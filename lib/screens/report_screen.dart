// ===== 极简记账 · 报表（日/周/月/年 + 自定义；饼图/排行/趋势）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../widgets/charts.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _period = 'month';
  int _offset = 0;
  String _cat1 = '全部';
  String _cat2 = '全部';
  String _pieLevel = 'c1';
  String _trendMode = 'both';
  DateTimeRange? _custom;

  List<Txn> _txns = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _txns = await appDb.txns();
    _accounts = await appDb.accounts();
    if (mounted) setState(() {});
  }

  ({DateTime start, DateTime end}) _range() {
    final now = DateTime.now();
    DateTime start, end;
    if (_period == 'day') {
      start = DateTime(now.year, now.month, now.day + _offset);
      end = start.add(const Duration(days: 1));
    } else if (_period == 'week') {
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1) + _offset * 7);
      start = DateTime(monday.year, monday.month, monday.day);
      end = start.add(const Duration(days: 7));
    } else if (_period == 'month') {
      start = DateTime(now.year, now.month + _offset, 1);
      end = DateTime(now.year, now.month + _offset + 1, 1);
    } else if (_period == 'year') {
      start = DateTime(now.year + _offset, 1, 1);
      end = DateTime(now.year + _offset + 1, 1, 1);
    } else {
      start = _custom?.start ?? DateTime(now.year, now.month, now.day);
      end = (_custom?.end ?? DateTime(now.year, now.month, now.day)).add(const Duration(days: 1));
    }
    return (start: start, end: end);
  }

  String _label() {
    final r = _range();
    if (_period == 'day') return '${r.start.year}年${r.start.month}月${r.start.day}日';
    if (_period == 'year') return '${r.start.year}年';
    if (_period == 'month') return '${r.start.year}年${r.start.month}月';
    if (_period == 'custom') {
      final e = r.end.subtract(const Duration(days: 1));
      return '${r.start.month}/${r.start.day} ~ ${e.month}/${e.day}';
    }
    final e = r.end.subtract(const Duration(days: 1));
    return '${r.start.month}/${r.start.day} ~ ${e.month}/${e.day}';
  }

  bool _inFilter(Txn t) {
    if (_cat1 != '全部' && t.category1 != _cat1) return false;
    if (_cat2 != '全部' && t.category2 != _cat2) return false;
    return true;
  }

  List<Txn> _inRange() {
    final r = _range();
    return _txns.where((t) => !t.isVoid && !t.date.isBefore(r.start) && t.date.isBefore(r.end) && _inFilter(t)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _inRange();
    final expense = list.where((t) => t.type == TxnType.expense).fold<double>(0, (s, t) => s + t.amount);
    final income = list.where((t) => t.type == TxnType.income).fold<double>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 周期切换
        Row(
          children: [
            ...['day', 'week', 'month', 'year'].map((p) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Center(child: Text(p == 'day' ? '日' : p == 'week' ? '周' : p == 'month' ? '月' : '年')),
                      selected: _period == p,
                      onSelected: (_) => setState(() { _period = p; _offset = 0; _custom = null; }),
                    ),
                  ),
                )),
            IconButton(
              icon: const Icon(Icons.calendar_month),
              color: _period == 'custom' ? kBlue : null,
              onPressed: _pickRange,
            ),
          ],
        ),
        // 翻页
        Row(
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: _period == 'custom' ? null : () => setState(() => _offset--)),
            Expanded(child: Center(child: Text(_label(), style: const TextStyle(fontWeight: FontWeight.w600)))),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: _period == 'custom' ? null : () => setState(() => _offset++)),
          ],
        ),
        const SizedBox(height: 8),
        // 总额
        Row(
          children: [
            _sumCell('支出', fmtNum(expense), kExpense),
            _sumCell('收入', fmtNum(income), kIncome),
            _sumCell('结余', fmtNum(income - expense), kBlue),
          ],
        ),
        const SizedBox(height: 12),
        // 分类筛选
        Row(
          children: [
            Expanded(child: _c1Dropdown()),
            const SizedBox(width: 8),
            Expanded(child: _c2Dropdown()),
          ],
        ),
        const SizedBox(height: 16),
        // 饼图
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(label: const Text('按一级'), selected: _pieLevel == 'c1', onSelected: (_) => setState(() => _pieLevel = 'c1')),
                    ChoiceChip(label: const Text('按二级'), selected: _pieLevel == 'c2', onSelected: (_) => setState(() => _pieLevel = 'c2')),
                  ],
                ),
                const SizedBox(height: 12),
                _pie(list),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 排行
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('排行榜', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._rank(list),
              ],
            ),
          ),
        ),
        // 趋势（仅年）
        if (_period == 'year') ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('趋势', style: TextStyle(fontWeight: FontWeight.w600)),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(label: const Text('对比'), selected: _trendMode == 'both', onSelected: (_) => setState(() => _trendMode = 'both')),
                          ChoiceChip(label: const Text('支出'), selected: _trendMode == 'expense', onSelected: (_) => setState(() => _trendMode = 'expense')),
                          ChoiceChip(label: const Text('收入'), selected: _trendMode == 'income', onSelected: (_) => setState(() => _trendMode = 'income')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BarChartView(buckets: _yearBuckets(), mode: _trendMode),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null) setState(() { _period = 'custom'; _custom = picked; _offset = 0; });
  }

  Widget _sumCell(String k, String v, Color c) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 3),
            Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c)),
          ],
        ),
      ),
    );
  }

  Widget _c1Dropdown() {
    final opts = ['全部', ...expenseCategories.map((c) => c.name), ...incomeCategories.map((c) => c.name)];
    return DropdownButton<String>(
      value: _cat1,
      isExpanded: true,
      items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => setState(() { _cat1 = v ?? '全部'; _cat2 = '全部'; }),
    );
  }

  Widget _c2Dropdown() {
    List<String> opts = ['全部'];
    for (final g in [...expenseCategories, ...incomeCategories]) {
      if (g.name == _cat1) opts.addAll(g.children);
    }
    return DropdownButton<String>(
      value: opts.contains(_cat2) ? _cat2 : '全部',
      isExpanded: true,
      items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => setState(() => _cat2 = v ?? '全部'),
    );
  }

  Widget _pie(List<Txn> list) {
    final exp = list.where((t) => t.type == TxnType.expense).toList();
    final groups = <String, double>{};
    for (final t in exp) {
      final k = _pieLevel == 'c1' ? (t.category1 ?? '其他') : (t.category2 ?? t.category1 ?? '其他');
      groups[k] = (groups[k] ?? 0) + t.amount;
    }
    final slices = groups.entries.map((e) => PieSlice(e.key, e.value)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return PieChartView(slices: slices);
  }

  List<Widget> _rank(List<Txn> list) {
    final exp = list.where((t) => t.type == TxnType.expense).toList();
    final groups = <String, double>{};
    for (final t in exp) {
      final k = _pieLevel == 'c1' ? (t.category1 ?? '其他') : (t.category2 ?? t.category1 ?? '其他');
      groups[k] = (groups[k] ?? 0) + t.amount;
    }
    final entries = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const [Text('暂无支出', style: TextStyle(color: Colors.grey))];
    final maxV = entries.first.value;
    return entries.take(6).map((e) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 20, child: Text('${entries.indexOf(e) + 1}', style: const TextStyle(color: kBlue, fontSize: 12))),
            Expanded(child: Text(e.key)),
            Text(fmtNum(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            SizedBox(width: 60, child: LinearProgressIndicator(value: maxV == 0 ? 0 : e.value / maxV, minHeight: 6, backgroundColor: const Color(0xFFE8EFFF), color: kBlue)),
          ],
        ),
      );
    }).toList();
  }

  List<BarBucket> _yearBuckets() {
    final r = _range();
    final buckets = <BarBucket>[];
    for (var m = 1; m <= 12; m++) {
      final s = DateTime(r.start.year, m, 1);
      final e = DateTime(r.start.year, m + 1, 1);
      double ex = 0, inc = 0;
      for (final t in _txns) {
        if (t.isVoid || !_inFilter(t)) continue;
        if (t.date.isBefore(s) || !t.date.isBefore(e)) continue;
        if (t.type == TxnType.expense) ex += t.amount;
        if (t.type == TxnType.income) inc += t.amount;
      }
      buckets.add(BarBucket('$m月', ex, inc));
    }
    return buckets;
  }
}
