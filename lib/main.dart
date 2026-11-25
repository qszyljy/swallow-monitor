import 'package:flutter/material.dart';

import 'core/recorder_service.dart';
import 'ui/capture_page.dart';
import 'ui/recordings_page.dart';
import 'ui/result_page.dart';

void main() => runApp(const SwallowApp());

class SwallowApp extends StatelessWidget {
  const SwallowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '吞咽事件采集',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F6F6A),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final RecorderService _recorder = RecorderService();
  int _index = 0;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CapturePage(recorder: _recorder),
          ResultPage(recorder: _recorder),
          const RecordingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: '采集'),
          NavigationDestination(icon: Icon(Icons.insights), label: '分类'),
          NavigationDestination(icon: Icon(Icons.folder_open), label: '记录'),
        ],
      ),
    );
  }
}
