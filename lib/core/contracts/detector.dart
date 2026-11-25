import 'dart:async';

import 'sample_source.dart';
import 'segmenter.dart';

/// 一次检测的输出。界面、日志、盲测记录都用这个结构。
class DetectionResult {
  const DetectionResult({
    required this.label,
    required this.scores,
    required this.score,
    required this.startMicros,
    required this.timestampMicros,
    required this.latencyMs,
    required this.isEvent,
  });

  /// 判定类别；静息时是 'rest'
  final String label;
  final List<double> scores;

  /// 判定类的分数
  final double score;

  /// 事件开始时刻（设备时间戳）
  final int startMicros;

  /// 事件结束时刻（设备时间戳），不是出结果的时刻
  final int timestampMicros;

  /// 帧就绪 → 出结果。任务书 20 ms 说的是这个。
  final int latencyMs;

  /// 是否确认为事件（通过了投票和冷却）
  final bool isEvent;
}

/// 装配线：SampleSource → 能量 → EventSegmenter → Classifier → 投票 → DetectionResult。
///
/// 界面只订阅 [results]，不关心数据来自麦克风还是蓝牙。
/// 换成双路时，新的实现内部跑两个 SampleSource，按 deviceTimestampMicros 对齐即可。
abstract class Detector {
  Stream<DetectionResult> get results;

  List<String> get labels;

  bool get ready;

  void handleFrame(SampleFrame frame);

  void reset();

  Future<void> dispose();
}
