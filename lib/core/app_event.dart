import 'dart:convert';
import 'dart:io';

/// 一次检测事件。时间戳相对「这次录音的开始」，单位微秒。
class AppEvent {
  AppEvent({
    required this.startMicros,
    required this.endMicros,
    required this.predictedLabel,
    required this.scores,
    required this.latencyMs,
    this.humanLabel,
  });

  final int startMicros;
  final int endMicros;
  final String predictedLabel;
  final List<double> scores;
  final int latencyMs;

  /// 人工标注结果，优先级高于模型预测。
  String? humanLabel;

  double get startSec => startMicros / 1000000.0;

  double get endSec => endMicros / 1000000.0;

  double get durationSec => (endMicros - startMicros) / 1000000.0;

  bool get isPending =>
      predictedLabel == 'pending' || predictedLabel == 'unknown';

  String get displayLabel {
    final human = humanLabel;
    if (human != null && human.isNotEmpty) return human;
    return isPending ? '待分类' : predictedLabel;
  }

  Map<String, dynamic> toJson() => {
        'start_us': startMicros,
        'end_us': endMicros,
        'predicted': predictedLabel,
        'scores': scores,
        'latency_ms': latencyMs,
        'human': humanLabel,
      };

  static AppEvent fromJson(Map<String, dynamic> json) {
    final rawScores = (json['scores'] as List?) ?? const [];
    return AppEvent(
      startMicros: (json['start_us'] as num?)?.toInt() ?? 0,
      endMicros: (json['end_us'] as num?)?.toInt() ?? 0,
      predictedLabel: (json['predicted'] as String?) ?? 'unknown',
      scores: rawScores.map((e) => (e as num).toDouble()).toList(),
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      humanLabel: json['human'] as String?,
    );
  }
}

/// 事件与标注的落盘。
///
/// 每条录音旁边放两个文件：
///   `p03_swallow_20261125_130500.events.json`  事件起止 + 预测 + 人工标注
///   `p03_swallow_20261125_130500.labels.csv`   给训练端直接读的表格
class EventStore {
  static File _eventsFile(String wavPath) {
    final base = _stripExt(wavPath);
    return File('$base.events.json');
  }

  static File _labelsFile(String wavPath) {
    final base = _stripExt(wavPath);
    return File('$base.labels.csv');
  }

  static String _stripExt(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return path.substring(0, path.length - 4);
    return path;
  }

  static Future<void> save(String wavPath, List<AppEvent> events) async {
    final file = _eventsFile(wavPath);
    final payload = events.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(payload));
    await writeLabelsCsv(wavPath, events);
  }

  static Future<List<AppEvent>> load(String wavPath) async {
    final file = _eventsFile(wavPath);
    if (!await file.exists()) return <AppEvent>[];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <AppEvent>[];
      return raw
          .whereType<Map>()
          .map((e) => AppEvent.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return <AppEvent>[];
    }
  }

  static Future<File> writeLabelsCsv(
    String wavPath,
    List<AppEvent> events,
  ) async {
    final file = _labelsFile(wavPath);
    final buffer = StringBuffer('start_sec,end_sec,duration_sec,predicted,human\n');
    for (final e in events) {
      buffer.writeln(
        '${e.startSec.toStringAsFixed(3)},'
        '${e.endSec.toStringAsFixed(3)},'
        '${e.durationSec.toStringAsFixed(3)},'
        '${e.predictedLabel},'
        '${e.humanLabel ?? ''}',
      );
    }
    await file.writeAsString(buffer.toString());
    return file;
  }
}
