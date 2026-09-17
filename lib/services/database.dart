// ===== 极简记账 · SQLite 存储 + 余额/冲销/导出 =====

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models.dart';

/// 数据版本号：任何一次写库（增/改/删）都会 +1。
/// 界面监听它，一旦变化就重新读库，避免「记完账报表/明细/余额不刷新」。
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
void bumpData() => dataVersion.value++;

class AppDb {
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'jizhang.db');
    return openDatabase(path, version: 1, onCreate: (db, v) async {
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
    });
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

  // ---------- 备份 / 恢复（文件，存到手机外部存储）----------
  Future<String> _backupDir() async {
    final base = await getExternalStorageDirectory();
    if (base == null) throw Exception('无法访问外部存储');
    final d = Directory(p.join(base.path, '极简记账备份'));
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  String _ts() {
    final n = DateTime.now();
    final p2 = (int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p2(n.month)}${p2(n.day)}_${p2(n.hour)}${p2(n.minute)}${p2(n.second)}';
  }

  /// 生成 JSON 备份文件，返回完整路径（覆盖安装后该文件仍在）
  Future<String> backupToFile() async {
    final dir = await _backupDir();
    final file = File(p.join(dir, '极简记账_${_ts()}.json'));
    await file.writeAsString(await exportJson());
    return file.path;
  }

  /// 列出已有备份文件名（新的在前）
  Future<List<String>> listBackups() async {
    try {
      final dir = await _backupDir();
      final files = Directory(dir)
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
    final dir = await _backupDir();
    return File(p.join(dir, fileName)).readAsString();
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
