// ===== 极简记账 · 入口 =====

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/record_screen.dart';
import 'screens/report_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/accounts_screen.dart';
import 'services/database.dart';
import 'services/notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 任何页面构建错误都显示可读信息，而不是白屏
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '页面出错：${details.exception}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  };

  // 先显示界面，初始化放后台，失败也不影响打开
  runApp(const JizhangApp());
  _initAsync();
}

Future<void> _initAsync() async {
  try {
    await appDb.database;
  } catch (e) {
    debugPrint('DB 初始化失败: $e');
  }
  try {
    await reminder.init();
    await reminder.refresh();
  } catch (e) {
    debugPrint('提醒初始化失败: $e');
  }
}

class JizhangApp extends StatelessWidget {
  const JizhangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '极简记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F6F9), elevation: 0, centerTitle: false),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _titles = ['极简记账', '报表', '明细', '账户'];
  final _pages = const [RecordScreen(), ReportScreen(), DetailScreen(), AccountsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index], style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1F2937)))),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: '记一笔'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '报表'),
          NavigationDestination(icon: Icon(Icons.format_list_bulleted), label: '明细'),
          NavigationDestination(icon: Icon(Icons.credit_card), label: '账户'),
        ],
      ),
    );
  }
}
