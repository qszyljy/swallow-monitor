import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_event.dart';
import '../core/benchmark_log.dart';
import '../core/classifier_provider.dart';
import '../core/contracts/detector.dart';
import '../core/contracts/sample_source.dart';
import '../core/impls/mic_detector.dart';
import '../core/recorder_service.dart';
import '../core/spec.dart';
import 'waveform_view.dart';

/// 实时识别面板：不落盘，只推理。
///
/// 分割负责「有没有事件」，模型负责「是什么」；最高分低于阈值就显示「不确定」。
/// 波形支持横向拖动回看，事件按真实时间位置画在曲线上。
class LiveRecognizeView extends StatefulWidget {
  const LiveRecognizeView({
    super.key,
    required this.recorder,
    required this.classifierProvider,
  });

  final RecorderService recorder;
  final ClassifierProvider classifierProvider;

  @override
  State<LiveRecognizeView> createState() => _LiveRecognizeViewState();
}

class _LiveRecognizeViewState extends State<LiveRecognizeView> {
  static const Map<String, String> _names = {
    'swallow': '吞咽',
    'cough': '咳嗽',
    'interfere': '干扰',
    'rest': '静息',
  };

  late MicDetector _detector;
  StreamSubscription<SampleFrame>? _frameSub;
  StreamSubscription<DetectionResult>? _resultSub;

  final List<AppEvent> _events = <AppEvent>[];
  final List<BenchmarkEntry> _bench = <BenchmarkEntry>[];
  DetectionResult? _last;
  int _correct = 0;
  int _wrong = 0;

  RecorderService get recorder => widget.recorder;

  double get _threshold => PipelineSpec.current.detection.confidenceThreshold;

  bool get _modelReady => widget.classifierProvider.ready;

  @override
  void initState() {
    super.initState();
    _detector = _buildDetector();
    _frameSub = recorder.frames.listen((frame) => _detector.handleFrame(frame));
    _bind();
    widget.classifierProvider.addListener(_onModelChanged);
  }

  MicDetector _buildDetector() => MicDetector(
        specProvider: () => PipelineSpec.current,
        classifier: widget.classifierProvider.classifier,
      );

  void _bind() {
    _resultSub = _detector.results.listen((result) {
      if (!mounted) return;
      setState(() {
        _last = result;
        _events.add(
          AppEvent(
            startMicros: result.startMicros,
            endMicros: result.timestampMicros,
            predictedLabel: result.label,
            scores: result.scores,
            latencyMs: result.latencyMs,
          ),
        );
      });
    });
  }

  void _onModelChanged() {
    final previous = _detector;
    _resultSub?.cancel();
    _detector = _buildDetector();
    _bind();
    unawaited(previous.dispose());
    if (mounted) setState(_clear);
  }

  void _clear() {
    _events.clear();
    _bench.clear();
    _correct = 0;
    _wrong = 0;
    _last = null;
    _detector.reset();
  }

  @override
  void dispose() {
    widget.classifierProvider.removeListener(_onModelChanged);
    _frameSub?.cancel();
    _resultSub?.cancel();
    unawaited(_detector.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (recorder.recording) {
      await recorder.stop();
      return;
    }
    setState(_clear);
    await recorder.start(saveAudio: false);
    if (!mounted) return;
    final error = recorder.error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _mark(bool correct) {
    final last = _last;
    if (last == null) return;
    setState(() {
      _bench.add(
        BenchmarkEntry(
          time: DateTime.now(),
          label: last.label,
          score: last.score,
          latencyMs: last.latencyMs,
          correct: correct,
        ),
      );
      if (correct) {
        _correct++;
      } else {
        _wrong++;
      }
    });
  }

  Future<void> _exportBench() async {
    if (_bench.isEmpty) return;
    final file = await BenchmarkLog.write(_bench);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '盲测记录 ${_bench.length} 条',
      ),
    );
  }

