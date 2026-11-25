import 'dart:convert';
import 'dart:io';

import 'classifier.dart';
import '../spec.dart';

/// 导出包 = 手机端唯一接口。
///
/// 训练端产出四件套：`labels.txt` / `preprocess.json` / 模型文件 / `eval.json`。
/// 这里负责读它、校验它、把它和 App 当前的 [PipelineSpec] 对齐。
///
/// 缺文件或参数对不上时**直接抛错 / 返回问题列表**，不许猜——
/// 猜错的结果是模型装上去看起来在跑，其实分数全是乱的。
class ModelPackage {
  const ModelPackage({
    required this.directory,
    required this.labels,
    required this.input,
    required this.preprocess,
    required this.modelPath,
  });

  final String directory;
  final List<String> labels;
  final ModelInputSpec input;
  final Map<String, dynamic> preprocess;
  final String modelPath;

  static Future<ModelPackage> load(String directory, {PipelineSpec? spec}) async {
    final s = spec ?? PipelineSpec.current;
    final dir = Directory(directory);
    if (!await dir.exists()) {
      throw StateError('模型目录不存在：$directory');
    }

    final labelsFile = File('${dir.path}/${s.package.labelsFile}');
    final preprocessFile = File('${dir.path}/${s.package.preprocessFile}');
    if (!await labelsFile.exists()) {
      throw StateError('缺少 ${s.package.labelsFile}');
    }
    if (!await preprocessFile.exists()) {
      throw StateError('缺少 ${s.package.preprocessFile}');
    }

    final labels = (await labelsFile.readAsString())
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final preprocess =
        jsonDecode(await preprocessFile.readAsString()) as Map<String, dynamic>;
    final modelJson = (preprocess['model'] as Map?)?.cast<String, dynamic>() ?? {};
    final modelName = (modelJson['file'] as String?) ?? s.package.modelFileName;
    final model = File('${dir.path}/$modelName');
    if (!await model.exists()) {
      throw StateError('缺少模型文件 $modelName');
    }

    return ModelPackage(
      directory: dir.path,
      labels: labels,
      input: ModelInputSpec.fromJson(preprocess),
      preprocess: preprocess,
      modelPath: model.path,
    );
  }

  /// 两端一致性检查。返回空列表才允许加载模型。
  ///
  /// 这四条是踩过的坑：采样率、窗长、归一化、类别顺序。
  /// 任何一条不一致，模型输出就没有解释意义。
  List<String> checkAgainstApp(PipelineSpec spec) {
    final issues = <String>[];

    if (input.sampleRate != spec.audio.sampleRate) {
      issues.add('采样率不一致：模型 ${input.sampleRate}，App ${spec.audio.sampleRate}');
    }
    final appWindow = spec.window.samplesAt(spec.audio.sampleRate);
    if (input.windowSamples != appWindow) {
      issues.add('窗长不一致：模型 ${input.windowSamples} 点，App $appWindow 点');
    }
    if (input.normalize != spec.normalize.mode) {
      issues.add('归一化不一致：模型 ${input.normalize}，App ${spec.normalize.mode}');
    }
    final missing = spec.classes.where((c) => !labels.contains(c)).toList();
    if (missing.isNotEmpty) {
      issues.add('模型缺少类别：${missing.join('、')}');
    }
    return issues;
  }
}
