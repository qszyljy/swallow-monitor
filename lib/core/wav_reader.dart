import 'dart:io';
import 'dart:typed_data';

/// 读 WAV（只认 PCM16，够我们自己录的文件用）。
class WavData {
  WavData({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.pcm,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// 裸 PCM 数据（不含头）
  final Uint8List pcm;

  int get bytesPerSample => channels * (bitsPerSample ~/ 8);

  int get frameCount => bytesPerSample == 0 ? 0 : pcm.lengthInBytes ~/ bytesPerSample;

  double get seconds => sampleRate == 0 ? 0 : frameCount / sampleRate;
}

Future<WavData> readWav(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length < 44) {
    throw const FormatException('文件太小，不是 wav');
  }
  final data = ByteData.sublistView(bytes);
  String tag(int offset) => String.fromCharCodes(bytes.sublist(offset, offset + 4));

  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('不是 RIFF/WAVE 文件');
  }

  int? sampleRate;
  int? channels;
  int? bits;
  int? dataOffset;
  int? dataLength;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = size;
      break;
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  final rate = sampleRate;
  final chan = channels;
  final bitsValue = bits;
  final start = dataOffset;
  final length = dataLength;
  if (rate == null ||
      chan == null ||
      bitsValue == null ||
      start == null ||
      length == null) {
    throw const FormatException('wav 头不完整');
  }

  final end = (start + length).clamp(0, bytes.length);
  return WavData(
    sampleRate: rate,
    channels: chan,
    bitsPerSample: bitsValue,
    pcm: Uint8List.sublistView(bytes, start, end),
  );
}
