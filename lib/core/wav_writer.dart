import 'dart:io';
import 'dart:typed_data';

/// 边录边写 WAV（PCM16 单声道）。
///
/// 录音开始先占位 44 字节头，结束时回填 RIFF/data 长度，
/// 这样即使 App 中途被杀，文件也只是长度字段不对，音频数据没丢。
class WavWriter {
  WavWriter({
    required this.file,
    required this.sampleRate,
    required this.channels,
  });

  final File file;
  final int sampleRate;
  final int channels;

  RandomAccessFile? _raf;
  int _dataBytes = 0;
  bool _closed = false;
  Future<void> _queue = Future<void>.value();

  int get dataBytes => _dataBytes;

  double get seconds =>
      sampleRate == 0 ? 0 : _dataBytes / (sampleRate * channels * 2);

  Future<void> open() async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    _raf = raf;
    await raf.writeFrom(_header(0));
  }

  /// 写入一段 PCM。内部串行化，避免多个 chunk 并发写乱序。
  Future<void> add(Uint8List pcm) {
    final next = _queue.then((_) => _write(pcm));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(Uint8List pcm) async {
    final raf = _raf;
    if (raf == null || _closed) return;
    await raf.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  Future<void> close() async {
    await _queue;
    final raf = _raf;
    if (raf == null || _closed) return;
    _closed = true;
    await raf.setPosition(0);
    await raf.writeFrom(_header(_dataBytes));
    await raf.flush();
    await raf.close();
    _raf = null;
  }

  Uint8List _header(int dataLen) {
    final bytes = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    final byteRate = sampleRate * channels * 2;
    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLen, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // fmt chunk 大小
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // 位深
    ascii(36, 'data');
    bytes.setUint32(40, dataLen, Endian.little);
    return bytes.buffer.asUint8List();
  }
}
