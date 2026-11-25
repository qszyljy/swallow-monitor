import 'package:flutter/material.dart';

import '../core/app_event.dart';

/// 回看一条录音的事件，并人工标注类别。
///
/// 标注结果写回 `*.events.json` 和 `*.labels.csv`，
/// 训练端就能用精确的事件边界，而不是靠能量峰值去猜。
class EventAnnotationPage extends StatefulWidget {
  const EventAnnotationPage({super.key, required this.wavPath});

  final String wavPath;

  @override
  State<EventAnnotationPage> createState() => _EventAnnotationPageState();
}

class _EventAnnotationPageState extends State<EventAnnotationPage> {
  static const Map<String, String> _names = {
    'swallow': '吞咽',
    'cough': '咳嗽',
    'interfere': '干扰',
    'rest': '静息',
  };

  List<AppEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await EventStore.load(widget.wavPath);
    if (!mounted) return;
    setState(() => _events = events);
  }

  Future<void> _label(int index, String label) async {
    final events = _events;
    if (events == null) return;
    setState(() => events[index].humanLabel = label);
    await EventStore.save(widget.wavPath, events);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已标注为「${_names[label] ?? label}」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.wavPath.split('/').last;
    final events = _events;
    return Scaffold(
      appBar: AppBar(title: Text(name, style: const TextStyle(fontSize: 15))),
      body: events == null
          ? const Center(child: CircularProgressIndicator())
          : events.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '这条录音没有事件记录。\n'
                      '可能是旧版本录的，或者当时没有检测到事件。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('#${index + 1}',
                                    style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(width: 8),
                                Text(
                                  '${event.startSec.toStringAsFixed(2)}s → '
                                  '${event.endSec.toStringAsFixed(2)}s · '
                                  '${event.durationSec.toStringAsFixed(2)}s',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const Spacer(),
                                Text(
                                  event.isPending ? '未分类' : event.predictedLabel,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final entry in _names.entries)
                                  ChoiceChip(
                                    label: Text(entry.value),
                                    selected: event.humanLabel == entry.key,
                                    onSelected: (_) => _label(index, entry.key),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
