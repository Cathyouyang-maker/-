// ===== 极简记账 · 账户（盘点 / 多币种 / 备份 / 清空）=====

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../data/categories.dart';
import '../services/database.dart';
import '../services/notifications.dart';
import '../widgets/charts.dart';
import '../widgets/account_sheet.dart';
import '../screens/account_detail_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Account> _accounts = [];
  double _total = 0;
  bool _notifOk = false;
  bool _reminderOn = true;
  int _hour = 21;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _accounts = await appDb.accounts();
    _total = await appDb.totalAssets();
    _notifOk = reminder.permissionGranted;
    _reminderOn = (await appDb.getSetting('reminder_enabled')) != '0';
    _hour = int.tryParse(await appDb.getSetting('reminder_hour') ?? '') ?? 21;
    if (mounted) setState(() {});
    if (_accounts.isEmpty) _onboard();
  }

  Future<void> _requestNotif() async {
    final ok = await reminder.requestPermission();
    setState(() => _notifOk = ok);
    if (ok) await reminder.refresh();
  }

  void _onboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAccountSheet(null));
  }

  Future<void> _showAccountSheet(Account? a) async {
    await showAccountSheet(context, account: a);
    await _load();
  }

  Future<void> _openDetail(Account a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(account: a)));
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

  Future<void> _backup() async {
    try {
      final path = await appDb.backupToFile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成备份文件：\n$path', maxLines: 4), duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败：$e')));
    }
  }

  Future<void> _import() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'xlsx', 'xls', 'csv'],
        withData: true,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开文件选择：$e')));
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final lower = f.name.toLowerCase();
    try {
      late ({int accounts, int txns}) r;
      late Uint8List bytes;
      if (f.bytes != null) {
        bytes = f.bytes!;
      } else if (f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      } else {
        throw '无法读取所选文件';
      }
      if (lower.endsWith('.json')) {
        r = await appDb.importJson(utf8.decode(bytes));
      } else if (lower.endsWith('.csv')) {
        r = await appDb.importCsv(utf8.decode(bytes));
      } else {
        r = await appDb.importExcel(bytes);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入成功：账户 ${r.accounts} 个，流水 ${r.txns} 笔')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _restore() async {
    final files = await appDb.listBackups();
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有备份文件，先点“备份数据”')));
      }
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('恢复数据'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: files.map((f) => ListTile(title: Text(f), onTap: () => Navigator.pop(c, f))).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消'))],
      ),
    );
    if (chosen == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认恢复？'),
        content: const Text('将用该备份覆盖当前所有账户和流水，确定继续？（建议先再备一份）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('恢复', style: TextStyle(color: kExpense))),
        ],
      ),
    );
    if (ok == true) {
      try {
        final text = await appDb.readBackup(chosen);
        await appDb.restoreFromJson(text);
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('恢复成功')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
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
                      onTap: () => _openDetail(a),
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
            Expanded(child: OutlinedButton(onPressed: _backup, child: const Text('备份数据'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _restore, child: const Text('恢复数据'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => _export(false), child: const Text('导出表格'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _import, child: const Text('导入数据'))),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('记账提醒', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (!_notifOk)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                    child: const Text('未开启通知权限，提醒不会弹出。点下方“请求权限”；如仍无弹窗，请到手机设置→应用→极简记账→通知 中开启。',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('每天提醒记账'),
                  subtitle: Text(_notifOk ? '未在 $_hour:00 前记账，当晚提醒' : '需先开启通知权限'),
                  value: _reminderOn && _notifOk,
                  onChanged: _notifOk
                      ? (v) async {
                          await reminder.setEnabled(v);
                          setState(() => _reminderOn = v);
                        }
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒时间'),
                  trailing: DropdownButton<int>(
                    value: _hour,
                    items: [19, 20, 21, 22]
                        .map((h) => DropdownMenuItem(value: h, child: Text('$h:00')))
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) {
                        await reminder.setHour(v);
                        setState(() => _hour = v);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: () => reminder.testNow(), child: const Text('发送测试提醒')),
                ),
              ],
            ),
          ),
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