  String _headline() {
    if (!_modelReady) return '模型未接入';
    final last = _last;
    if (last == null) return '等待事件';
    if (last.score < _threshold) return '不确定';
    return _names[last.label] ?? last.label;
  }

  String _subtitle() {
    if (!_modelReady) return '去「模型」页导入 .zip 后自动生效';
    final last = _last;
    if (last == null) return '说句话或咳一声试试';
    final percent = (last.score * 100).toStringAsFixed(0);
    final base = '$percent% · 推理 ${last.latencyMs} ms';
    return last.score < _threshold
        ? '$base · 低于阈值 ${(_threshold * 100).toStringAsFixed(0)}%'
        : base;
  }

  String _waveStatus() {
    if (recorder.recording) {
      return '${recorder.elapsedSeconds.toStringAsFixed(1)} s · 48 kHz · '
          '峰值 ${recorder.peakDb.toStringAsFixed(0)} dB';
    }
    if (recorder.peaks.isEmpty) return '未开始';
    final total = recorder.peaks.length * 0.01;
    return '已停止 · 共 ${total.toStringAsFixed(1)} s · 左右拖动可回看';
  }

  List<EventMarker> _markers() {
    final now = recorder.elapsedSeconds;
    final markers = <EventMarker>[];
    for (final event in _events) {
      final endAgo = now - event.endSec;
      if (endAgo < 0) continue;
      markers.add(
        EventMarker(endAgoSeconds: endAgo, durationSeconds: event.durationSec),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final landscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final wave = _waveBlock(context, scheme);
        final panel = _panel(context, scheme);

        if (landscape) {
          // 横屏：波形占左 3/4 高度，信息流在右侧独立滚动，别把曲线挤扁
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: wave,
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  children: panel,
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [SizedBox(height: 170, child: wave), ...panel],
        );
      },
    );
  }

  Widget _waveBlock(BuildContext context, ColorScheme scheme) {
    final recording = recorder.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: WaveformView(
                peaks: recorder.peaks,
                markers: _markers(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _waveStatus(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (recording)
              Icon(Icons.fiber_manual_record,
                  size: 12, color: scheme.error),
          ],
        ),
      ],
    );
  }

  List<Widget> _panel(BuildContext context, ColorScheme scheme) {
    final recording = recorder.recording;
    final last = _last;
    final labels = widget.classifierProvider.classifier.labels;

    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('当前判定', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  Text('事件 ${_events.length}',
                      style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(_headline(),
                  style: Theme.of(context).textTheme.displaySmall),
              Text(_subtitle(), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (var i = 0; i < labels.length; i++)
                _scoreRow(
                  context,
                  _names[labels[i]] ?? labels[i],
                  last == null || i >= last.scores.length ? 0 : last.scores[i],
                  scheme,
                ),
            ],
          ),
        ),
      ),
      if (_events.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Text('事件流', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            TextButton(
              onPressed: _exportBench,
              child: Text('导出盲测 ${_bench.length}'),
            ),
          ],
        ),
        for (var i = _events.length - 1;
            i >= 0 && i >= _events.length - 5;
            i--)
          _eventRow(context, _events[i], scheme),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _last == null ? null : () => _mark(true),
              icon: const Icon(Icons.check, size: 18),
              label: Text('判对 $_correct'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _last == null ? null : () => _mark(false),
              icon: const Icon(Icons.close, size: 18),
              label: Text('判错 $_wrong'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _toggle,
        icon: Icon(recording ? Icons.stop : Icons.bolt),
        label: Text(recording ? '停止识别' : '开始识别'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    ];
  }

  Widget _scoreRow(
    BuildContext context,
    String label,
    double value,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(value * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(BuildContext context, AppEvent event, ColorScheme scheme) {
    final low = event.scores.isEmpty ||
        event.scores.reduce((a, b) => a > b ? a : b) < _threshold;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('${event.startSec.toStringAsFixed(1)}s',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              low
                  ? '不确定'
                  : (_names[event.predictedLabel] ?? event.predictedLabel),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text('${event.latencyMs} ms',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
