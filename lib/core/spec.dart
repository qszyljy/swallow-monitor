import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 手机端唯一的参数源。
///
/// 所有数字（采样率、窗长、步长、阈值、投票、时延口径、同步容差）
/// 都只在 `assets/spec.default.json` 里出现一次，代码里禁止再写字面量。
///
/// 模型导出包带来的 `preprocess.json` 会覆盖其中和模型相关的部分
/// （采样率、窗长、归一化、类别顺序），实现见 ModelPackage。
class PipelineSpec {
  const PipelineSpec({
    required this.version,
    required this.audio,
    required this.window,
    required this.normalize,
    required this.classes,
    required this.detection,
    required this.sync,
    required this.latency,
    required this.package,
  });

  final int version;
  final AudioSpec audio;
  final WindowSpec window;
  final NormalizeSpec normalize;
  final List<String> classes;
  final DetectionSpec detection;
  final SyncSpec sync;
  final LatencySpec latency;
  final PackageSpec package;

  /// 当前生效的配置。启动时由 [loadBundled] 替换，失败则保留兜底值。
  static PipelineSpec current = PipelineSpec.baseline();

  factory PipelineSpec.baseline() => const PipelineSpec(
        version: 1,
        audio: AudioSpec(sampleRate: 48000, channels: 1, bitDepth: 16),
        window: WindowSpec(seconds: 1.0, hopSeconds: 0.25),
        normalize: NormalizeSpec(mode: 'per_window_zscore'),
        classes: ['swallow', 'cough', 'interfere'],
        detection: DetectionSpec(
          energyFrameMs: 25,
          energyHopMs: 10,
          thresholdOnDb: -35,
          thresholdOffDb: -45,
          minEventMs: 200,
          maxEventMs: 1500,
          cooldownMs: 500,
          voteWindows: 3,
          voteMinHits: 2,
        ),
        sync: SyncSpec(toleranceMs: 10, beepAnchor: true, maxDriftPpm: 200),
        latency: LatencySpec(frameReadyBudgetMs: 20, responseBudgetMs: 300),
        package: PackageSpec(
          labelsFile: 'labels.txt',
          preprocessFile: 'preprocess.json',
          modelFileName: 'model.tflite',
        ),
      );

