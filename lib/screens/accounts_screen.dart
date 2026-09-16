// ===== 极简记账 · 账户（盘点 / 多币种 / 备份 / 清空）=====

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../widgets/charts.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> _accounts = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    _total = await appDb.totalAssets();
    if (mounted) setState(() {});
    if (_accounts.isEmpty) _onboard();
  }

  void _onboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAccountSheet(null));
  }

  Future<void> _showAccountSheet(Account? a) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountSheet(account: a),
    );
    await _load();
  }

  Future<void> _deleteAccount(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('删除「${a.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除', style: TextStyle(color: kExpense))),
        ],
      ),
    );
    if (ok == true) {
      await appDb.deleteAccount(a.id);
      await _load();
    }
  }

  Future<void> _export(bool json) async {
    final content = json ? await appDb.exportJson() : await appDb.exportCsv();
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(json ? '已复制备份数据（JSON）' : '已复制表格（CSV），可粘贴到 Excel')));
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空全部数据'),
        content: const Text('将删除所有账户和流水，且无法恢复。确定清空？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空', style: TextStyle(color: kExpense))),
        ],
      ),
    );
    if (ok == true) {
      await appDb.clearAll();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 总资产
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kBlue, Color(0xFF1D4ED8)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('总资产（人民币）', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text('¥${fmtNum(_total)}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              if (_accounts.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text('还没有账户', style: TextStyle(color: Colors.grey)))
              else
                ..._accounts.map((a) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      title: Text(a.name),
                      subtitle: Text('币种 ${a.currency}', style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.currency == '¥' ? '¥${fmtNum(a.balance)}' : '${a.currency} ${fmtNum(a.balance)}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showAccountSheet(a)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: kExpense), onPressed: () => _deleteAccount(a)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => _showAccountSheet(null), child: const Text('＋ 新增账户')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => _export(true), child: const Text('备份数据'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _export(false), child: const Text('导出表格'))),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _clearAll,
            child: const Text('清空全部数据', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }
}

// ---------- 账户增改 ----------
class _AccountSheet extends StatefulWidget {
  final Account? account;
  const _AccountSheet({this.account});
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String _currency = '¥';

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
    if (_name.text.trim().isEmpty) return;
    await appDb.upsertAccount(Account(
      id: widget.account?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      currency: _currency,
      balance: double.tryParse(_balance.text) ?? 0,
    ));
    if (mounted) Navigator.pop(context);
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
            Text(widget.account == null ? '新增账户' : '编辑账户', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: '账户名（如：现金 / 微信 / 招行卡 / 美金现金）')),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _currency,
              isExpanded: true,
              items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: _balance, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '当前余额')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('保存'))),
          ],
        ),
      ),
    );
  }
}
