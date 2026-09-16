// ===== 极简记账 · 记一笔（语音/文字 → 解析 → 确认）=====

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../services/parser.dart';
import '../services/notifications.dart';
import '../widgets/charts.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    final all = await appDb.txns();
    final now = DateTime.now();
    _today = all
        .where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    final ok = _speech.isAvailable ? true : await _speech.initialize();
    if (!ok) {
      _toast('当前设备不支持语音，请用输入框');
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'zh_CN',
      onResult: (r) {
        if (r.finalResult) {
          setState(() => _listening = false);
          _parseText(r.recognizedWords);
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _parseText(String text) async {
    if (text.trim().isEmpty) {
      _toast('先说一句或打一句');
      return;
    }
    final r = parse(text, _accounts);
    final saved = await _showConfirm(r);
    if (saved == true) {
      _input.clear();
      await reminder.refresh();
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
      await appDb.addTxn(txn);
      return true;
    }
    return null;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 麦克风
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTapDown: (_) => _startListening(),
                onTapUp: (_) => _stopListening(),
                onTapCancel: _stopListening,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _listening
                          ? const [Color(0xFF1D4ED8), Color(0xFF1E40AF)]
                          : const [Color(0xFF3B82F6), Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x592563EB), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: const Icon(Icons.mic_none, color: Colors.white, size: 48),
                ),
              ),
              const SizedBox(height: 14),
              Text(_listening ? '正在聆听，松手结束…' : '按住说话，松手自动记账', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 输入框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                  hintText: '打字兜底，例如：昨天中午吃麦当劳花了三十二',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  isDense: true,
                ),
                onSubmitted: _parseText,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => _parseText(_input.text), child: const Text('记账')),
          ],
        ),
        const SizedBox(height: 20),
        // 今日流水
        const Text('今日流水', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (_today.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('今天还没记账', style: TextStyle(color: Colors.grey)))
        else
          ..._today.map((t) => _txnTile(t)),
      ],
    );
  }

  Widget _txnTile(Txn t) {
    final sign = t.type == TxnType.expense ? '-' : (t.type == TxnType.income ? '+' : '');
    final color = t.type == TxnType.expense
        ? kExpense
        : (t.type == TxnType.income ? kIncome : Colors.grey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.initial.type;
    _amount = widget.initial.amount ?? 0;
    _amountCtrl.text = _amount == 0 ? '' : _amount.toString();
    _c1 = widget.initial.category1 ?? defaultC1For(_type);
    _c2 = widget.initial.category2 ?? defaultC2(_c1);
    _accountId = widget.initial.accountId ?? (widget.accounts.isNotEmpty ? widget.accounts.first.id : '');
    _toAccountId = widget.initial.toAccountId ?? (widget.accounts.isNotEmpty ? widget.accounts.first.id : '');
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
    final all = await appDb.txns();
    _recentExpenses = all.where((t) => t.type == TxnType.expense && !t.refunded && t.refundOf == null).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() {});
  }

  String defaultC1For(TxnType type) => categoriesFor(type).first.name;

  void _save() {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写金额')));
      return;
    }
    if (_type != TxnType.transfer && _accountId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择账户')));
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
              if (_type != TxnType.transfer)
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
    if (widget.accounts.isEmpty) {
      return Text('$label：暂无账户', style: const TextStyle(color: Colors.grey, fontSize: 12));
    }
    final ids = widget.accounts.map((a) => a.id).toList();
    final v = ids.contains(value) ? value : ids.first;
    return _labeled(label, DropdownButton<String>(
      value: v,
      isExpanded: true,
      items: widget.accounts.map((a) => DropdownMenuItem<String>(value: a.id, child: Text('${a.name}（${a.currency}）', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    ));
  }
}
