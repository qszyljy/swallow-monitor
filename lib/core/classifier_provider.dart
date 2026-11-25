import 'dart:async';

import 'package:flutter/foundation.dart';

import 'contracts/classifier.dart';
import 'impls/tflite_classifier.dart';
import 'model_manager.dart';
import 'spec.dart';

/// 全局分类器：有可用模型就上 TFLite，否则退回占位。
///
/// 模型页导入成功后调用 [load] 就能热切换，不需要重启 App。
class ClassifierProvider extends ChangeNotifier {
  Classifier _classifier = const PlaceholderClassifier();
  String? _error;

  Classifier get classifier => _classifier;

  String? get error => _error;

  bool get ready => _classifier.ready;

  Future<void> load() async {
    final previous = _classifier;
    _error = null;
    try {
      final package = await ModelManager.describeActive();
      if (package == null) {
        _classifier = const PlaceholderClassifier();
      } else {
        final issues = package.checkAgainstApp(PipelineSpec.current);
        if (issues.isNotEmpty) {
          _error = issues.join('；');
          _classifier = const PlaceholderClassifier();
        } else {
          _classifier = await TfliteClassifier.load(
            modelPath: package.modelPath,
            labels: package.labels,
            input: package.input,
          );
        }
      }
    } catch (e) {
      _error = '模型加载失败：$e';
      _classifier = const PlaceholderClassifier();
    }

    // 旧的释放掉（占位实现是 no-op，TFLite 会关 interpreter）
    if (!identical(previous, _classifier)) {
      unawaited(previous.dispose());
    }
    notifyListeners();
  }
}
