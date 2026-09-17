// ===== 极简记账 · 明细（账单式：时间 + 余额，点一笔可修改/删除）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../services/database.dart';
import '../widgets/charts.dart';
import '../widgets/edit_sheet.dart';

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
      child: Column(
        children: [
          // 让「能改、能删」这件事一眼可见
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: const Color(0xFFF4F6F9),
            child: const Text('点任意一笔，可以修改或删除', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _txns.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F2F5)),
              itemBuilder: (context, i) {
                final t = _txns[i];
                final acc = _accounts.where((a) => a.id == t.accountId).toList();
                final accName = acc.isNotEmpty ? acc.first.name : '';
                final toList = _accounts.where((a) => a.id == t.toAccountId).toList();
                final toName = toList.isNotEmpty ? toList.first.name : '';
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
                              Text(t.refunded ? '$sub（已退款冲销）' : sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Txn t) async {
    final changed = await showEditSheet(context, t, _accounts);
    if (changed == true) await _load();
  }
}
