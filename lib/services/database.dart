// ===== 极简记账 · SQLite 存储 + 余额/冲销/导出 =====

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models.dart';

/// 数据版本号：任何一次写库（增/改/删）都会 +1。
/// 界面监听它，一旦变化就重新读库，避免「记完账报表/明细/余额不刷新」。
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
void bumpData() {
  dataVersion.value++;
  // 每次数据变化都静默自动备份一份（失败也无妨）
  appDb.autoBackup();
}

class AppDb {
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'jizhang.db');
    return openDatabase(path, version: 2, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE accounts(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT '¥',
          balance REAL NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE txns(
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          category1 TEXT,
          category2 TEXT,
          account_id TEXT NOT NULL,
          to_account_id TEXT,
          note TEXT,
          date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          refund_of TEXT,
          refunded INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE settings(
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }, onUpgrade: (db, oldV, newV) async {
      // 旧版本（v1）没有 settings 表，补建
      await db.execute('CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)');
    });
  }

  // ---------- 设置（键值对，持久化提醒开关/时间等）----------
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- 账户 ----------
  Future<List<Account>> accounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'rowid');
    return rows.map(Account.fromMap).toList();
  }

  Future<void> upsertAccount(Account a) async {
    final db = await database;
    await db.insert('accounts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    bumpData();
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
    bumpData();
  }

  // ---------- 流水 ----------
  Future<List<Txn>> txns() async {
    final db = await database;
    final rows = await db.query('txns', orderBy: 'date DESC');
    return rows.map(Txn.fromMap).toList();
  }

  /// 某账户相关的所有流水（含转入/转出），按时间倒序
  Future<List<Txn>> txnsByAccount(String accountId) async {
    final db = await database;
    final rows = await db.query(
      'txns',
      where: 'account_id = ? OR to_account_id = ?',
      whereArgs: [accountId, accountId],
      orderBy: 'date DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  /// 余额变动：sign=+1 入账 / -1 冲销
  Future<void> _applyBalance(DatabaseExecutor db, Txn t, int sign) async {
    if (t.type == TxnType.transfer) {
      await db.rawUpdate('UPDATE accounts SET balance = balance + ? WHERE id = ?', [-sign * t.amount, t.accountId]);
      if (t.toAccountId != null) {
        await db.rawUpdate('UPDATE accounts SET balance = balance + ? WHERE id = ?', [sign * t.amount, t.toAccountId]);
      }
    } else if (t.type == TxnType.income) {
      await db.rawUpdate('UPDATE accounts SET balance = balance + ? WHERE id = ?', [sign * t.amount, t.accountId]);
    } else {
      await db.rawUpdate('UPDATE accounts SET balance = balance - ? WHERE id = ?', [sign * t.amount, t.accountId]);
    }
  }

  Future<void> addTxn(Txn t) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('txns', t.toMap());
      await _applyBalance(txn, t, 1);
      if (t.refundOf != null) {
        await txn.update('txns', {'refunded': 1}, where: 'id = ?', whereArgs: [t.refundOf]);
      }
    });
    bumpData();
  }

  Future<void> deleteTxn(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('txns', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      final t = Txn.fromMap(rows.first);
      await _applyBalance(txn, t, -1);
      if (t.refundOf != null) {
        await txn.update('txns', {'refunded': 0}, where: 'id = ?', whereArgs: [t.refundOf]);
      }
      await txn.delete('txns', where: 'id = ?', whereArgs: [id]);
    });
    bumpData();
  }

  Future<void> updateTxn(Txn next) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('txns', where: 'id = ?', whereArgs: [next.id], limit: 1);
      if (rows.isEmpty) return;
      final old = Txn.fromMap(rows.first);
      await _applyBalance(txn, old, -1);
      await _applyBalance(txn, next, 1);
      await txn.update('txns', next.toMap(), where: 'id = ?', whereArgs: [next.id]);
      // 冲销关联变更
      if (old.refundOf != next.refundOf) {
        if (old.refundOf != null) await txn.update('txns', {'refunded': 0}, where: 'id = ?', whereArgs: [old.refundOf]);
        if (next.refundOf != null) await txn.update('txns', {'refunded': 1}, where: 'id = ?', whereArgs: [next.refundOf]);
      }
    });
    bumpData();
  }

  Future<double> totalAssets() async {
    final list = await accounts();
    double sum = 0;
    for (final a in list) {
      if (a.currency == '¥') sum += a.balance;
    }
    return (sum * 100).roundToDouble() / 100;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('txns');
    await db.delete('accounts');
    bumpData();
  }

  // ---------- 备份 / 恢复（写进系统“下载”文件夹，卸载也保留）----------
  static const MethodChannel _backupChan = MethodChannel('com.jizhang.app/backup');

  String _ts() {
    final n = DateTime.now();
    final p2 = (int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p2(n.month)}${p2(n.day)}_${p2(n.hour)}${p2(n.minute)}${p2(n.second)}';
  }

  /// 生成 JSON 备份文件。Android 写进“下载/极简记账备份”，返回给人看的路径说明。
  Future<String> backupToFile() async {
    final name = '极简记账_${_ts()}.json';
    final content = await exportJson();
    if (Platform.isAndroid) {
      await _backupChan.invokeMethod('backupSave', {'name': name, 'content': content});
      return '下载/极简记账备份/$name';
    }
    // 桌面调试回退：文档目录
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsString(content);
    return f.path;
  }

  /// 自动备份：每次启动 / 每次记账后静默写一份最新数据到“下载/极简记账备份”。
  /// 该目录卸载 App 也不会清，重装后可经「导入数据 / 恢复数据」找回。
  /// 内部已吞掉异常，绝不影响正常使用。
  Future<void> autoBackup() async {
    try {
      final content = await exportJson();
      if (Platform.isAndroid) {
        await _backupChan.invokeMethod('backupSave', {
          'name': '极简记账_auto.json',
          'content': content,
        });
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final f = File(p.join(dir.path, '极简记账_auto.json'));
        await f.writeAsString(content);
      }
    } catch (_) {
      // 自动备份失败不应影响正常使用
    }
  }

  /// 导出文件：把 JSON 或 CSV 写入“下载/极简记账备份”，返回给人看的路径。
  Future<String> exportToFile(bool asJson) async {
    final content = asJson ? await exportJson() : await exportCsv();
    final name = '极简记账_导出_${_ts()}.${asJson ? 'json' : 'csv'}';
    if (Platform.isAndroid) {
      await _backupChan.invokeMethod('backupSave', {'name': name, 'content': content});
      return '下载/极简记账备份/$name';
    }
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsString(content);
    return f.path;
  }

  /// 列出已有备份文件名（新的在前）
  Future<List<String>> listBackups() async {
    try {
      if (Platform.isAndroid) {
        final r = await _backupChan.invokeMethod<List<dynamic>>('backupList');
        final list = (r ?? []).map((e) => e.toString()).toList();
        list.sort((a, b) => b.compareTo(a));
        return list;
      }
      final dir = await getApplicationDocumentsDirectory();
      if (!await dir.exists()) return [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => p.basename(f.path))
          .toList();
      files.sort((a, b) => b.compareTo(a));
      return files;
    } catch (_) {
      return [];
    }
  }

  Future<String> readBackup(String fileName) async {
    if (Platform.isAndroid) {
      return await _backupChan.invokeMethod('backupRead', {'name': fileName});
    }
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName)).readAsString();
  }

  /// 从 JSON 文本恢复（先清空再写入，谨慎使用）
  Future<void> restoreFromJson(String text) async {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final accs = (data['accounts'] as List? ?? [])
        .map((e) => Account.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final txns = (data['txns'] as List? ?? [])
        .map((e) => Txn.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('txns');
      await txn.delete('accounts');
      for (final a in accs) {
        await txn.insert('accounts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final t in txns) {
        await txn.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    bumpData();
  }

  // ---------- 导入（JSON / Excel / CSV）----------

  /// 从本 App 自己的备份 JSON（{accounts:[...], txns:[...]}）导入。
  /// 按 id 覆盖（幂等），不会清空其他已有数据，适合“把旧备份搬回来”。
  Future<({int accounts, int txns})> importJson(String text) async {
    final decoded = jsonDecode(text);
    List<dynamic> accRaw;
    List<dynamic> txnRaw;
    if (decoded is Map) {
      accRaw = (decoded['accounts'] as List? ?? []);
      txnRaw = (decoded['txns'] as List? ?? []);
    } else if (decoded is List) {
      accRaw = [];
      txnRaw = decoded;
    } else {
      throw 'JSON 格式无法识别';
    }
    final accs = accRaw.map((e) => Account.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    final txns = txnRaw.map((e) => Txn.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    final db = await database;
    int aN = 0, tN = 0;
    await db.transaction((txn) async {
      for (final a in accs) {
        await txn.insert('accounts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        aN++;
      }
      for (final t in txns) {
        await txn.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        tN++;
      }
    });
    bumpData();
    return (accounts: aN, txns: tN);
  }

  /// 从 Excel(.xlsx/.xls) 导入：第一行为表头，按中文/英文列名匹配。
  Future<({int accounts, int txns})> importExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) throw 'Excel 里没有工作表';
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString()?.trim()).toList())
        .toList();
    return _importGrid(rows);
  }

  /// 从 CSV 导入（兼容本 App 导出的带 BOM 表格）。
  Future<({int accounts, int txns})> importCsv(String text) async {
    final rows = _parseCsv(text);
    return _importGrid(rows);
  }

  Future<({int accounts, int txns})> _importGrid(List<List<String?>> grid) async {
    if (grid.isEmpty) throw '文件内容为空';
    final header = grid.first.map((e) => (e ?? '').toLowerCase()).toList();
    int idx(String zh, String en) {
      final i = header.indexOf(zh);
      return i >= 0 ? i : header.indexOf(en);
    }
    final ciDate = idx('日期', 'date');
    final ciType = idx('类型', 'type');
    final ciAmount = idx('金额', 'amount');
    final ciC1 = idx('一级分类', 'category1');
    final ciC2 = idx('二级分类', 'category2');
    final ciAcc = idx('账户', 'account');
    final ciTo = idx('转入账户', 'to account');
    final ciNote = idx('备注', 'note');

    final db = await database;
    int aN = 0, tN = 0;
    await db.transaction((txn) async {
      for (var i = 1; i < grid.length; i++) {
        final row = grid[i];
        if (row.every((e) => (e ?? '').isEmpty)) continue;
        final dateStr = _cell(row, ciDate);
        final amtStr = _cell(row, ciAmount);
        if (dateStr.isEmpty || amtStr.isEmpty) continue;
        final date = _parseDate(dateStr);
        if (date == null) continue;
        final type = _parseType(_cell(row, ciType));
        final amount = double.tryParse(amtStr.replaceAll(',', '')) ?? 0;
        if (amount == 0) continue;

        var accName = _cell(row, ciAcc);
        if (accName.isEmpty) accName = '默认账户';
        final accId = await _ensureAccount(txn, accName, () => 'acc_${DateTime.now().microsecondsSinceEpoch}_${tN}_$aN', () => aN++);
        String? toId;
        final toName = _cell(row, ciTo);
        if (toName.isNotEmpty) {
          toId = await _ensureAccount(txn, toName, () => 'acc_to${DateTime.now().microsecondsSinceEpoch}_${tN}_$aN', () => aN++);
        }
        final t = Txn(
          id: 'imp_${DateTime.now().microsecondsSinceEpoch}_${tN}_$aN',
          type: type,
          amount: amount,
          category1: _cell(row, ciC1),
          category2: _cell(row, ciC2),
          accountId: accId,
          toAccountId: toId,
          note: _cell(row, ciNote),
          date: date,
          createdAt: date,
        );
        await txn.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        await _applyBalance(txn, t, 1);
        tN++;
      }
    });
    bumpData();
    return (accounts: aN, txns: tN);
  }

  /// 按名称找账户，没有就新建（余额 0）。返回账户 id。
  Future<String> _ensureAccount(DatabaseExecutor txn, String name, String Function() newId, void Function() bump) async {
    final ex = await txn.query('accounts', where: 'name = ?', whereArgs: [name], limit: 1);
    if (ex.isNotEmpty) return ex.first['id'] as String;
    final id = newId();
    await txn.insert('accounts', Account(id: id, name: name, currency: '¥', balance: 0).toMap());
    bump();
    return id;
  }

  String _cell(List<String?> row, int i) => (i >= 0 && i < row.length) ? (row[i] ?? '').trim() : '';

  DateTime? _parseDate(String s) {
    s = s.trim();
    if (RegExp(r'^\d{13}$').hasMatch(s)) return DateTime.fromMillisecondsSinceEpoch(int.parse(s));
    for (final f in ['yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd', 'yyyy/MM/dd', 'yyyy.MM.dd']) {
      final d = DateFormat(f).tryParse(s);
      if (d != null) return d;
    }
    return null;
  }

  TxnType _parseType(String s) {
    s = s.trim();
    if (s == '收入' || s.toLowerCase() == 'income' || s == 'i') return TxnType.income;
    if (s == '转账' || s.toLowerCase() == 'transfer' || s == 't') return TxnType.transfer;
    return TxnType.expense;
  }

  List<List<String?>> _parseCsv(String text) {
    final out = <List<String?>>[];
    for (final raw in text.replaceAll('\uFEFF', '').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final row = <String?>[];
      var field = '';
      var inQ = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (inQ) {
          if (ch == '"') {
            if (i + 1 < line.length && line[i + 1] == '"') {
              field += '"';
              i++;
            } else {
              inQ = false;
            }
          } else {
            field += ch;
          }
        } else if (ch == '"') {
          inQ = true;
        } else if (ch == ',') {
          row.add(field);
          field = '';
        } else {
          field += ch;
        }
      }
      row.add(field);
      out.add(row);
    }
    return out;
  }

  // ---------- 导出 ----------
  Future<String> exportJson() async {
    final accs = await accounts();
    final list = await txns();
    final buf = StringBuffer()
      ..writeln('{')
      ..writeln('  "accounts": [');
    for (var i = 0; i < accs.length; i++) {
      buf.write('    ${_jsonMap(accs[i].toMap())}');
      if (i != accs.length - 1) buf.write(',');
      buf.writeln();
    }
    buf.writeln('  ],');
    buf.writeln('  "txns": [');
    for (var i = 0; i < list.length; i++) {
      buf.write('    ${_jsonMap(list[i].toMap())}');
      if (i != list.length - 1) buf.write(',');
      buf.writeln();
    }
    buf.writeln('  ]');
    buf.write('}');
    return buf.toString();
  }

  String _jsonMap(Map<String, dynamic> m) {
    return '{${m.entries.map((e) => '"${e.key}":${_jsonVal(e.value)}').join(',')}}';
  }

  String _jsonVal(Object? v) {
    if (v == null) return 'null';
    if (v is num || v is bool) return '$v';
    return '"${'$v'.replaceAll('"', '\\"')}"';
  }

  Future<String> exportCsv() async {
    final list = await txns();
    final accs = await accounts();
    String nameOf(String? id) {
      if (id == null) return '';
      for (final a in accs) {
        if (a.id == id) return a.name;
      }
      return '';
    }

    final buf = StringBuffer('\uFEFF日期,类型,金额,一级分类,二级分类,账户,转入账户,备注\n');
    for (final t in list) {
      final row = [
        _dateStr(t.date),
        t.type.label,
        t.amount,
        t.category1 ?? '',
        t.category2 ?? '',
        nameOf(t.accountId),
        nameOf(t.toAccountId),
        t.note ?? '',
      ].map((x) => '"${'$x'.replaceAll('"', '""')}"').join(',');
      buf.writeln(row);
    }
    return buf.toString();
  }

  String _dateStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final AppDb appDb = AppDb();
