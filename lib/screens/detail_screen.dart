// ===== 极简记账 · 明细（账单式：时间 + 余额）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../widgets/charts.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  List<Account> _accounts = [];
  List<Txn> _txns = [];
  Map<String, double> _balance = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    _txns = await appDb.txns();
    _txns.sort((a, b) => b.date.compareTo(a.date));
    _balance = _computeBalance();
    if (mounted) setState(() {});
  }

  Map<String, double> _computeBalance() {
    final cur = <String, double>{for (final a in _accounts) a.id: a.balance};
    final sorted = [..._txns]..sort((a, b) => a.date.compareTo(b.date));
    final sums = <String, double>{};
    final after = <String, double>{};
    for (var i = sorted.length - 1; i >= 0; i--) {
      final t = sorted[i];
      final eff = <String, double>{};
      if (t.type == TxnType.transfer) {
        eff[t.accountId] = -t.amount;
        if (t.toAccountId != null) eff[t.toAccountId!] = (eff[t.toAccountId!] ?? 0) + t.amount;
      } else if (t.type == TxnType.income) {
        eff[t.accountId] = t.amount;
      } else {
        eff[t.accountId] = -t.amount;
      }
      after[t.id] = (cur[t.accountId] ?? 0) - (sums[t.accountId] ?? 0);
      eff.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
    }
    return after;
  }

  String _catLabel(Txn t) {
    if (t.type == TxnType.transfer) return '转账';
    return (t.category2 != null && t.category2!.isNotEmpty && t.category2 != t.category1)
        ? '${t.category1} · ${t.category2}'
        : (t.category1 ?? '其他');
  }

  @override
  Widget build(BuildContext context) {
    if (_txns.isEmpty) {
      return const Center(child: Text('还没有任何流水', style: TextStyle(color: Colors.grey)));
    }
    return Container(
      color: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _txns.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F2F5)),
        itemBuilder: (context, i) {
          final t = _txns[i];
          final acc = _accounts.where((a) => a.id == t.accountId).toList();
          final accName = acc.isNotEmpty ? acc.first.name : '';
          final toName = t.toAccountId == null ? '' : (_accounts.where((a) => a.id == t.toAccountId).toList().isNotEmpty ? _accounts.where((a) => a.id == t.toAccountId).toList().first.name : '');
          final sign = t.type == TxnType.expense ? '-' : (t.type == TxnType.income ? '+' : '');
          final color = t.type == TxnType.expense ? kExpense : (t.type == TxnType.income ? kIncome : Colors.grey);
          final title = t.type == TxnType.transfer ? '转账' : (t.note ?? (t.category2 ?? t.category1 ?? '支出'));
          final sub = t.type == TxnType.transfer ? '$accName → $toName' : '${t.category1 ?? '其他'}（$accName）';
          final bal = _balance[t.id];
          return InkWell(
            onTap: () => _edit(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text('${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')} ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$sign${fmtNum(t.amount)}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                      if (bal != null) ...[
                        const SizedBox(height: 4),
                        Text('余额 ${fmtNum(bal)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(Txn t) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSheet(txn: t, accounts: _accounts),
    );
    if (changed == true) await _load();
  }
}

// ---------- 编辑/删除 ----------
class _EditSheet extends StatefulWidget {
  final Txn txn;
  final List<Account> accounts;
  const _EditSheet({required this.txn, required this.accounts});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late TxnType _type;
  late double _amount;
  late String _c1, _c2, _accountId;
  String? _toAccountId;
  late DateTime _date;
  late String _note;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.txn.type;
    _amount = widget.txn.amount;
    _c1 = widget.txn.category1 ?? categoriesFor(_type).first.name;
    _c2 = widget.txn.category2 ?? defaultC2(_c1);
    _accountId = widget.txn.accountId;
    _toAccountId = widget.txn.toAccountId;
    _date = widget.txn.date;
    _note = widget.txn.note ?? '';
    _amountCtrl.text = _amount.toString();
    _noteCtrl.text = _note;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount <= 0) return;
    await appDb.updateTxn(Txn(
      id: widget.txn.id,
      type: _type,
      amount: _amount,
      category1: _type == TxnType.transfer ? null : _c1,
      category2: _type == TxnType.transfer ? '' : _c2,
      accountId: _accountId,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      note: _note.trim().isEmpty ? null : _note.trim(),
      date: _date,
      createdAt: widget.txn.createdAt,
      refundOf: widget.txn.refundOf,
      refunded: widget.txn.refunded,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await appDb.deleteTxn(widget.txn.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('编辑明细', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: TxnType.values.map((t) => ChoiceChip(label: Text(t.label), selected: _type == t, onSelected: (_) => setState(() => _type = t))).toList(),
              ),
              const SizedBox(height: 12),
              TextField(controller: _amountCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '金额'), onChanged: (v) => _amount = double.tryParse(v) ?? 0),
              const SizedBox(height: 12),
              if (_type != TxnType.transfer)
                Row(
                  children: [
                    Expanded(child: _dropdown(categoriesFor(_type).map((c) => c.name).toList(), _c1, (v) => setState(() { _c1 = v!; _c2 = defaultC2(v); }))),
                    const SizedBox(width: 8),
                    Expanded(child: _dropdown(_c2Options(), _c2, (v) => setState(() => _c2 = v!))),
                  ],
                ),
              const SizedBox(height: 12),
              if (_type == TxnType.transfer)
                Row(
                  children: [
                    Expanded(child: _accountDropdown('转出', _accountId, (v) => setState(() => _accountId = v!))),
                    const SizedBox(width: 8),
                    Expanded(child: _accountDropdown('转入', _toAccountId ?? '', (v) => setState(() => _toAccountId = v!))),
                  ],
                )
              else
                _accountDropdown('账户', _accountId, (v) => setState(() => _accountId = v!)),
              const SizedBox(height: 12),
              TextField(controller: _noteCtrl, decoration: const InputDecoration(labelText: '备注'), onChanged: (v) => _note = v),
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
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: _delete, style: OutlinedButton.styleFrom(foregroundColor: kExpense), child: const Text('删除'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
                ],
              ),
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

  Widget _dropdown(List<String> opts, String value, ValueChanged<String?> onChanged) {
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
    return DropdownButton<String>(
      value: v,
      isExpanded: true,
      items: widget.accounts.map((a) => DropdownMenuItem<String>(value: a.id, child: Text('${a.name}（${a.currency}）', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}
