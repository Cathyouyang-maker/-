// ===== 极简记账 · 账户新建/编辑弹层（共享：账户页 + 记一笔页）=====

import 'package:flutter/material.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';

/// 打开「新建 / 编辑账户」弹层。返回 true 表示保存成功。
/// account 为 null 时是新建。
Future<bool?> showAccountSheet(BuildContext context, {Account? account}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AccountSheet(account: account),
  );
  // 新建成功后给出明确反馈（用户第一次用最容易卡在「没有账户」）
  if (ok == true && context.mounted && account == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账户已建好，现在可以记账了')),
    );
  }
  return ok;
}

class AccountSheet extends StatefulWidget {
  final Account? account;
  const AccountSheet({super.key, this.account});
  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String _currency = '¥';
  String? _nameError;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      _name.text = widget.account!.name;
      _balance.text = widget.account!.balance.toString();
      _currency = widget.account!.currency;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '请填个名字，比如「微信」');
      return;
    }
    await appDb.upsertAccount(Account(
      id: widget.account?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      currency: _currency,
      balance: double.tryParse(_balance.text.trim()) ?? 0,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.account == null ? '新建账户（钱放在哪儿）' : '编辑账户',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.account == null,
              decoration: InputDecoration(
                labelText: '账户名',
                hintText: '如：现金 / 微信 / 招行卡 / 美金现金',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _currency,
              isExpanded: true,
              items: currencies.map((c) => DropdownMenuItem(value: c, child: Text('币种  $c'))).toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _balance,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '当前余额', hintText: '填 0 也行，以后随时改'),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
          ],
        ),
      ),
    );
  }
}
