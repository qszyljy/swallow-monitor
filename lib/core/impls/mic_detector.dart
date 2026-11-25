import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../contracts/classifier.dart';
import '../contracts/detector.dart';
import '../contracts/sample_source.dart';
import '../contracts/segmenter.dart';
import '../spec.dart';

/// 单路麦克风检测：帧 → 能量 → 分割 → 分类 → 投票 → 结果。
///
/// 分工是「分割决定有没有事件，分类决定是什么」，两件事分开之后，
/// 静息段不跑推理，误触发率也有地方统计。
class MicDetector implements Detector {
  MicDetector({
    required this.specProvider,
    required this.classifier,
  }) : _segmenter = EnergyGateSegmenter(specProvider().detection);

  final PipelineSpec Function() specProvider;
  final Classifier classifier;
  final EnergyGateSegmenter _segmenter;

  final StreamController<DetectionResult> _results =
      StreamController<DetectionResult>.broadcast();

  /// 环形缓冲：保留最近两个窗，足够切一个完整窗出来。
  final List<double> _ring = <double>[];
  final List<String> _votes = <String>[];

  int _totalSamples = 0;
  int _sinceHop = 0;
  int _eventCount = 0;
  bool _busy = false;

  @override
  Stream<DetectionResult> get results => _results.stream;

  @override
  List<String> get labels => classifier.labels;

  @override
  bool get ready => classifier.ready;

  int get eventCount => _eventCount;

  @override
  void handleFrame(SampleFrame frame) {
    final spec = specProvider();
    final sr = frame.sampleRate;
    final data = ByteData.sublistView(frame.samples);
    final n = frame.samples.lengthInBytes ~/ 2;

    for (var i = 0; i < n; i++) {
      _ring.add(data.getInt16(i * 2, Endian.little) / 32768.0);
    }
    final maxSamples = spec.window.samplesAt(sr) * 2;
    if (_ring.length > maxSamples) {
      _ring.removeRange(0, _ring.length - maxSamples);
    }

    _totalSamples += n;
    _sinceHop += n;

    final hop = math.max(1, (spec.detection.energyHopMs * sr / 1000).round());
    final frameLen =
        math.max(1, (spec.detection.energyFrameMs * sr / 1000).round());

    while (_sinceHop >= hop) {
      _sinceHop -= hop;
      final endSample = _totalSamples - _sinceHop;
      final ringEnd = _ring.length - _sinceHop;
      final ringStart = ringEnd - frameLen;
      if (ringStart < 0) continue;

      var sum = 0.0;
      for (var i = ringStart; i < ringEnd; i++) {
        sum += _ring[i] * _ring[i];
      }
      final rms = math.sqrt(sum / frameLen);
      final db = 20 * (math.log(rms + 1e-9) / math.ln10);
      final timestamp = endSample * 1000000 ~/ sr;

      final candidate = _segmenter.update(
        energyDb: db,
        timestampMicros: timestamp,
      );
      if (candidate != null) {
        unawaited(_onCandidate(candidate, spec));
      }
    }
  }

  Future<void> _onCandidate(EventCandidate candidate, PipelineSpec spec) async {
    if (_busy) return;
    final need = spec.window.samplesAt(spec.audio.sampleRate);
    if (_ring.length < need) return;

    _busy = true;
    final watch = Stopwatch()..start();
    try {
      final window = Float32List(need);
      final offset = _ring.length - need;
      for (var i = 0; i < need; i++) {
        window[i] = _ring[offset + i];
      }

      final scores = await classifier.classifyWindow(window);
      watch.stop();

      final label = _argmaxLabel(scores);
      _votes.add(label);
      if (_votes.length > spec.detection.voteWindows) {
        _votes.removeAt(0);
      }

      // 分割已经保证「有事件」，投票只用来稳住类别
      final majority = _majority(spec);
      _eventCount++;

      if (!_results.isClosed) {
        _results.add(
          DetectionResult(
            label: classifier.ready ? majority : 'pending',
            scores: scores,
            score: scores.isEmpty ? 0 : scores[_argmax(scores)],
            timestampMicros: candidate.endMicros,
            latencyMs: watch.elapsedMilliseconds,
            isEvent: true,
          ),
        );
      }
    } catch (_) {
      // 单次推理失败不该让整个检测停掉
    } finally {
      _busy = false;
    }
  }

  int _argmax(List<double> scores) {
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return best;
  }

  String _argmaxLabel(List<double> scores) {
    if (scores.isEmpty || labels.isEmpty) return 'unknown';
    final index = _argmax(scores);
    return index < labels.length ? labels[index] : 'unknown';
  }

  String _majority(PipelineSpec spec) {
    if (_votes.isEmpty) return 'unknown';
    final counts = <String, int>{};
    for (final v in _votes) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  @override
  void reset() {
    _ring.clear();
    _votes.clear();
    _segmenter.reset();
    _totalSamples = 0;
    _sinceHop = 0;
    _eventCount = 0;
    _busy = false;
  }

  @override
  Future<void> dispose() async {
    await _results.close();
    await classifier.dispose();
  }
}
