// ===== 极简记账 · 入口 =====

import 'package:flutter/material.dart';
import 'screens/record_screen.dart';
import 'screens/report_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/accounts_screen.dart';
import 'services/database.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appDb.database;
  await reminder.init();
  await reminder.refresh();
  runApp(const JizhangApp());
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
