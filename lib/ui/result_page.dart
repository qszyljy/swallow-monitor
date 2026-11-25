import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_event.dart';
import '../core/classifier_provider.dart';
import '../core/contracts/classifier.dart';
import '../core/recorder_service.dart';
import '../core/wav_reader.dart';
import '../core/window_slicer.dart';

class _EventResult {
  _EventResult({
    required this.event,
    required this.label,
    required this.score,
    required this.latencyMs,
  });

  final AppEvent event;
  final String label;
  final double score;
  final int latencyMs;

  bool? get match {
    final human = event.humanLabel;
    if (human == null || human.isEmpty) return null;
    return human == label;
  }
}

/// 分类页：模型状态 → 选录音 → 逐事件结果 → 汇总与导出。
class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.recorder,
    required this.classifierProvider,
  });

  final RecorderService recorder;
  final ClassifierProvider classifierProvider;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  List<File> _recordings = const <File>[];
  String? _selectedPath;
  List<_EventResult>? _results;
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    final files = await RecorderService.listRecordings();
    if (!mounted) return;
    setState(() {
      _recordings = files;
      _selectedPath ??= files.isEmpty ? null : files.first.path;
    });
  }

  int _argmax(List<double> scores) {
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return best;
  }

  Future<void> _analyze() async {
    final path = _selectedPath;
    if (path == null) {
      setState(() => _note = '先选一条录音');
      return;
    }
    setState(() {
      _busy = true;
      _note = null;
      _results = null;
    });

    try {
      final events = await EventStore.load(path);
      if (events.isEmpty) {
        if (!mounted) return;
        setState(() {
          _note = '这条录音没有事件记录（旧版本录的，或当时没检测到事件）';
          _busy = false;
        });
        return;
      }

      final wav = await readWav(path);
      final classifier = widget.classifierProvider.classifier;
      final windowSamples = classifier.input.windowSamples;

      final results = <_EventResult>[];
      for (final event in events) {
        final window = sliceWindowEndingAt(wav, event.endSec, windowSamples);
        final watch = Stopwatch()..start();
        final scores = await classifier.classifyWindow(window);
        watch.stop();

        final label = classifier.ready && scores.isNotEmpty
            ? classifier.labels[_argmax(scores)]
            : 'pending';
        results.add(
          _EventResult(
            event: event,
            label: label,
            score: scores.isEmpty ? 0 : scores[_argmax(scores)],
            latencyMs: watch.elapsedMilliseconds,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _note = '分析失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _export() async {
    final results = _results;
    if (results == null || results.isEmpty) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/analysis');
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .split('T')
          .join('_');
      final file = File('${dir.path}/events_$stamp.csv');
      final buffer = StringBuffer(
        'start_sec,end_sec,predicted,human,match,score,latency_ms\n',
      );
      for (final r in results) {
        buffer.writeln(
          '${r.event.startSec.toStringAsFixed(3)},'
          '${r.event.endSec.toStringAsFixed(3)},'
          '${r.label},'
          '${r.event.humanLabel ?? ''},'
          '${r.match == null ? '' : (r.match! ? 1 : 0)},'
          '${r.score.toStringAsFixed(3)},'
          '${r.latencyMs}',
        );
      }
      await file.writeAsString(buffer.toString());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '分类结果 ${results.length} 条',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.classifierProvider,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final classifier = widget.classifierProvider.classifier;
        final results = _results;

        return Scaffold(
          appBar: AppBar(
            title: const Text('分类'),
            actions: [
              IconButton(
                tooltip: '刷新录音列表',
                onPressed: _loadRecordings,
                icon: const Icon(Icons.refresh),
              ),
              if (results != null && results.isNotEmpty)
                IconButton(
                  tooltip: '导出结果',
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _modelCard(context, classifier, scheme),
              const SizedBox(height: 12),
              _pickerCard(context, scheme),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _analyze,
                icon: const Icon(Icons.play_arrow),
                label: Text(_busy ? '分析中…' : '分析这条录音的全部事件'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              if (_note != null) ...[
                const SizedBox(height: 8),
                Text(_note!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (results != null && results.isNotEmpty) ...[
                const SizedBox(height: 16),
                _summary(context, results, scheme),
                const SizedBox(height: 12),
                Text('逐事件结果',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < results.length; i++)
                  _eventTile(context, i, results[i], scheme),
                const SizedBox(height: 8),
                Text(
                  '「一致」只统计已人工标注的事件；没标注的留空，不计入一致率。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _modelCard(
    BuildContext context,
    Classifier classifier,
    ColorScheme scheme,
  ) {
    final error = widget.classifierProvider.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  classifier.ready ? Icons.check_circle : Icons.info_outline,
                  size: 16,
                  color: classifier.ready ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 6),
                Text('模型', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  classifier.ready ? '已接入' : '未接入',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(classifier.name,
                style: Theme.of(context).textTheme.bodySmall),
            Text(
              '窗长 ${classifier.input.windowMs} ms · '
              '采样率 ${classifier.input.sampleRate} Hz · '
              '归一化 ${classifier.input.normalize}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (error != null)
              Text(
                error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pickerCard(BuildContext context, ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: _recordings.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('还没有录音，先去「采集」页录一条'),
              )
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedPath,
                  items: [
                    for (final file in _recordings)
                      DropdownMenuItem<String>(
                        value: file.path,
                        child: Text(
                          file.path.split('/').last,
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedPath = value;
                    _results = null;
                    _note = null;
                  }),
                ),
              ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    List<_EventResult> results,
    ColorScheme scheme,
  ) {
    final labeled =
        results.where((r) => r.event.humanLabel != null).length;
    final matched = results.where((r) => r.match == true).length;
    final meanLatency = results.isEmpty
        ? 0.0
        : results.map((r) => r.latencyMs).reduce((a, b) => a + b) /
            results.length;

    final counts = <String, int>{};
    for (final r in results) {
      final label = r.event.humanLabel?.isNotEmpty == true
          ? r.event.humanLabel!
          : r.label;
      counts[label] = (counts[label] ?? 0) + 1;
    }

    Widget metric(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleMedium),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('汇总', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                metric('${results.length}', '事件'),
                metric('$labeled', '已标注'),
                metric(
                  labeled == 0 ? '—' : '$matched/$labeled',
                  '与标注一致',
                ),
                metric('${meanLatency.toStringAsFixed(0)} ms', '平均推理'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              counts.entries.map((e) => '${e.key} ${e.value}').join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(
    BuildContext context,
    int index,
    _EventResult result,
    ColorScheme scheme,
  ) {
    final match = result.match;
    final human = result.event.humanLabel;
    final label = result.label == 'pending' ? '待分类' : result.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#${index + 1}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              '${result.event.startSec.toStringAsFixed(2)}s · $label'
              '${human == null ? '' : ' / 标注 $human'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            '${(result.score * 100).toStringAsFixed(0)}% · ${result.latencyMs}ms',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 6),
          Icon(
            match == null
                ? Icons.remove
                : (match ? Icons.check : Icons.close),
            size: 16,
            color: match == null
                ? scheme.outline
                : (match ? scheme.primary : scheme.error),
          ),
        ],
      ),
    );
  }
}
