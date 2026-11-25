import 'dart:typed_data';

import '../spec.dart';

/// 模型输入约定。这些值来自导出包的 `preprocess.json`，不是手写的。
class ModelInputSpec {
  const ModelInputSpec({
    required this.format,
    required this.sampleRate,
    required this.windowSamples,
    required this.normalize,
    required this.layout,
  });

  /// tflite / joblib / dart
  final String format;
  final int sampleRate;
  final int windowSamples;

  /// per_window_zscore 等，必须与训练端一致
  final String normalize;

  /// raw_waveform / mel_image
  final String layout;

  int get windowMs =>
      sampleRate == 0 ? 0 : windowSamples * 1000 ~/ sampleRate;

  factory ModelInputSpec.fromJson(Map<String, dynamic> json) {
    final model = (json['model'] as Map?)?.cast<String, dynamic>() ?? {};
    final sampleRate = (json['sample_rate'] as num?)?.toInt() ??
        PipelineSpec.current.audio.sampleRate;
    final windowSeconds =
        (json['window_seconds'] as num?)?.toDouble() ??
            PipelineSpec.current.window.seconds;
    return ModelInputSpec(
      format: (model['format'] as String?) ?? 'tflite',
      sampleRate: sampleRate,
      windowSamples: (windowSeconds * sampleRate).round(),
      normalize:
          ((json['normalize'] as Map?)?['mode'] as String?) ?? 'per_window_zscore',
      layout: (model['input'] as String?) ?? 'raw_waveform',
    );
  }

  Map<String, dynamic> toJson() => {
        'model': {'format': format, 'input': layout},
        'sample_rate': sampleRate,
        'window_seconds': sampleRate == 0 ? 0 : windowSamples / sampleRate,
        'normalize': {'mode': normalize},
      };
}

/// 分类器接口。
///
/// 现在只有占位实现；接 TFLite 时新写一个类实现它，界面和采集逻辑都不用改。
abstract class Classifier {
  String get name;

  /// 模型是否真的加载成功。false 时界面必须显示「未接入」，不许假装在工作。
  bool get ready;

  /// 与分数一一对应的类别顺序。
  List<String> get labels;

  ModelInputSpec get input;

  /// 单窗推理。输入长度应等于 [input.windowSamples]，返回与 [labels] 等长的分数。
  Future<List<double>> classifyWindow(Float32List window);

  /// 离线分析一条 wav：读文件 → 取窗 → 走 [classifyWindow]。
  Future<List<double>> classifyFile(String wavPath);

  Future<void> dispose();
}

/// 占位实现：分数恒为 0。用来把界面和状态机跑通，不许拿去演示。
class PlaceholderClassifier implements Classifier {
  const PlaceholderClassifier();

  @override
  String get name => '占位分类器（TFLite 未接入）';

  @override
  bool get ready => false;

  @override
  List<String> get labels => PipelineSpec.current.classes;

  @override
  ModelInputSpec get input {
    final spec = PipelineSpec.current;
    return ModelInputSpec(
      format: 'none',
      sampleRate: spec.audio.sampleRate,
      windowSamples: spec.window.samplesAt(spec.audio.sampleRate),
      normalize: spec.normalize.mode,
      layout: 'raw_waveform',
    );
  }

  @override
  Future<List<double>> classifyWindow(Float32List window) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return List<double>.filled(labels.length, 0);
  }

  @override
  Future<List<double>> classifyFile(String wavPath) async {
    return classifyWindow(Float32List(0));
  }

  @override
  Future<void> dispose() async {}
}
