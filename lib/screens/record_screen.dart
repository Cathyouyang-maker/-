// ===== 极简记账 · 记一笔（语音/文字 → 解析 → 确认）=====

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../services/parser.dart';
import '../services/notifications.dart';
import '../widgets/charts.dart';
import '../widgets/account_sheet.dart';
import '../widgets/edit_sheet.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  List<Account> _accounts = [];
  List<Txn> _today = [];
  final TextEditingController _input = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  bool _busy = false;
  bool _speechInited = false;
  String _heard = '';
  Timer? _autoStop;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoStop?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _accounts = await appDb.accounts();
      final all = await appDb.txns();
      final now = DateTime.now();
      _today = all
          .where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('读数据失败: $e');
    }
    if (mounted) setState(() {});
  }

  // ---------- 语音：点一下开始，再点一下结束 ----------
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopVoice();
    } else {
      await _startVoice();
    }
  }

  Future<void> _startVoice() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!_speechInited) {
        final ok = await _speech.initialize(
          onError: (e) => _onSpeechError(e.errorMsg),
          onStatus: (s) {
            if (s == 'done' || s == 'notListening') _finishVoice();
          },
        );
        _speechInited = true;
        if (!ok) {
          _toast('语音用不了：请到手机「设置 → 应用 → 极简记账 → 权限」打开麦克风；也可以直接在下面打字');
          return;
        }
      }
      _heard = '';
      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        localeId: await _zhLocale(),
        onResult: (r) {
          final t = r.recognizedWords.toString();
          if (t.isNotEmpty) {
            _heard = t;
            if (mounted) setState(() => _input.text = t);
          }
          if (r.finalResult) _finishVoice();
        },
      );
      _autoStop?.cancel();
      _autoStop = Timer(const Duration(seconds: 30), _stopVoice);
    } catch (e) {
      if (mounted) setState(() => _listening = false);
      _toast('语音启动失败：$e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _stopVoice() async {
    try {
      await _speech.stop();
    } catch (_) {}
    _finishVoice();
  }

  /// 中文识别器（找不到就用系统默认）
  Future<String?> _zhLocale() async {
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('zh')) return l.localeId;
      }
    } catch (_) {}
    return null;
  }

  void _finishVoice() {
    if (!_listening) return;
    _autoStop?.cancel();
    if (mounted) setState(() => _listening = false);
    final text = _heard.trim();
    if (text.isEmpty) {
      _toast('没听清，再说一次，或者直接打字');
      return;
    }
    _parseText(text);
  }

  void _onSpeechError(String? msg) {
    _autoStop?.cancel();
    if (mounted) setState(() => _listening = false);
    _toast('语音没成功（${msg ?? '未知原因'}），可以直接打字');
  }

  // ---------- 记账 ----------
  Future<void> _parseText(String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      _toast('先说一句或打一句');
      return;
    }
    try {
      _accounts = await appDb.accounts(); // 保证账户是最新的
    } catch (_) {}
    if (!mounted) return;
    final r = parse(t, _accounts);
    final saved = await _showConfirm(r);
    if (saved == true) {
      _input.clear();
      _heard = '';
      try {
        await reminder.refresh();
      } catch (_) {}
      await _load();
    }
  }

  Future<bool?> _showConfirm(ParseResult r) async {
    final txn = await showModalBottomSheet<Txn>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(initial: r, accounts: _accounts),
    );
    if (txn != null) {
      try {
        await appDb.addTxn(txn);
      } catch (e) {
        _toast('保存失败：$e');
        return null;
      }
      return true;
    }
    return null;
  }

  Future<void> _newAccount() async {
    await showAccountSheet(context);
    await _load();
  }

  Future<void> _editTxn(Txn t) async {
    final changed = await showEditSheet(context, t, _accounts);
    if (changed == true) await _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_accounts.isEmpty) _noAccountCard(),
        // 输入框 + 麦克风（在输入框右侧）+ 记账
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: InputDecoration(
                  hintText: _listening ? '正在听…说完点一下麦克风' : '说一句或打一句，如：昨天中午吃麦当劳花了三十二',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    tooltip: _listening ? '结束' : '语音记账',
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _listening ? Icons.stop_circle : Icons.mic_none,
                      size: 24,
                      color: _listening ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                onSubmitted: _parseText,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => _parseText(_input.text), child: const Text('记账')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _listening ? '正在聆听…说完再点一下麦克风' : '点输入框右边的麦克风开始，说完再点一下结束',
          style: TextStyle(fontSize: 12, color: _listening ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF)),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('今日流水', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_today.isNotEmpty)
              const Text('点一笔可修改 / 删除', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
        const SizedBox(height: 4),
        if (_today.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('今天还没记账', style: TextStyle(color: Colors.grey)))
        else
          ..._today.map((t) => _txnTile(t)),
      ],
    );
  }

  Widget _noAccountCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: const Color(0xFFE8EFFF), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('还没有账户', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
                SizedBox(height: 2),
                Text('先建一个（现金 / 微信 / 支付宝都行），才记得了账', style: TextStyle(fontSize: 12, color: Color(0xFF3B5BDB))),
              ],
            ),
          ),
          TextButton(onPressed: _newAccount, child: const Text('建账户')),
        ],
      ),
    );
  }

  Widget _txnTile(Txn t) {
    final sign = t.type == TxnType.expense ? '-' : (t.type == TxnType.income ? '+' : '');
    final color = t.type == TxnType.expense
        ? kExpense
        : (t.type == TxnType.income ? kIncome : Colors.grey);
    return InkWell(
      onTap: () => _editTxn(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_catLabel(t), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_noteText(t), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Text('$sign${fmtNum(t.amount)}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

String _catLabel(Txn t) {
  if (t.type == TxnType.transfer) return '转账';
  return (t.category2 != null && t.category2!.isNotEmpty && t.category2 != t.category1)
      ? '${t.category1} · ${t.category2}'
      : (t.category1 ?? '其他');
}

String _noteText(Txn t) {
  if (t.note != null && t.note!.isNotEmpty) return t.note!;
  return t.type == TxnType.transfer ? '转给账户' : '—';
}

// ---------- 确认层 ----------
class _ConfirmSheet extends StatefulWidget {
  final ParseResult initial;
  final List<Account> accounts;
  const _ConfirmSheet({required this.initial, required this.accounts});
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late TxnType _type;
  late double _amount;
  String _c1 = '';
  String _c2 = '';
  String _accountId = '';
  String _toAccountId = '';
  late DateTime _date;
  String _note = '';
  String? _refundOf;
  List<Txn> _recentExpenses = [];
  late List<Account> _accs;
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accs = [...widget.accounts];
    _type = widget.initial.type;
    _amount = widget.initial.amount ?? 0;
    _amountCtrl.text = _amount == 0 ? '' : _amount.toString();
    _c1 = widget.initial.category1 ?? defaultC1For(_type);
    _c2 = widget.initial.category2 ?? defaultC2(_c1);
    _accountId = widget.initial.accountId ?? (_accs.isNotEmpty ? _accs.first.id : '');
    _toAccountId = widget.initial.toAccountId ?? (_accs.isNotEmpty ? _accs.first.id : '');
    _date = widget.initial.date;
    _note = widget.initial.note;
    _noteCtrl.text = _note;
    _loadRecent();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final all = await appDb.txns();
      _recentExpenses = all.where((t) => t.type == TxnType.expense && !t.refunded && t.refundOf == null).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String defaultC1For(TxnType type) => categoriesFor(type).first.name;

  /// 确认层里也能直接建账户（首次使用最容易卡在这）
  Future<void> _newAccount() async {
    final ok = await showAccountSheet(context);
    if (ok != true) return;
    final list = await appDb.accounts();
    if (!mounted) return;
    setState(() {
      _accs = list;
      if (list.isNotEmpty) {
        if (_accountId.isEmpty) _accountId = list.first.id;
        if (_toAccountId.isEmpty) _toAccountId = list.first.id;
      }
    });
  }

  void _save() {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写金额')));
      return;
    }
    if (_type != TxnType.transfer && _accountId.isEmpty) {
      if (_accs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('先建一个账户（钱放在哪儿）')));
        _newAccount();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择账户')));
      }
      return;
    }
    if (_type == TxnType.transfer && (_accountId.isEmpty || _toAccountId.isEmpty || _accountId == _toAccountId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择不同的转出/转入账户')));
      return;
    }
    final txn = Txn(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      amount: _amount,
      category1: _type == TxnType.transfer ? null : _c1,
      category2: _type == TxnType.transfer ? '' : _c2,
      accountId: _accountId,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      note: _note.trim().isEmpty ? null : _note.trim(),
      date: DateTime(_date.year, _date.month, _date.day, DateTime.now().hour, DateTime.now().minute),
      createdAt: DateTime.now(),
      refundOf: _type == TxnType.income ? _refundOf : null,
    );
    Navigator.pop(context, txn);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('确认这笔账', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              // 类型
              Wrap(
                spacing: 8,
                children: TxnType.values.map((t) => ChoiceChip(
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() {
                        _type = t;
                        _c1 = defaultC1For(t);
                        _c2 = defaultC2(_c1);
                      }),
                    )).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: '金额'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                controller: _amountCtrl,
                onChanged: (v) => _amount = double.tryParse(v) ?? 0,
              ),
              const SizedBox(height: 12),
              if (_type != TxnType.transfer) ...[
                Row(
                  children: [
                    Expanded(child: _catDropdown(categoriesFor(_type).map((c) => c.name).toList(), _c1, (v) => setState(() { _c1 = v!; _c2 = defaultC2(v); }))),
                    const SizedBox(width: 8),
                    Expanded(child: _catDropdown(_c2Options(), _c2, (v) => setState(() => _c2 = v!))),
                  ],
                ),
                if (_type == TxnType.income && _recentExpenses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _labeled('冲销某笔支出（可选）', DropdownButton<String?>(
                    value: _refundOf,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('不关联')),
                      ..._recentExpenses.map((e) => DropdownMenuItem<String?>(
                            value: e.id,
                            child: Text('${_catLabel(e)} · ${fmtNum(e.amount)}（${e.date.month}/${e.date.day}）', overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => _refundOf = v),
                  )),
                ],
              ] else ...[
                Row(
                  children: [
                    Expanded(child: _accountDropdown('转出', _accountId, (v) => setState(() => _accountId = v!))),
                    const SizedBox(width: 8),
                    Expanded(child: _accountDropdown('转入', _toAccountId, (v) => setState(() => _toAccountId = v!))),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (_type != TxnType.transfer && _accs.isEmpty)
                Row(
                  children: [
                    const Expanded(child: Text('还没有账户，先建一个', style: TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                    TextButton(onPressed: _newAccount, child: const Text('＋ 新建账户')),
                  ],
                )
              else if (_type != TxnType.transfer)
                _accountDropdown('账户', _accountId, (v) => setState(() => _accountId = v!)),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: '备注'),
                controller: _noteCtrl,
                onChanged: (v) => _note = v,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setState(() => _date = d);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _c2Options() {
    for (final g in categoriesFor(_type)) {
      if (g.name == _c1) return g.children;
    }
    return const [];
  }

  Widget _labeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        child,
      ],
    );
  }

  Widget _catDropdown(List<String> opts, String value, ValueChanged<String?> onChanged) {
    return DropdownButton<String>(
      value: opts.contains(value) ? value : (opts.isNotEmpty ? opts.first : null),
      isExpanded: true,
      items: opts.map((o) => DropdownMenuItem<String>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _accountDropdown(String label, String value, ValueChanged<String?> onChanged) {
    if (_accs.isEmpty) {
      return Text('$label：暂无账户', style: const TextStyle(color: Colors.grey, fontSize: 12));
    }
    final ids = _accs.map((a) => a.id).toList();
    final v = ids.contains(value) ? value : ids.first;
    return _labeled(label, DropdownButton<String>(
      value: v,
      isExpanded: true,
      items: _accs.map((a) => DropdownMenuItem<String>(value: a.id, child: Text('${a.name}（${a.currency}）', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    ));
  }
}
