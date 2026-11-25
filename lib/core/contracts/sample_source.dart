import 'dart:typed_data';

/// 一帧原始数据。麦克风和将来的 BLE 加速度都吐这个结构，下游只认它。
class SampleFrame {
  const SampleFrame({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.deviceTimestampMicros,
  });

  /// PCM16 小端。麦克风是音频；BLE 加速度是同一套打包方式，通道含义由数据源决定。
  final Uint8List samples;
  final int sampleRate;
  final int channels;

  /// 数据产生的那一刻（设备侧），**不是**到达手机的时刻。
  /// 双路对齐只信这个字段：BLE 到达抖动 20~30 ms，用到达时刻对齐必然超过 10 ms 指标。
  final int deviceTimestampMicros;

  int get totalInt16 => samples.lengthInBytes ~/ 2;

  int get frameCount => channels == 0 ? 0 : totalInt16 ~/ channels;

  int get durationMicros =>
      sampleRate == 0 ? 0 : frameCount * 1000000 ~/ sampleRate;

  int get endTimestampMicros => deviceTimestampMicros + durationMicros;
}

/// 一路数据源。界面、波形、检测器都只依赖这个接口，
/// 换成 BLE 时只需要新写一个实现，其余代码不动。
abstract class SampleSource {
  String get name;

  int get sampleRate;

  int get channels;

  Stream<SampleFrame> get frames;

  bool get isRunning;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
