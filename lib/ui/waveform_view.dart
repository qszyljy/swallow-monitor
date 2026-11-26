import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 事件标记：相对「此刻」的结束时间和持续时长（秒）。
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

/// 可拖动的时间轴波形。
///
/// - 右端固定为「此刻」，新数据从右边进，旧数据往左移
/// - 横向拖动可以回看更早的数据，右下角出现「回到最新」
/// - [markers] 按同一时间轴画成色块，事件落在它真实发生的位置
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.markers = const <EventMarker>[],
    this.secondsPerPoint = 0.01,
    this.spanSeconds = 10,
    this.color,
    this.showFollowButton = true,
  });

  final List<double> peaks;
  final List<EventMarker> markers;
  final double secondsPerPoint;
  final double spanSeconds;
  final Color? color;
  final bool showFollowButton;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  /// 右端距离「此刻」多少秒。0 表示跟随最新。
  double _offsetSeconds = 0;

  double get _totalSeconds => widget.peaks.length * widget.secondsPerPoint;

  double get _maxOffset =>
      math.max(0.0, _totalSeconds - widget.spanSeconds);

  void _onDrag(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    final secondsPerPixel = widget.spanSeconds / width;
    setState(() {
      _offsetSeconds =
          (_offsetSeconds + details.delta.dx * secondsPerPixel)
              .clamp(0.0, _maxOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final following = _offsetSeconds < 0.05;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _onDrag(details, width),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WaveformPainter(
                    peaks: widget.peaks,
                    markers: widget.markers,
                    secondsPerPoint: widget.secondsPerPoint,
                    spanSeconds: widget.spanSeconds,
                    offsetSeconds: _offsetSeconds,
                    color: widget.color ?? scheme.primary,
                    markerColor: scheme.tertiary,
                    grid: scheme.outlineVariant,
                  ),
                ),
              ),
              if (!following)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: scheme.surface,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setState(() => _offsetSeconds = 0),
                    child: Text('回到最新 ${_offsetSeconds.toStringAsFixed(1)}s 前'),
                  ),
                ),
              if (following && widget.peaks.isEmpty)
                Center(
                  child: Text(
                    '等待音频…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.markers,
    required this.secondsPerPoint,
    required this.spanSeconds,
    required this.offsetSeconds,
    required this.color,
    required this.markerColor,
    required this.grid,
  });

  final List<double> peaks;
  final List<EventMarker> markers;
  final double secondsPerPoint;
  final double spanSeconds;
  final double offsetSeconds;
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

    if (peaks.isEmpty || spanSeconds <= 0) return;

    // 时间轴：右端是 offsetSeconds 秒之前，左端更早
    double xFor(double agoSeconds) =>
        size.width * (1 - (agoSeconds - offsetSeconds) / spanSeconds);

    // 事件色块画在波形下面
    if (markers.isNotEmpty) {
      final bandPaint = Paint()..color = markerColor.withAlpha(56);
      final edgePaint = Paint()
        ..color = markerColor.withAlpha(170)
        ..strokeWidth = 1.5;
      for (final marker in markers) {
        final left = xFor(marker.endAgoSeconds + marker.durationSeconds);
        final right = xFor(marker.endAgoSeconds);
        final l = math.max(0.0, left);
        final r = math.min(size.width, right);
        if (r <= l) continue;
        canvas.drawRect(Rect.fromLTRB(l, 0, r, size.height), bandPaint);
        canvas.drawLine(Offset(l, 0), Offset(l, size.height), edgePaint);
        canvas.drawLine(Offset(r, 0), Offset(r, size.height), edgePaint);
      }
    }

    final barPaint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.0, size.width / (spanSeconds / secondsPerPoint) * 0.9)
      ..strokeCap = StrokeCap.round;

    final halfMax = size.height / 2 - 4;
    final count = peaks.length;
    for (var i = 0; i < count; i++) {
      final allAgo = (count - 1 - i) * secondsPerPoint;
      if (allAgo < offsetSeconds || allAgo > offsetSeconds + spanSeconds) {
        continue;
      }
      final x = xFor(allAgo);
      final value = peaks[i].clamp(0.0, 1.0);
      final h = value * halfMax;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks.length != peaks.length ||
      old.markers.length != markers.length ||
      old.offsetSeconds != offsetSeconds ||
      old.color != color ||
      old.grid != grid;
}
