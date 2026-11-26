import 'package:flutter/material.dart';

import 'core/classifier_provider.dart';
import 'core/recorder_service.dart';
import 'core/spec.dart';
import 'ui/capture_page.dart';
import 'ui/model_page.dart';
import 'ui/recordings_page.dart';
import 'ui/recognize_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // 唯一参数源：采样率、窗长、步长、阈值、时延口径都从这里来
    await PipelineSpec.loadBundled();
  } catch (error) {
    // 读不到就用兜底值启动，界面上会有提示，不至于白屏
    debugPrint('spec 读取失败，使用兜底配置：$error');
  }
  runApp(const SwallowApp());
}

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
  final ClassifierProvider _classifierProvider = ClassifierProvider();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 恢复上次的被试编号
    _recorder.loadSettings();
    _classifierProvider.load();
  }

  @override
  void dispose() {
    _classifierProvider.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CapturePage(
            recorder: _recorder,
            classifierProvider: _classifierProvider,
          ),
          RecognizePage(
            recorder: _recorder,
            classifierProvider: _classifierProvider,
          ),
          const RecordingsPage(),
          ModelPage(classifierProvider: _classifierProvider),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: '采集'),
          NavigationDestination(icon: Icon(Icons.insights), label: '识别'),
          NavigationDestination(icon: Icon(Icons.folder_open), label: '记录'),
          NavigationDestination(icon: Icon(Icons.model_training), label: '模型'),
        ],
      ),
    );
  }
}
