// ===== 极简记账 · 解析引擎（纯本地规则，离线、秒出、免费）=====

import '../data/categories.dart';
import '../models.dart';

class AmountHit {
  final double value;
  final String text;
  AmountHit(this.value, this.text);
}

class ParseResult {
  double? amount;
  DateTime date;
  String? category1;
  String? category2;
  String? accountId;
  String? toAccountId;
  TxnType type;
  String note;

  ParseResult({
    this.amount,
    required this.date,
    this.category1,
    this.category2,
    this.accountId,
    this.toAccountId,
    this.type = TxnType.expense,
    this.note = '',
  });
}

// ---------- 中文数字 ----------
const Map<String, int> _cnDigits = {'零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
const Map<String, int> _cnUnits = {'十': 10, '百': 100, '千': 1000, '万': 10000, '亿': 100000000};

int cnToNum(String s) {
  s = s.replaceAll('两', '二');
  int total = 0, section = 0, num = 0, lastUnit = 0;
  final hasZero = s.contains('零');
  for (final ch in s.split('')) {
    if (_cnDigits.containsKey(ch)) {
      num = _cnDigits[ch]!;
    } else if (_cnUnits.containsKey(ch)) {
      final u = _cnUnits[ch]!;
      lastUnit = u;
      if (u >= 10000) {
        section = (section + num) * u;
        total += section;
        section = 0;
      } else {
        section += (num == 0 ? 1 : num) * u;
      }
      num = 0;
    }
  }
  if (num > 0 && lastUnit >= 10 && !hasZero) {
    section += num * (lastUnit ~/ 10);
    num = 0;
  }
  return total + section + num;
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

// ---------- 金额抽取 ----------
final _cnNumRe = '[零一二两三四五六七八九十百千万亿]';
final _cnDigitRe = '[零一二两三四五六七八九]';

AmountHit? extractAmount(String text) {
  final m1 = RegExp('($_cnNumRe+)\\s*[块元]\\s*($_cnDigitRe)?\\s*[毛角]?').firstMatch(text);
  if (m1 != null) {
    final yuan = cnToNum(m1.group(1)!);
    final jiao = m1.group(2) != null ? cnToNum(m1.group(2)!) * 0.1 : 0.0;
    return AmountHit(_r2(yuan + jiao), m1.group(0)!);
  }
  final m2 = RegExp('$_cnNumRe+[毛角分]?').firstMatch(text);
  if (m2 != null) {
    final s = m2.group(0)!;
    double n = cnToNum(s.replaceAll(RegExp('[毛角分]'), '')).toDouble();
    if (s.contains('分')) {
      n *= 0.01;
    } else if (s.contains('毛') || s.contains('角')) {
      n *= 0.1;
    }
    return AmountHit(_r2(n), s);
  }
  final m3 = RegExp('(\\d+)\\s*[块元]\\s*(\\d)?\\s*[毛角]?').firstMatch(text);
  if (m3 != null) {
    final jiao = m3.group(2) != null ? int.parse(m3.group(2)!) * 0.1 : 0.0;
    return AmountHit(_r2(int.parse(m3.group(1)!) + jiao), m3.group(0)!);
  }
  final m4 = RegExp('(\\d+(?:\\.\\d+)?)\\s*(万|千)?\\s*([块元毛角分])?').firstMatch(text);
  if (m4 != null) {
    double n = double.parse(m4.group(1)!);
    if (m4.group(2) == '万') n *= 10000;
    if (m4.group(2) == '千') n *= 1000;
    final u = m4.group(3);
    if (u == '毛' || u == '角') n *= 0.1;
    if (u == '分') n *= 0.01;
    return AmountHit(_r2(n), m4.group(0)!);
  }
  return null;
}

// ---------- 日期抽取 ----------
DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _startOfWeek(DateTime d) {
  final x = _startOfDay(d);
  final dow = (x.weekday + 6) % 7; // 周一=0
  return x.subtract(Duration(days: dow));
}

const Map<String, int> _weekIdx = {'一': 0, '二': 1, '三': 2, '四': 3, '五': 4, '六': 5, '日': 6, '天': 6};

({DateTime date, String text}) extractDate(String text) {
  final now = _startOfDay(DateTime.now());
  if (text.contains('大前天')) return (date: now.subtract(const Duration(days: 3)), text: '大前天');
  if (text.contains('前天')) return (date: now.subtract(const Duration(days: 2)), text: '前天');
  if (text.contains('昨天')) return (date: now.subtract(const Duration(days: 1)), text: '昨天');
  if (text.contains('今天')) return (date: now, text: '今天');

  final m = RegExp('(上|这|本)?周([一二三四五六日天])').firstMatch(text);
  if (m != null) {
    final idx = _weekIdx[m.group(2)!]!;
    var d = _startOfWeek(now).add(Duration(days: idx));
    if (m.group(1) == '上') d = d.subtract(const Duration(days: 7));
    return (date: d, text: m.group(0)!);
  }

  final m2 = RegExp('(\\d{1,2})月(\\d{1,2})([日号])?').firstMatch(text);
  if (m2 != null) {
    final mo = int.parse(m2.group(1)!), day = int.parse(m2.group(2)!);
    var d = DateTime(now.year, mo, day);
    if (d.isAfter(now)) d = DateTime(now.year - 1, mo, day);
    return (date: _startOfDay(d), text: m2.group(0)!);
  }

  final m3 = RegExp('(\\d{1,2})[号日]').firstMatch(text);
  if (m3 != null) {
    final day = int.parse(m3.group(1)!);
    var d = DateTime(now.year, now.month, day);
    if (d.isAfter(now)) d = DateTime(now.year, now.month - 1, day);
    return (date: _startOfDay(d), text: m3.group(0)!);
  }

  return (date: now, text: '');
}

// ---------- 分类匹配（最长命中）----------
final List<List<String>> _dictSorted = [...dict]..sort((a, b) => b[0].length.compareTo(a[0].length));

({String c1, String c2})? matchCategory(String text) {
  for (final e in _dictSorted) {
    if (text.contains(e[0])) return (c1: e[1], c2: e[2]);
  }
  return null;
}

// ---------- 账户匹配（按出现顺序）----------
List<Account> findAccounts(String text, List<Account> accounts) {
  final hits = <(Account, int)>[];
  for (final a in accounts) {
    if (a.name.isNotEmpty && text.contains(a.name)) {
      hits.add((a, text.indexOf(a.name)));
    }
  }
  hits.sort((x, y) => x.$2.compareTo(y.$2));
  return hits.map((h) => h.$1).toList();
}

// ---------- 备注构建 ----------
String buildNote(String working) {
  final sorted = [...stopwords]..sort((a, b) => b.length.compareTo(a.length));
  for (final w in sorted) {
    working = working.replaceAll(w, '');
  }
  // 清掉标点（句号、逗号、括号等）
  working = working.replaceAll(RegExp(r'[。，、,.!！?？;；:：~～()（）\[\]【】\-—_*#]'), '');
  working = working.replaceAll(RegExp(r'\s+'), '').trim();
  for (final tw in timeOfDay) {
    if (working.contains(tw)) {
      working = working.replaceAll(tw, ' $tw ').trim();
      break;
    }
  }
  working = working.replaceAll(RegExp(r'\s+'), ' ').trim();
  return working;
}

// ---------- 主解析入口 ----------
ParseResult parse(String text, List<Account> accounts) {
  final original = text.trim();
  var working = original;

  final d = extractDate(working);
  if (d.text.isNotEmpty) working = working.replaceAll(d.text, '');

  final a = extractAmount(working);
  final amount = a?.value;
  if (a != null) working = working.replaceAll(a.text, '');

  final accs = findAccounts(original, accounts);
  String? accountId, toAccountId;
  var type = TxnType.expense;

  final isTakeCash = RegExp('取现|取钱|取出来').hasMatch(original);
  final isSaveCash = RegExp('存现|存钱|存进去|存到').hasMatch(original);
  final isMoveTo = RegExp('转到|转入|转进|转存').hasMatch(original);

  if (isTakeCash || isSaveCash) {
    type = TxnType.transfer;
    Account? cash, other;
    for (final x in accounts) {
      if (x.name.contains('现金')) {
        cash = x;
      } else if (other == null) {
        other = x;
      }
    }
    if (isTakeCash) {
      accountId = other?.id;
      toAccountId = cash?.id;
    } else {
      accountId = cash?.id;
      toAccountId = other?.id;
    }
  } else if (isMoveTo) {
    type = TxnType.transfer;
    toAccountId = accs.isNotEmpty ? accs[0].id : null;
    accountId = accs.length > 1 ? accs[1].id : null;
  } else if (RegExp('转').hasMatch(original) && accs.length >= 2) {
    type = TxnType.transfer;
    accountId = accs[0].id;
    toAccountId = accs[1].id;
  }

  if (accountId != null) working = working.replaceAll(accounts.firstWhere((x) => x.id == accountId).name, '');
  if (toAccountId != null) working = working.replaceAll(accounts.firstWhere((x) => x.id == toAccountId).name, '');

  final cat = matchCategory(working);
  String? c1 = cat?.c1;
  String? c2 = cat?.c2;

  if (type == TxnType.transfer) {
    c1 = null;
    c2 = '';
  } else {
    if (c1 != null && incomeC1.contains(c1)) type = TxnType.income;
    if (c1 == null) c1 = null;
  }

  final note = buildNote(working);

  return ParseResult(
    amount: amount,
    date: d.date,
    category1: c1,
    category2: c2 ?? (c1 != null ? defaultC2(c1) : ''),
    accountId: accountId,
    toAccountId: toAccountId,
    type: type,
    note: note,
  );
}
