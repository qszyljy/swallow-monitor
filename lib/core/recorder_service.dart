import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'wav_writer.dart';
import 'spec.dart';

/// 采集类别。文件名前缀用它，攒出来的数据集直接按类别分好。
enum EventLabel {
  swallow('swallow', '吞咽'),
  cough('cough', '咳嗽'),
  interfere('interfere', '干扰'),
  rest('rest', '静息');

  const EventLabel(this.slug, this.note);
  final String slug;
  final String note;
}

class RecorderService extends ChangeNotifier {
  /// 采样率与通道数来自唯一参数源（assets/spec.default.json），
  /// 代码里不再写字面量——要改只改那个 JSON。
  static int get sampleRate => PipelineSpec.current.audio.sampleRate;
  static int get channels => PipelineSpec.current.audio.channels;

  /// 波形显示用：每 10 ms 一个峰值点，窗口约 10 s。
  int get _binSamples => (PipelineSpec.current.audio.sampleRate / 100).round();
  static const int _maxPoints = 1000;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  WavWriter? _writer;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();

  final List<double> peaks = <double>[];
  int _binFill = 0;
  double _binPeak = 0;
  double _sessionPeak = 0;

  bool recording = false;
  String? error;
  String? lastFile;
  EventLabel label = EventLabel.swallow;
  double elapsedSeconds = 0;

  /// 被试编号，写进文件名（p03_swallow_20261125_103000.wav）。
  /// LOSO 按被试划分，没有它就做不了交叉验证。
  static const String defaultSubject = 'p00';
  String subject = defaultSubject;

  bool setSubject(String value) {
    final cleaned = value.trim().replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return false;
    subject = cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
    notifyListeners();
    unawaited(saveSettings());
    return true;
  }

  Future<File> _settingsFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/settings.json');
  }

  /// 启动时恢复上次用的编号——8 个人轮流录，每次重输必然录错人。
  Future<void> loadSettings() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['subject'] is String) {
        final saved = data['subject'] as String;
        if (saved.isNotEmpty) {
          subject = saved;
          notifyListeners();
        }
      }
    } catch (_) {
      // 配置读坏了不该挡住录音
    }
  }

  Future<void> saveSettings() async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode({'subject': subject}));
    } catch (_) {
      // 忽略写配置失败
    }
  }

  /// 已写入文件的音频时长（来自实际字节数，不是秒表）。
  double get recordedSeconds => _writer?.seconds ?? 0;

  /// 会话最大峰值，转 dBFS 显示，用来判断有没有削顶。
  double get peakDb {
    if (_sessionPeak <= 0.0001) return -80;
    return 20 * math.log(_sessionPeak) / math.ln10;
  }

  Future<bool> ensurePermission() => _recorder.hasPermission();

  void setLabel(EventLabel value) {
    if (label == value) return;
    label = value;
    notifyListeners();
  }

  Future<String> _nextPath(EventLabel label) async {
    final dir = await getApplicationDocumentsDirectory();
    String two(int v) => v.toString().padLeft(2, '0');
    final t = DateTime.now();
    final stamp = '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final base = '${dir.path}/records/${subject}_${label.slug}_$stamp';
    // 同一秒内停止再开始会撞名，加后缀；训练端的文件名正则允许这个后缀
    var path = '$base.wav';
    var n = 2;
    while (await File(path).exists()) {
      path = '${base}_$n.wav';
      n++;
    }
    return path;
  }

  Future<void> start({EventLabel? event}) async {
    if (recording) return;
    error = null;
    label = event ?? label;
    peaks.clear();
    _binFill = 0;
    _binPeak = 0;
    _sessionPeak = 0;
    elapsedSeconds = 0;

    final granted = await _recorder.hasPermission();
    if (!granted) {
      error = '没有录音权限，去系统设置里允许麦克风';
      notifyListeners();
      return;
    }

    try {
      final path = await _nextPath(label);
      final writer = WavWriter(
        file: File(path),
        sampleRate: sampleRate,
        channels: channels,
      );
      await writer.open();

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: channels,
          // 任务书要求：关掉系统自动增益、降噪、回声消除，
          // 否则咳嗽的冲击被压平、吞咽低频被削掉。
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      _writer = writer;
      lastFile = path;
      _sub = stream.listen(
        _onChunk,
        onError: (Object e) {
          error = '录音中断：$e';
          unawaited(stop());
        },
      );
      recording = true;
      _clock
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
        elapsedSeconds = _clock.elapsedMilliseconds / 1000.0;
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      error = '启动录音失败：$e';
      recording = false;
      await _writer?.close();
      _writer = null;
      notifyListeners();
    }
  }

  void _onChunk(Uint8List chunk) {
    _writer?.add(chunk);

    final data = ByteData.sublistView(chunk);
    final samples = chunk.lengthInBytes ~/ 2;
    for (var i = 0; i < samples; i++) {
      final v = data.getInt16(i * 2, Endian.little) / 32768.0;
      final a = v.abs();
      if (a > _binPeak) _binPeak = a;
      _binFill++;
      if (_binFill >= _binSamples) {
        peaks.add(_binPeak);
        if (_binPeak > _sessionPeak) _sessionPeak = _binPeak;
        if (peaks.length > _maxPoints) peaks.removeAt(0);
        _binFill = 0;
        _binPeak = 0;
      }
    }
  }

  Future<void> stop() async {
    if (!recording) return;
    recording = false;
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 忽略停止失败，文件已落盘的部分仍然有效
    }
    await _writer?.close();
    _writer = null;
    notifyListeners();
  }

  static Future<Directory> recordsDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/records');
  }

  static Future<List<File>> listRecordings() async {
    final dir = await recordsDir();
    if (!await dir.exists()) return const <File>[];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.wav'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
