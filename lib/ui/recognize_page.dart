import 'package:flutter/material.dart';

import '../core/classifier_provider.dart';
import '../core/recorder_service.dart';
import 'analysis_view.dart';
import 'live_recognize_view.dart';

/// 识别页：实时（麦克风流）与回放（已录录音）两种用法，同页切换。
class RecognizePage extends StatefulWidget {
  const RecognizePage({
    super.key,
    required this.recorder,
    required this.classifierProvider,
  });

  final RecorderService recorder;
  final ClassifierProvider classifierProvider;

  @override
  State<RecognizePage> createState() => _RecognizePageState();
}

class _RecognizePageState extends State<RecognizePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('识别')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.bolt, size: 16),
                  label: Text('实时'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.history, size: 16),
                  label: Text('回放'),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => _tab = values.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                LiveRecognizeView(
                  recorder: widget.recorder,
                  classifierProvider: widget.classifierProvider,
                ),
                AnalysisView(
                  recorder: widget.recorder,
                  classifierProvider: widget.classifierProvider,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
