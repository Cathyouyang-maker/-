// ===== 极简记账 · 分类明细（报表里点某个分类进入，看该分类下的所有流水）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../services/database.dart';
import '../widgets/charts.dart';
import '../widgets/edit_sheet.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String? c1;
  final String? c2;
  final DateTime start;
  final DateTime end;
  final String periodLabel;
  const CategoryDetailScreen({
    super.key,
    this.c1,
    this.c2,
    required this.start,
    required this.end,
    required this.periodLabel,
  });
  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  List<Account> _accounts = [];
  List<Txn> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    final all = await appDb.txns();
    _txns = all.where((t) {
      if (t.isVoid) return false;
      if (t.date.isBefore(widget.start) || !t.date.isBefore(widget.end)) return false;
      if (widget.c1 != null && t.category1 != widget.c1) return false;
      if (widget.c2 != null && t.category2 != widget.c2) return false;
      return true;
    }).toList();
    _txns.sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() {});
  }

  String get _title {
    if (widget.c2 != null) return '${widget.c1 ?? ''} · ${widget.c2}';
    if (widget.c1 != null) return widget.c1!;
    return '明细';
  }

  String _catLabel(Txn t) {
    if (t.type == TxnType.transfer) return '转账';
    return (t.category2 != null && t.category2!.isNotEmpty && t.category2 != t.category1)
        ? '${t.category1} · ${t.category2}'
        : (t.category1 ?? '其他');
  }

  @override
  Widget build(BuildContext context) {
    final expense = _txns.where((t) => t.type == TxnType.expense).fold(0.0, (s, t) => s + t.amount);
    final income = _txns.where((t) => t.type == TxnType.income).fold(0.0, (s, t) => s + t.amount);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: const Color(0xFFF4F6F9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.periodLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _cell('笔数', '${_txns.length}', kBlue),
                    _cell('支出', fmtNum(expense), kExpense),
                    _cell('收入', fmtNum(income), kIncome),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _txns.isEmpty
                ? const Center(child: Text('该分类下暂无流水', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _txns.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F2F5)),
                    itemBuilder: (context, i) {
                      final t = _txns[i];
                      final acc = _accounts.where((a) => a.id == t.accountId).toList();
                      final accName = acc.isNotEmpty ? acc.first.name : '';
                      final sign = t.type == TxnType.expense ? '-' : (t.type == TxnType.income ? '+' : '');
                      final color = t.type == TxnType.expense
                          ? kExpense
                          : (t.type == TxnType.income ? kIncome : Colors.grey);
                      final title = t.type == TxnType.transfer ? '转账' : (t.note ?? (t.category2 ?? t.category1 ?? '支出'));
                      final sub = t.type == TxnType.transfer ? accName : '${_catLabel(t)}（$accName）';
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
                                    Text(
                                        '${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')} ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text('$sign${fmtNum(t.amount)}',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String k, String v, Color c) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 3),
            Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c)),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Txn t) async {
    final changed = await showEditSheet(context, t, _accounts);
    if (changed == true) await _load();
  }
}
