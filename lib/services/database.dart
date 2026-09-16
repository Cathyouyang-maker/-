// ===== 极简记账 · SQLite 存储 + 余额/冲销/导出 =====

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models.dart';

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
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 流水 ----------
  Future<List<Txn>> txns() async {
    final db = await database;
    final rows = await db.query('txns', orderBy: 'date DESC');
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
