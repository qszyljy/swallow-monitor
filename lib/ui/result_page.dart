import 'package:flutter/material.dart';

import '../core/classifier.dart';
import '../core/recorder_service.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.recorder});

  final RecorderService recorder;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  static const Classifier _classifier = PlaceholderClassifier();

  List<double>? _scores;
  String? _fileName;
  double _fileSeconds = 0;
  double _inferMs = 0;
  bool _busy = false;

  Future<void> _analyze() async {
    final files = await RecorderService.listRecordings();
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有录音，先去「采集」页录一条')),
      );
      return;
    }
    final file = files.first;
    final bytes = await file.length();
    setState(() {
      _busy = true;
      _fileName = file.path.split('/').last;
      _fileSeconds = bytes / (RecorderService.sampleRate * 2);
    });

    final watch = Stopwatch()..start();
    final scores = await _classifier.classifyFile(file.path);
    watch.stop();
    if (!mounted) return;
    setState(() {
      _scores = scores;
      _inferMs = watch.elapsedMicroseconds / 1000.0;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scores = _scores;
    return Scaffold(
      appBar: AppBar(title: const Text('分类')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_classifier.ready)
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_classifier.name}：分数恒为 0，仅用于打通界面。'
                          '模型接入点见 lib/core/classifier.dart。',
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('输入', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(_fileName ?? '尚未选择录音'),
                    if (_fileName != null)
                      Text(
                        '时长 ${_fileSeconds.toStringAsFixed(1)} s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: const Icon(Icons.play_arrow),
              label: Text(_busy ? '分析中…' : '分析最新一条录音'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 16),
            if (scores != null) ...[
              Text('各类分数', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < scores.length; i++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_classifier.labels[i]),
                    Text('${(scores[i] * 100).toStringAsFixed(1)}%'),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: scores[i],
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            const Divider(height: 32),
            Text(
              '端侧指标（评分项 6 要报）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _metricRow('模型体积', '—（未接入）'),
            _metricRow(
              '单次推理',
              _scores == null ? '—' : '${_inferMs.toStringAsFixed(1)} ms（占位）',
            ),
            _metricRow('端到端时延', '—（需真机打点，目标 ≤ 20 ms）'),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(name), Text(value)],
      ),
    );
  }
}
