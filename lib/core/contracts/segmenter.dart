import '../spec.dart';

enum SegmentState { idle, candidate, active }

/// 一个刚结束的事件。送去分类的是这段时间的波形。
class EventCandidate {
  const EventCandidate({required this.startMicros, required this.endMicros});

  final int startMicros;
  final int endMicros;

  int get durationMicros => endMicros - startMicros;

  int get durationMs => durationMicros ~/ 1000;
}

/// 事件分割。
///
/// 特意让输入是「能量值」而不是音频帧：这样可以脱离文件、脱离设备做单测，
/// 改阈值不用重装 APK 试。
abstract class EventSegmenter {
  SegmentState get state;

  /// 输入一帧能量（dBFS）与它的时间戳。
  /// 返回非空表示一个事件在此时结束，可以送去分类。
  EventCandidate? update({required double energyDb, required int timestampMicros});

  void reset();
}

/// 迟滞双阈值 + 最短/最长时长 + 冷却。参考实现，参数全部来自 DetectionSpec。
class EnergyGateSegmenter implements EventSegmenter {
  EnergyGateSegmenter(this.spec);

  final DetectionSpec spec;

  SegmentState _state = SegmentState.idle;
  int? _startMicros;
  int? _lastEndMicros;

  @override
  SegmentState get state => _state;

  @override
  EventCandidate? update({
    required double energyDb,
    required int timestampMicros,
  }) {
    final cooldownMicros = spec.cooldownMs * 1000;
    if (_lastEndMicros != null &&
        timestampMicros - _lastEndMicros! < cooldownMicros) {
      return null;
    }

    switch (_state) {
      case SegmentState.idle:
      case SegmentState.candidate:
        if (energyDb >= spec.thresholdOnDb) {
          _state = SegmentState.active;
          _startMicros = timestampMicros;
        }
        return null;

      case SegmentState.active:
        final start = _startMicros ?? timestampMicros;
        if (energyDb < spec.thresholdOffDb) {
          _state = SegmentState.idle;
          _startMicros = null;
          _lastEndMicros = timestampMicros;
          final durationMs = (timestampMicros - start) ~/ 1000;
          if (durationMs >= spec.minEventMs && durationMs <= spec.maxEventMs) {
            return EventCandidate(
              startMicros: start,
              endMicros: timestampMicros,
            );
          }
          return null;
        }
        // 一直不回落：超过上限就当失败事件丢掉，避免把一段说话拖成巨长事件
        if ((timestampMicros - start) ~/ 1000 > spec.maxEventMs) {
          _state = SegmentState.idle;
          _startMicros = null;
          _lastEndMicros = timestampMicros;
        }
        return null;
    }
    // 枚举已穷尽，这行只是为了满足返回类型
    return null;
  }

  @override
  void reset() {
    _state = SegmentState.idle;
    _startMicros = null;
    _lastEndMicros = null;
  }
}
