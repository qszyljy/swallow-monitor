import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../contracts/sample_source.dart';
import '../spec.dart';
import '../wav_writer.dart';

/// 麦克风数据源：48 kHz PCM16 → SampleFrame，并可选落成 WAV。
///
/// 之所以单独一层，是为了让 BLE 加速度进来时只新增一个实现，
/// 波形、检测器、界面都不用动。
class MicSource implements SampleSource {
  MicSource({required this.specProvider});

  final PipelineSpec Function() specProvider;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<SampleFrame> _frames =
      StreamController<SampleFrame>.broadcast();

  StreamSubscription<Uint8List>? _sub;
  WavWriter? _writer;
  bool _running = false;
  int _totalFrames = 0;

  PipelineSpec get _spec => specProvider();

  @override
  String get name => '麦克风';

  @override
  int get sampleRate => _spec.audio.sampleRate;

  @override
  int get channels => _spec.audio.channels;

  @override
  Stream<SampleFrame> get frames => _frames.stream;

  @override
  bool get isRunning => _running;

  /// 已写入文件的时长（来自实际字节数）。
  double get recordedSeconds => _writer?.seconds ?? 0;

  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<void> start({String? wavPath}) async {
    if (_running) return;
    final spec = _spec;

    if (wavPath != null) {
      final writer = WavWriter(
        file: File(wavPath),
        sampleRate: spec.audio.sampleRate,
        channels: spec.audio.channels,
      );
      await writer.open();
      _writer = writer;
    }

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: spec.audio.sampleRate,
        numChannels: spec.audio.channels,
        // 任务书要求：关掉系统处理，否则咳嗽冲击被压平、吞咽低频被削掉
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _totalFrames = 0;
    _running = true;
    _sub = stream.listen(
      _onChunk,
      onError: (Object _) => _running = false,
    );
  }

  void _onChunk(Uint8List chunk) {
    final spec = _spec;
    _writer?.add(chunk);

    final frames = spec.audio.channels == 0
        ? 0
        : chunk.lengthInBytes ~/ 2 ~/ spec.audio.channels;
    final timestamp = _totalFrames * 1000000 ~/ spec.audio.sampleRate;
    _totalFrames += frames;

    if (_frames.isClosed) return;
    _frames.add(
      SampleFrame(
        samples: chunk,
        sampleRate: spec.audio.sampleRate,
        channels: spec.audio.channels,
        deviceTimestampMicros: timestamp,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止失败不影响已落盘的数据
    }
    await _writer?.close();
    _writer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _frames.close();
  }
}