  factory PipelineSpec.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> part(String key) =>
        (json[key] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    return PipelineSpec(
      version: (json['version'] as num?)?.toInt() ?? 1,
      audio: AudioSpec.fromJson(part('audio')),
      window: WindowSpec.fromJson(part('window')),
      normalize: NormalizeSpec.fromJson(part('normalize')),
      classes: (json['classes'] as List?)?.cast<String>() ?? const ['swallow'],
      detection: DetectionSpec.fromJson(part('detection')),
      sync: SyncSpec.fromJson(part('sync')),
      latency: LatencySpec.fromJson(part('latency')),
      package: PackageSpec.fromJson(part('package')),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'audio': audio.toJson(),
        'window': window.toJson(),
        'normalize': normalize.toJson(),
        'classes': classes,
        'detection': detection.toJson(),
        'sync': sync.toJson(),
        'latency': latency.toJson(),
        'package': package.toJson(),
      };

  PipelineSpec copyWith({List<String>? classes}) => PipelineSpec(
        version: version,
        audio: audio,
        window: window,
        normalize: normalize,
        classes: classes ?? this.classes,
        detection: detection,
        sync: sync,
        latency: latency,
        package: package,
      );

  /// 启动自检。返回空列表表示没问题；有问题就应当在启动日志里说出来，
  /// 而不是等到采完 240 条数据才发现窗长和步长不是整数倍。
  List<String> validate() {
    final issues = <String>[];
    if (audio.sampleRate <= 0) issues.add('采样率必须大于 0');
    if (audio.channels <= 0) issues.add('通道数必须大于 0');
    if (window.seconds <= 0 || window.hopSeconds <= 0) {
      issues.add('窗长和步长必须大于 0');
    }
    if (window.hopSeconds > window.seconds) issues.add('步长不能大于窗长');
    final ratio = window.seconds / window.hopSeconds;
    if ((ratio - ratio.roundToDouble()).abs() > 1e-6) {
      issues.add('窗长应当是步长的整数倍（当前 ${window.seconds}/${window.hopSeconds}）');
    }
    if (detection.thresholdOffDb >= detection.thresholdOnDb) {
      issues.add('关闭阈值必须低于开启阈值，否则没有迟滞、会反复触发');
    }
    if (detection.minEventMs <= 0 || detection.maxEventMs <= detection.minEventMs) {
      issues.add('事件时长上下限不合法');
    }
    if (detection.voteMinHits <= 0 || detection.voteMinHits > detection.voteWindows) {
      issues.add('投票命中数必须在 1 到 窗口数 之间');
    }
    if (classes.isEmpty) issues.add('类别列表不能为空');
    if (sync.toleranceMs <= 0) issues.add('同步容差必须为正');
    if (latency.frameReadyBudgetMs <= 0) issues.add('帧就绪时延预算必须为正');
    return issues;
  }

  /// 从打包的 JSON 读取。抛异常时调用方应保留 [current] 的兜底值。
  static Future<PipelineSpec> loadBundled([String assetPath = 'assets/spec.default.json']) async {
    final raw = await rootBundle.loadString(assetPath);
    final spec = PipelineSpec.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final issues = spec.validate();
    if (issues.isNotEmpty) {
      throw FormatException('spec 自检失败：${issues.join('；')}');
    }
    current = spec;
    return spec;
  }
}

class AudioSpec {
  const AudioSpec({
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
  });

  final int sampleRate;
  final int channels;
  final int bitDepth;

  factory AudioSpec.fromJson(Map<String, dynamic> json) => AudioSpec(
        sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 48000,
        channels: (json['channels'] as num?)?.toInt() ?? 1,
        bitDepth: (json['bitDepth'] as num?)?.toInt() ?? 16,
      );

  Map<String, dynamic> toJson() => {
        'sampleRate': sampleRate,
        'channels': channels,
        'bitDepth': bitDepth,
      };
}

class WindowSpec {
  const WindowSpec({required this.seconds, required this.hopSeconds});

  final double seconds;
  final double hopSeconds;

  int samplesAt(int sampleRate) => (seconds * sampleRate).round();
  int hopSamplesAt(int sampleRate) => (hopSeconds * sampleRate).round();

  factory WindowSpec.fromJson(Map<String, dynamic> json) => WindowSpec(
        seconds: (json['seconds'] as num?)?.toDouble() ?? 1.0,
        hopSeconds: (json['hopSeconds'] as num?)?.toDouble() ?? 0.25,
      );

  Map<String, dynamic> toJson() => {'seconds': seconds, 'hopSeconds': hopSeconds};
}

class NormalizeSpec {
  const NormalizeSpec({required this.mode});

  final String mode;

  factory NormalizeSpec.fromJson(Map<String, dynamic> json) =>
      NormalizeSpec(mode: (json['mode'] as String?) ?? 'per_window_zscore');

  Map<String, dynamic> toJson() => {'mode': mode};
}

class DetectionSpec {
  const DetectionSpec({
    required this.energyFrameMs,
    required this.energyHopMs,
    required this.thresholdOnDb,
    required this.thresholdOffDb,
    required this.minEventMs,
    required this.maxEventMs,
    required this.cooldownMs,
    required this.voteWindows,
    required this.voteMinHits,
  });

  final double energyFrameMs;
  final double energyHopMs;
  final double thresholdOnDb;
  final double thresholdOffDb;
  final int minEventMs;
  final int maxEventMs;
  final int cooldownMs;
  final int voteWindows;
  final int voteMinHits;

