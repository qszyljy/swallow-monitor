/// 分类器接口。这里只放接口和一个占位实现，
/// 等模型训好、导出 tflite 后，新写一个实现替换掉 _classifier 即可，
/// 界面和采集逻辑都不用动。
///
/// 接入步骤（对应评分项 6）：
///   1. pubspec 加 tflite_flutter
///   2. 把 model.tflite + labels.txt 放进 assets/
///   3. 朗读 wav → 22.05 kHz 单声道 → 3 s 定长 → 128 梅尔灰度图 → 128×128
///   4. 归一化到 0~1，输入形状 1×128×128×3，输出 3 类分数
///   5. 真机打点：从采样到出结果的端到端时延，目标 ≤ 20 ms，模型 ≤ 5 MB
library;

class ClassScore {
  const ClassScore(this.label, this.score);

  final String label;

  /// 0~1。三类之和约为 1。
  final double score;
}

abstract class Classifier {
  String get name;

  /// 是否已经真正接入模型。占位实现返回 false，界面据此显示提示。
  bool get ready;

  Future<List<ClassScore>> classify(String wavPath);
}

/// 占位分类器：模型还没接入，分数恒为 0。
/// 界面上必须标出「未接入」，别让演示时看起来像在瞎猜。
class PlaceholderClassifier implements Classifier {
  const PlaceholderClassifier();

  @override
  String get name => '占位分类器（TFLite 未接入）';

  @override
  bool get ready => false;

  @override
  Future<List<ClassScore>> classify(String wavPath) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return const <ClassScore>[
      ClassScore('吞咽', 0),
      ClassScore('咳嗽', 0),
      ClassScore('干扰', 0),
    ];
  }
}
