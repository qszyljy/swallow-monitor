import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'contracts/sample_source.dart';
import 'impls/mic_source.dart';
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

/// 界面用的采集控制器：把 [MicSource] 包成可监听的状态。
///
/// 音频解码、波形分箱、文件落盘都在 MicSource 里；这里只管
/// 「开始/停止、文件名、峰值、时长、设置」这些界面关心的事。
class RecorderService extends ChangeNotifier {
  RecorderService() {
    _source = MicSource(specProvider: () => PipelineSpec.current);
  }

  late final MicSource _source;
  StreamSubscription<SampleFrame>? _frameSub;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();

  /// 波形显示用：每 10 ms 一个峰值点，保留 30 s。
  static int get sampleRate => PipelineSpec.current.audio.sampleRate;
  static int get channels => PipelineSpec.current.audio.channels;

  int get _binSamples => (PipelineSpec.current.audio.sampleRate / 100).round();
  static const int _maxPoints = 3000; // 30 s，供拖动回看

  final List<double> peaks = <double>[];
  int _binFill = 0;
  double _binPeak = 0;
  double _sessionPeak = 0;

  bool recording = false;
  String? error;
  String? lastFile;
  EventLabel label = EventLabel.swallow;
  double elapsedSeconds = 0;

  static const String defaultSubject = 'p00';
  String subject = defaultSubject;

  /// 检测器订阅这个流；录音停止时流自然没有数据。
  Stream<SampleFrame> get frames => _source.frames;

  double get recordedSeconds => _source.recordedSeconds;

  double get peakDb {
    if (_sessionPeak <= 0.0001) return -80;
    return 20 * math.log(_sessionPeak) / math.ln10;
  }

  void setLabel(EventLabel value) {
    if (label == value) return;
    label = value;
    notifyListeners();
  }

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

  Future<String> _nextPath(EventLabel label) async {
    final dir = await getApplicationDocumentsDirectory();
    String two(int v) => v.toString().padLeft(2, '0');
    final t = DateTime.now();
    final stamp = '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final base = '${dir.path}/records/${subject}_${label.slug}_$stamp';
    var path = '$base.wav';
    var n = 2;
    while (await File(path).exists()) {
      path = '${base}_$n.wav';
      n++;
    }
    return path;
  }

  /// [saveAudio] 为 false 时不落盘——识别/盲测模式用，避免现场演示污染数据集。
  Future<void> start({EventLabel? event, bool saveAudio = true}) async {
    if (recording) return;
    error = null;
    label = event ?? label;
    peaks.clear();
    _binFill = 0;
    _binPeak = 0;
    _sessionPeak = 0;
    elapsedSeconds = 0;

    final granted = await _source.ensurePermission();
    if (!granted) {
      error = '没有录音权限，去系统设置里允许麦克风';
      notifyListeners();
      return;
    }

    try {
      final String? path = saveAudio ? await _nextPath(label) : null;
      await _source.start(wavPath: path);
      lastFile = path;
      _frameSub = _source.frames.listen(_onFrame);
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
      await _frameSub?.cancel();
      _frameSub = null;
      notifyListeners();
    }
  }

  void _onFrame(SampleFrame frame) {
    final data = ByteData.sublistView(frame.samples);
    final samples = frame.samples.lengthInBytes ~/ 2;
    for (var i = 0; i < samples; i++) {
      final a = (data.getInt16(i * 2, Endian.little) / 32768.0).abs();
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
    await _frameSub?.cancel();
    _frameSub = null;
    await _source.stop();
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
    _frameSub?.cancel();
    unawaited(_source.dispose());
    super.dispose();
  }
}
