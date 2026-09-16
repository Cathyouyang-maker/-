// ===== 极简记账 · 数据模型 =====

enum TxnType { expense, income, transfer }

extension TxnTypeX on TxnType {
  String get label => switch (this) {
        TxnType.expense => '支出',
        TxnType.income => '收入',
        TxnType.transfer => '转账',
      };
}

TxnType txnTypeFrom(String s) => switch (s) {
      'income' => TxnType.income,
      'transfer' => TxnType.transfer,
      _ => TxnType.expense,
    };

class Account {
  String id;
  String name;
  String currency;
  double balance;

  Account({
    required this.id,
    required this.name,
    required this.currency,
    this.balance = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'currency': currency,
        'balance': balance,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as String,
        name: m['name'] as String,
        currency: m['currency'] as String,
        balance: (m['balance'] as num).toDouble(),
      );

  Account copy() => Account(id: id, name: name, currency: currency, balance: balance);
}

class Txn {
  String id;
  TxnType type;
  double amount;
  String? category1;
  String? category2;
  String accountId;
  String? toAccountId;
  String? note;
  DateTime date;
  DateTime createdAt;

  /// 冲销：收入退款关联的原支出 id（此笔是退款时）
  String? refundOf;

  /// 冲销：原支出是否已被退款冲掉
  bool refunded;

  Txn({
    required this.id,
    required this.type,
    required this.amount,
    this.category1,
    this.category2,
    required this.accountId,
    this.toAccountId,
    this.note,
    required this.date,
    required this.createdAt,
    this.refundOf,
    this.refunded = false,
  });

  /// 是否参与统计（被冲销的原支出 / 用于冲销的退款 都不再计入报表）
  bool get isVoid => refunded || refundOf != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'category1': category1,
        'category2': category2,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'refund_of': refundOf,
        'refunded': refunded ? 1 : 0,
      };

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as String,
        type: txnTypeFrom(m['type'] as String),
        amount: (m['amount'] as num).toDouble(),
        category1: m['category1'] as String?,
        category2: m['category2'] as String?,
        accountId: m['account_id'] as String,
        toAccountId: m['to_account_id'] as String?,
        note: m['note'] as String?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        refundOf: m['refund_of'] as String?,
        refunded: (m['refunded'] as int? ?? 0) == 1,
      );
}
