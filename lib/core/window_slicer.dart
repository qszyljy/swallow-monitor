import 'dart:typed_data';

import 'wav_reader.dart';

/// 取以 [endSec] 结尾、长度 [windowSamples] 的一段窗，前面不够就补零。
///
/// 事件结束时刻是检测器给的，窗从这里往回取，正好覆盖住事件主体。
Float32List sliceWindowEndingAt(
  WavData wav,
  double endSec,
  int windowSamples,
) {
  final out = Float32List(windowSamples);
  final endFrame = (endSec * wav.sampleRate).round().clamp(0, wav.frameCount);
  final startFrame = endFrame - windowSamples;
  final data = ByteData.sublistView(wav.pcm);
  final bps = wav.bytesPerSample;

  for (var i = 0; i < windowSamples; i++) {
    final frame = startFrame + i;
    if (frame < 0 || frame >= wav.frameCount) continue;
    final offset = frame * bps;
    if (offset + 2 > wav.pcm.lengthInBytes) continue;
    out[i] = data.getInt16(offset, Endian.little) / 32768.0;
  }
  return out;
}

/// 以 [centerSec] 为中心取窗，和训练片段「事件居中」的约定一致。
Float32List sliceWindowCenteredAt(
  WavData wav,
  double centerSec,
  int windowSamples,
) {
  final half = windowSamples / 2 / wav.sampleRate;
  return sliceWindowEndingAt(wav, centerSec + half, windowSamples);
}
