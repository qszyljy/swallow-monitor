import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'app_event.dart';
import 'recorder_service.dart';
import 'wav_reader.dart';
import 'wav_writer.dart';

class ClipExportResult {
  const ClipExportResult({
    required this.zipFile,
    required this.directory,
    required this.clips,
    required this.skipped,
  });

  final File zipFile;
  final Directory directory;
  final int clips;

  /// 没有事件记录、被跳过的录音条数
  final int skipped;
}

/// 把「录音 + 事件标注」切成一个个事件片段，打包成 zip。
///
/// 导出结构（训练端直接能用）：
///   clips/p03_cough_20261125_143000_ev01.wav
///   manifest.csv     file,subject,label,source,start_sec,end_sec,kind
///
/// 为什么切片段而不是导滑动窗：一个事件切窗会产出 4~8 个窗，
/// 240 条录音会膨胀到 1500+ 个文件，标注和传输都会失控。
/// 片段是「一个事件一个文件」，训练端再做滑窗增广。
class ClipExporter {
  /// 事件前后各留一点余量，保证 1 s 窗放得下。
  static const double padBefore = 0.3;
  static const double padAfter = 0.3;
  static const double minClipSeconds = 1.2;

  static Future<ClipExportResult> exportAll() async {
    final recordings = await RecorderService.listRecordings();
    final base = await getApplicationDocumentsDirectory();
    final stamp = _stamp(DateTime.now());
    final dir = Directory('${base.path}/exports/clips_$stamp');
    final clipsDir = Directory('${dir.path}/clips');
    await clipsDir.create(recursive: true);

    final manifest =
        StringBuffer('file,subject,label,source,start_sec,end_sec,kind\n');
    var count = 0;
    var skipped = 0;

    for (final file in recordings) {
      final events = await EventStore.load(file.path);
      if (events.isEmpty) {
        skipped++;
        continue;
      }

      final WavData wav;
      try {
        wav = await readWav(file.path);
      } catch (_) {
        skipped++;
        continue;
      }

      final fileName = file.path.split('/').last;
      final parsed = _parseName(fileName);
      final total = wav.seconds;

      var index = 0;
      for (final event in events) {
        index++;
        var start = event.startSec - padBefore;
        var end = event.endSec + padAfter;

        if (end - start < minClipSeconds) {
          final extra = (minClipSeconds - (end - start)) / 2;
          start -= extra;
          end += extra;
        }
        start = start.clamp(0.0, total);
        end = end.clamp(0.0, total);
        if (end <= start) continue;

        final startFrame = (start * wav.sampleRate).floor();
        final endFrame = (end * wav.sampleRate).ceil().clamp(0, wav.frameCount);
        if (endFrame - startFrame < 16) continue;

        final byteStart = startFrame * wav.bytesPerSample;
        final byteEnd = endFrame * wav.bytesPerSample;
        if (byteEnd > wav.pcm.lengthInBytes) continue;

        final label = _labelFor(event, parsed.label);
        final clipName =
            '${_stripExt(fileName)}_ev${index.toString().padLeft(2, '0')}.wav';
        final clipFile = File('${clipsDir.path}/$clipName');

        final writer = WavWriter(
          file: clipFile,
          sampleRate: wav.sampleRate,
          channels: wav.channels,
        );
        await writer.open();
        await writer.add(
          Uint8List.sublistView(wav.pcm, byteStart, byteEnd),
        );
        await writer.close();

        manifest.writeln(
          'clips/$clipName,${parsed.subject},$label,$fileName,'
          '${start.toStringAsFixed(3)},${end.toStringAsFixed(3)},clip',
        );
        count++;
      }
    }

    await File('${dir.path}/manifest.csv').writeAsString(manifest.toString());

    // 打包，方便一次分享走
    final archive = Archive();
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(dir.path.length + 1);
      final data = await entity.readAsBytes();
      archive.addFile(ArchiveFile(relative, data.length, data));
    }
    final zipBytes = ZipEncoder().encode(archive) ?? const <int>[];
    final zipFile = File('${dir.path}/clips_$stamp.zip');
    await zipFile.writeAsBytes(zipBytes, flush: true);

    return ClipExportResult(
      zipFile: zipFile,
      directory: dir,
      clips: count,
      skipped: skipped,
    );
  }

  static String _labelFor(AppEvent event, String fallback) {
    final human = event.humanLabel;
    if (human != null && human.isNotEmpty) return human;
    if (event.isPending) return fallback;
    return event.predictedLabel;
  }

  static String _stripExt(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return path.substring(0, path.length - 4);
    return path;
  }

  /// 从 `p03_cough_20261125_143000.wav` 取被试和类别。
  static ({String subject, String label}) _parseName(String fileName) {
    final name = _stripExt(fileName);
    final parts = name.split('_');
    if (parts.length >= 2 &&
        RegExp(r'^[pP]\d{1,3}$').hasMatch(parts.first)) {
      return (subject: parts.first.toLowerCase(), label: parts[1].toLowerCase());
    }
    return (subject: 'p00', label: 'swallow');
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
