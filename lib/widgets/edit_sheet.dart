// ===== 极简记账 · 编辑/删除流水（共享组件）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../widgets/charts.dart';

Future<bool?> showEditSheet(BuildContext context, Txn t, List<Account> accounts) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EditSheet(txn: t, accounts: accounts),
  );
}

class EditSheet extends StatefulWidget {
  final Txn txn;
  final List<Account> accounts;
  const EditSheet({super.key, required this.txn, required this.accounts});
  @override
  State<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<EditSheet> {
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
    if (!(_amount > 0)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('金额要大于 0')));
      return;
    }
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这笔账'),
        content: const Text('删掉之后余额会一起还原，确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不删')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除', style: TextStyle(color: kExpense))),
        ],
      ),
    );
    if (ok != true) return;
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
              const Text('修改这笔账', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: TxnType.values
                    .map((t) => ChoiceChip(
                          label: Text(t.label),
                          selected: _type == t,
                          onSelected: (_) => setState(() {
                            _type = t;
                            _c1 = categoriesFor(t).first.name;
                            _c2 = defaultC2(_c1);
                          }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '金额'),
                onChanged: (v) => _amount = double.tryParse(v) ?? 0,
              ),
              const SizedBox(height: 12),
              if (_type != TxnType.transfer)
                Row(
                  children: [
                    Expanded(child: _dropdown(categoriesFor(_type).map((c) => c.name).toList(), _c1,
                        (v) => setState(() { _c1 = v!; _c2 = defaultC2(v); }))),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('分类', style: TextStyle(fontSize: 12, color: Colors.grey)),
        DropdownButton<String>(
          value: opts.contains(value) ? value : (opts.isNotEmpty ? opts.first : null),
          isExpanded: true,
          items: opts.map((o) => DropdownMenuItem<String>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _accountDropdown(String label, String value, ValueChanged<String?> onChanged) {
    if (widget.accounts.isEmpty) {
      return Text('$label：暂无账户', style: const TextStyle(color: Colors.grey, fontSize: 12));
    }
    final ids = widget.accounts.map((a) => a.id).toList();
    final v = ids.contains(value) ? value : ids.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        DropdownButton<String>(
          value: v,
          isExpanded: true,
          items: widget.accounts.map((a) => DropdownMenuItem<String>(value: a.id, child: Text('${a.name}（${a.currency}）', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