  factory DetectionSpec.fromJson(Map<String, dynamic> json) => DetectionSpec(
        energyFrameMs: (json['energyFrameMs'] as num?)?.toDouble() ?? 25,
        energyHopMs: (json['energyHopMs'] as num?)?.toDouble() ?? 10,
        thresholdOnDb: (json['thresholdOnDb'] as num?)?.toDouble() ?? -35,
        thresholdOffDb: (json['thresholdOffDb'] as num?)?.toDouble() ?? -45,
        minEventMs: (json['minEventMs'] as num?)?.toInt() ?? 200,
        maxEventMs: (json['maxEventMs'] as num?)?.toInt() ?? 1500,
        cooldownMs: (json['cooldownMs'] as num?)?.toInt() ?? 500,
        voteWindows: (json['voteWindows'] as num?)?.toInt() ?? 3,
        voteMinHits: (json['voteMinHits'] as num?)?.toInt() ?? 2,
      );

  Map<String, dynamic> toJson() => {
        'energyFrameMs': energyFrameMs,
        'energyHopMs': energyHopMs,
        'thresholdOnDb': thresholdOnDb,
        'thresholdOffDb': thresholdOffDb,
        'minEventMs': minEventMs,
        'maxEventMs': maxEventMs,
        'cooldownMs': cooldownMs,
        'voteWindows': voteWindows,
        'voteMinHits': voteMinHits,
      };
}

class SyncSpec {
  const SyncSpec({
    required this.toleranceMs,
    required this.beepAnchor,
    required this.maxDriftPpm,
  });

  /// 任务书要求两路对齐误差 ≤ 10 ms。
  final int toleranceMs;
  final bool beepAnchor;
  final int maxDriftPpm;

  factory SyncSpec.fromJson(Map<String, dynamic> json) => SyncSpec(
        toleranceMs: (json['toleranceMs'] as num?)?.toInt() ?? 10,
        beepAnchor: (json['beepAnchor'] as bool?) ?? true,
        maxDriftPpm: (json['maxDriftPpm'] as num?)?.toInt() ?? 200,
      );

  Map<String, dynamic> toJson() => {
        'toleranceMs': toleranceMs,
        'beepAnchor': beepAnchor,
        'maxDriftPpm': maxDriftPpm,
      };
}

class LatencySpec {
  const LatencySpec({
    required this.frameReadyBudgetMs,
    required this.responseBudgetMs,
  });

  /// 任务书口径：帧数据就绪 → 结果输出。
  final int frameReadyBudgetMs;

  /// 用户感知口径：事件发生 → 出结果，约等于一个步长加推理时间。
  final int responseBudgetMs;

  factory LatencySpec.fromJson(Map<String, dynamic> json) => LatencySpec(
        frameReadyBudgetMs: (json['frameReadyBudgetMs'] as num?)?.toInt() ?? 20,
        responseBudgetMs: (json['responseBudgetMs'] as num?)?.toInt() ?? 300,
      );

  Map<String, dynamic> toJson() => {
        'frameReadyBudgetMs': frameReadyBudgetMs,
        'responseBudgetMs': responseBudgetMs,
      };
}

class PackageSpec {
  const PackageSpec({
    required this.labelsFile,
    required this.preprocessFile,
    required this.modelFileName,
  });

  final String labelsFile;
  final String preprocessFile;
  final String modelFileName;

  factory PackageSpec.fromJson(Map<String, dynamic> json) => PackageSpec(
        labelsFile: (json['labelsFile'] as String?) ?? 'labels.txt',
        preprocessFile: (json['preprocessFile'] as String?) ?? 'preprocess.json',
        modelFileName: (json['modelFileName'] as String?) ?? 'model.tflite',
      );

  Map<String, dynamic> toJson() => {
        'labelsFile': labelsFile,
        'preprocessFile': preprocessFile,
        'modelFileName': modelFileName,
      };
}
