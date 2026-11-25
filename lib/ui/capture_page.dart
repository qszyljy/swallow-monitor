import 'dart:async';

import 'package:flutter/material.dart';

import '../core/contracts/classifier.dart';
import '../core/contracts/detector.dart';
import '../core/contracts/sample_source.dart';
import '../core/impls/mic_detector.dart';
import '../core/recorder_service.dart';
import '../core/spec.dart';
import 'waveform_view.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.recorder});

  final RecorderService recorder;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late final MicDetector _detector;
  StreamSubscription<SampleFrame>? _frameSub;
  StreamSubscription<DetectionResult>? _resultSub;
  DetectionResult? _last;
  int _events = 0;

  RecorderService get recorder => widget.recorder;

  @override
  void initState() {
    super.initState();
    _detector = MicDetector(
      specProvider: () => PipelineSpec.current,
      classifier: const PlaceholderClassifier(),
    );
    _frameSub = recorder.frames.listen(_detector.handleFrame);
    _resultSub = _detector.results.listen((result) {
      if (!mounted) return;
      setState(() {
        _last = result;
        _events = _detector.eventCount;
      });
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _resultSub?.cancel();
    unawaited(_detector.dispose());
    super.dispose();
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (recorder.recording) {
      final seconds = recorder.recordedSeconds;
      await recorder.stop();
      final name = recorder.lastFile?.split('/').last ?? '录音';
      messenger.showSnackBar(
        SnackBar(content: Text('已保存 $name（${seconds.toStringAsFixed(1)} s）')),
      );
    } else {
      _detector.reset();
      setState(() {
        _events = 0;
        _last = null;
      });
      await recorder.start();
      if (recorder.error != null) {
        messenger.showSnackBar(SnackBar(content: Text(recorder.error!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final recording = recorder.recording;
        return Scaffold(
          appBar: AppBar(
            title: const Text('采集'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Row(
                    children: [
                      Icon(
                        recording
                            ? Icons.fiber_manual_record
                            : Icons.circle_outlined,
                        size: 12,
                        color: recording ? scheme.error : scheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text('${recorder.subject} · ${recording ? '录音中' : '待机'}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subjectRow(context, enabled: !recording),
                  const SizedBox(height: 8),
                  _labelPicker(enabled: !recording),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: WaveformView(peaks: recorder.peaks),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _metrics(context),
                  const SizedBox(height: 8),
                  _detectionCard(context),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _toggle(context),
                    icon: Icon(recording ? Icons.stop : Icons.mic),
                    label: Text(recording ? '停止并保存' : '开始录音'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '48 kHz · 单声道 · 16 bit · 已关闭 AGC / 降噪 / 回声消除\n'
                    '每个动作前后留 1 s 静息；每类每被试 ≥ 10 条',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _subjectRow(BuildContext context, {required bool enabled}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.person_outline, size: 18, color: scheme.outline),
        const SizedBox(width: 6),
        Text('被试', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 8),
        ActionChip(
          label: Text(recorder.subject),
          onPressed: enabled ? () => _pickSubject(context) : null,
        ),
      ],
    );
  }

  Future<void> _pickSubject(BuildContext context) async {
    final controller = TextEditingController(text: recorder.subject);
    String chip(int i) => 'p${i.toString().padLeft(2, '0')}';

    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('被试编号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 1; i <= 8; i++)
                  ActionChip(
                    label: Text(chip(i)),
                    onPressed: () => Navigator.pop(dialogContext, chip(i)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '或手动输入',
                helperText: '字母或数字，最多 8 位',
              ),
              maxLength: 8,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (picked == null) return;
    if (!recorder.setSubject(picked) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('编号只能是字母或数字')),
      );
    }
  }

  Widget _labelPicker({required bool enabled}) {
    return Wrap(
      spacing: 8,
      children: [
        for (final e in EventLabel.values)
          ChoiceChip(
            label: Text(e.note),
            selected: recorder.label == e,
            onSelected: enabled ? (_) => recorder.setLabel(e) : null,
          ),
      ],
    );
  }

  Widget _metrics(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget cell(String value, String label) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: style),
              Text(label, style: small),
            ],
          ),
        );
    return Row(
      children: [
        cell('${recorder.elapsedSeconds.toStringAsFixed(1)} s', '已录时长'),
        cell('48 kHz', '采样率'),
        cell('${recorder.peakDb.toStringAsFixed(0)} dB', '峰值'),
      ],
    );
  }

  Widget _detectionCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _last;
    final label =
        last == null ? '—' : (last.label == 'pending' ? '待分类' : last.label);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('实时检测', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text('事件 $_events',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              last == null
                  ? '等待事件…'
                  : '$label · ${(last.score * 100).toStringAsFixed(0)}% · '
                      '推理 ${last.latencyMs} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!_detector.ready)
              Text(
                '模型未接入：只统计事件次数，类别显示「待分类」',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}
