// ===== 极简记账 · 账户明细（对账：期初 + 流水 = 结余）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../services/database.dart';
import '../widgets/charts.dart';
import '../widgets/edit_sheet.dart';

class AccountDetailScreen extends StatefulWidget {
  final Account account;
  const AccountDetailScreen({super.key, required this.account});
  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late Account _acc;
  List<Txn> _txns = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    _acc = _accounts.firstWhere((a) => a.id == widget.account.id, orElse: () => widget.account);
    _txns = await appDb.txnsByAccount(_acc.id);
    if (mounted) setState(() {});
  }

  ({double income, double expense, double inT, double outT}) _sums() {
    double income = 0, expense = 0, inT = 0, outT = 0;
    for (final t in _txns) {
      if (t.isVoid) continue;
      if (t.type == TxnType.transfer) {
        if (t.toAccountId == _acc.id) inT += t.amount;
        if (t.accountId == _acc.id) outT += t.amount;
      } else if (t.type == TxnType.income) {
        if (t.accountId == _acc.id) income += t.amount;
      } else {
        if (t.accountId == _acc.id) expense += t.amount;
      }
    }
    return (income: income, expense: expense, inT: inT, outT: outT);
  }

  @override
  Widget build(BuildContext context) {
    final s = _sums();
    final balance = _acc.balance;
    final start = balance - (s.income - s.expense + s.inT - s.outT);
    final consistent = (start + s.income - s.expense + s.inT - s.outT - balance).abs() < 0.005;

    return Scaffold(
      appBar: AppBar(title: Text(_acc.name)),
      body: Column(
        children: [
          // 当前结余
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kBlue, Color(0xFF1D4ED8)]),
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前结余', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${_acc.currency} ${fmtNum(balance)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 对账卡
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('对账', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        _row('期初（盘点）', start, false),
                        _row('＋ 收入', s.income, false, color: kIncome),
                        _row('－ 支出', s.expense, false, color: kExpense),
                        _row('＋ 转入', s.inT, false, color: kIncome),
                        _row('－ 转出', s.outT, false, color: kExpense),
                        const Divider(height: 16),
                        _row('＝ 结余', balance, true, color: kBlue),
                        if (!consistent)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('⚠ 数据异常：期初+流水≠结余，可能某笔记账有错', style: TextStyle(color: kExpense, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('流水（点击可修改 / 删除）', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 6),
                if (_txns.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('该账户还没有流水', style: TextStyle(color: Colors.grey))),
                ..._txns.map((t) => _item(t)).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, double v, bool bold, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal, color: bold ? Colors.black87 : Colors.grey[700]))),
          Text('${_acc.currency} ${fmtNum(v)}', style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: color ?? (bold ? kBlue : Colors.black87))),
        ],
      ),
    );
  }

  Widget _item(Txn t) {
    final isTransfer = t.type == TxnType.transfer;
    final isOut = isTransfer ? t.accountId == _acc.id : (t.type == TxnType.expense);
    final sign = isOut ? '-' : '+';
    final color = isOut ? kExpense : kIncome;
    String title;
    String sub;
    if (isTransfer) {
      final otherId = isOut ? t.toAccountId : t.accountId;
      final otherName = (otherId == null) ? '（未指定）' : _accounts.firstWhere((a) => a.id == otherId, orElse: () => _acc).name;
      title = isOut ? '转出 → $otherName' : '转入 ← $otherName';
      sub = '转账';
    } else {
      title = t.note ?? t.category1 ?? '其他';
      sub = t.category1 ?? '其他';
    }
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
                  Text('${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                ],
              ),
            ),
            Text('$sign${fmtNum(t.amount)}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
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
