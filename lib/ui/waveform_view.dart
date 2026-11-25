import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 事件标记：相对「此刻」的结束时间和持续时长（秒）。
/// 这样波形每帧滚动时标记会跟着走，不用自己算坐标。
class EventMarker {
  const EventMarker({
    required this.endAgoSeconds,
    required this.durationSeconds,
    this.color,
  });

  final double endAgoSeconds;
  final double durationSeconds;
  final Color? color;
}

/// 实时波形：把每个 10 ms 窗的峰值画成竖线，最新数据在最右。
/// [markers] 用色块标出事件区间。
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.markers = const <EventMarker>[],
    this.secondsPerPoint = 0.01,
    this.color,
  });

  final List<double> peaks;
  final List<EventMarker> markers;
  final double secondsPerPoint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _WaveformPainter(
        peaks: peaks,
        markers: markers,
        secondsPerPoint: secondsPerPoint,
        color: color ?? scheme.primary,
        markerColor: scheme.tertiary,
        grid: scheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.markers,
    required this.secondsPerPoint,
    required this.color,
    required this.markerColor,
    required this.grid,
  });

  final List<double> peaks;
  final List<EventMarker> markers;
  final double secondsPerPoint;
  final Color color;
  final Color markerColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = grid
        ..strokeWidth = 1.5,
    );

    if (peaks.isEmpty) return;

    final step = size.width / peaks.length;

    // 先画事件色块，压在波形下面
    if (markers.isNotEmpty && secondsPerPoint > 0) {
      final bandPaint = Paint()..color = markerColor.withAlpha(56);
      final edgePaint = Paint()
        ..color = markerColor.withAlpha(170)
        ..strokeWidth = 1.5;
      for (final marker in markers) {
        final xEnd =
            size.width - (marker.endAgoSeconds / secondsPerPoint) * step;
        final xStart = xEnd - (marker.durationSeconds / secondsPerPoint) * step;
        final left = math.max(0.0, xStart);
        final right = math.min(size.width, xEnd);
        if (right <= left) continue;
        canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), bandPaint);
        canvas.drawLine(Offset(left, 0), Offset(left, size.height), edgePaint);
        canvas.drawLine(Offset(right, 0), Offset(right, size.height), edgePaint);
      }
    }

    final barPaint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.0, step * 0.9)
      ..strokeCap = StrokeCap.round;

    final halfMax = size.height / 2 - 4;
    for (var i = 0; i < peaks.length; i++) {
      final v = peaks[i].clamp(0.0, 1.0);
      final h = v * halfMax;
      final x = (i + 0.5) * step;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks.length != peaks.length ||
      old.markers.length != markers.length ||
      old.color != color ||
      old.grid != grid;
}
