import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

import '../contracts/classifier.dart';
import '../wav_reader.dart';

/// 真正的端侧推理。
///
/// 输入约定全部来自导出包的 `preprocess.json`，不在这里写死：
/// 窗长取 [ModelInputSpec.windowSamples]，归一化方式取 [ModelInputSpec.normalize]。
///
/// 归一化必须和训练端逐位一致（逐窗 z-score），否则模型看起来在跑、结果全错。
class TfliteClassifier implements Classifier {
  TfliteClassifier._(this._interpreter, this.labels, this._input, this._modelPath);

  final tfl.Interpreter _interpreter;
  final List<String> labels;
  final ModelInputSpec _input;
  final String _modelPath;

  static Future<TfliteClassifier> load({
    required String modelPath,
    required List<String> labels,
    required ModelInputSpec input,
  }) async {
    final interpreter = tfl.Interpreter.fromFile(File(modelPath));
    interpreter.allocateTensors();

    final shape = interpreter.getInputTensor(0).shape;
    final flat = shape.fold<int>(1, (acc, dim) => acc * dim);
    if (flat != input.windowSamples) {
      interpreter.close();
      throw StateError(
        '模型输入有 $flat 个点，preprocess.json 说 ${input.windowSamples} 个点，对不上',
      );
    }
    if (labels.isEmpty) {
      interpreter.close();
      throw StateError('labels.txt 是空的');
    }

    return TfliteClassifier._(interpreter, labels, input, modelPath);
  }

  @override
  String get name => 'TFLite · ${_modelPath.split('/').last}';

  @override
  bool get ready => true;

  @override
  ModelInputSpec get input => _input;

  @override
  Future<List<double>> classifyWindow(Float32List window) async {
    final shape = _interpreter.getInputTensor(0).shape;
    final prepared = _normalize(window);
    final inputData = prepared.reshape(shape);
    final output = List<double>.filled(labels.length, 0).reshape([1, labels.length]);

    _interpreter.run(inputData, output);

    final row = output.first as List;
    return row.map((value) => (value as num).toDouble()).toList();
  }

  Float32List _normalize(Float32List window) {
    if (_input.normalize != 'per_window_zscore') return window;

    var sum = 0.0;
    for (final value in window) {
      sum += value;
    }
    final mean = sum / window.length;

    var square = 0.0;
    for (final value in window) {
      final delta = value - mean;
      square += delta * delta;
    }
    final std = math.sqrt(square / window.length) + 1e-8;

    final out = Float32List(window.length);
    for (var i = 0; i < window.length; i++) {
      out[i] = (window[i] - mean) / std;
    }
    return out;
  }

  /// 离线分析：取文件末尾一个窗。片段是裁好的，事件就在末尾附近。
  @override
  Future<List<double>> classifyFile(String wavPath) async {
    final wav = await readWav(wavPath);
    final need = _input.windowSamples;
    final samples = Float32List(need);
    final startFrame = wav.frameCount - need;
    final data = ByteData.sublistView(wav.pcm);
    final bps = wav.bytesPerSample;

    for (var i = 0; i < need; i++) {
      final frame = startFrame + i;
      if (frame < 0 || frame >= wav.frameCount) continue;
      final offset = frame * bps;
      if (offset + 2 > wav.pcm.lengthInBytes) continue;
      samples[i] = data.getInt16(offset, Endian.little) / 32768.0;
    }
    return classifyWindow(samples);
  }

  @override
  Future<void> dispose() async {
    _interpreter.close();
  }
}
