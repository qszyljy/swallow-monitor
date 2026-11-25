import 'package:flutter/material.dart';

import '../core/recorder_service.dart';
import 'waveform_view.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key, required this.recorder});

  final RecorderService recorder;

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
                        recording ? Icons.fiber_manual_record : Icons.circle_outlined,
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
                  _labelPicker(context, enabled: !recording),
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
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _toggle(context),
                    icon: Icon(recording ? Icons.stop : Icons.mic),
                    label: Text(recording ? '停止并保存' : '开始录音'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 8),
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

  Widget _labelPicker(BuildContext context, {required bool enabled}) {
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
}
