import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 实时波形：把每个 10 ms 窗的峰值画成竖线，最新数据在最右。
class WaveformView extends StatelessWidget {
  const WaveformView({super.key, required this.peaks, this.color});

  final List<double> peaks;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _WaveformPainter(
        peaks: peaks,
        color: color ?? scheme.primary,
        grid: scheme.outlineVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.color,
    required this.grid,
  });

  final List<double> peaks;
  final Color color;
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
      old.color != color ||
      old.grid != grid;
}
