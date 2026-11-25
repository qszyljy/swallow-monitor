import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 盲测记录的一条：现场判对判错，报告里要用。
class BenchmarkEntry {
  const BenchmarkEntry({
    required this.time,
    required this.label,
    required this.score,
    required this.latencyMs,
    required this.correct,
  });

  final DateTime time;
  final String label;
  final double score;
  final int latencyMs;
  final bool correct;

  String toCsvRow() => '${time.toIso8601String()},$label,'
      '${score.toStringAsFixed(3)},$latencyMs,${correct ? 1 : 0}';
}

class BenchmarkLog {
  /// 写到 `benchmark/bench_<时间戳>.csv`，返回文件，供分享。
  static Future<File> write(List<BenchmarkEntry> entries) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/benchmark');
    await dir.create(recursive: true);

    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    final file = File('${dir.path}/bench_$stamp.csv');
    final buffer = StringBuffer('time,label,score,latency_ms,correct\n');
    for (final entry in entries) {
      buffer.writeln(entry.toCsvRow());
    }
    await file.writeAsString(buffer.toString());
    return file;
  }
}
