import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive spider/radar chart with draggable axis handles.
/// values are expected in 0..maxValue (default 0..100).
class SpiderChart extends StatefulWidget {
  final List<String> labels;
  final List<double> values;
  final ValueChanged<List<double>> onChanged;
  final int steps; // ring count
  final double maxValue;
  final bool readOnly;
  // Optional override colors; defaults to theme primary if null.
  final Color? fillColor;
  final Color? strokeColor;
  // Called when user taps a vertex handle without dragging.
  final void Function(int idx)? onVertexTap;

  const SpiderChart({
    super.key,
    required this.labels,
    required this.values,
    required this.onChanged,
    this.steps = 4,
    this.maxValue = 100,
    this.readOnly = false,
    this.fillColor,
    this.strokeColor,
    this.onVertexTap,
  });

  @override
  State<SpiderChart> createState() => _SpiderChartState();
}

class _SpiderChartState extends State<SpiderChart> with SingleTickerProviderStateMixin {
  late List<double> _display;
  int? _dragIndex;
  Offset? _panDownPos;  // track for tap vs drag disambiguation

  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _display = List<double>.from(widget.values);
  }

  @override
  void didUpdateWidget(covariant SpiderChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragIndex != null) return;

    if (!_listEq(oldWidget.values, widget.values)) {
      final from = List<double>.from(_display);
      final to = List<double>.from(widget.values);
      _ctl
        ..stop()
        ..reset();

      void tick() {
        final tt = _t.value;
        setState(() {
          _display = List<double>.generate(to.length, (i) => _lerp(from[i], to[i], tt));
        });
      }

      _ctl.removeListener(tick);
      _ctl.addListener(tick);
      _ctl.forward();
    }
  }

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final size = math.min(c.maxWidth, c.maxHeight);

        return Listener(
          // Helps capture intent early so the page doesn't steal the drag as often.
          onPointerDown: widget.readOnly ? null : (_) {},
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: widget.readOnly ? null : (d) {
              _panDownPos = d.localPosition;
              _startDrag(d.localPosition, size);
            },
            onPanStart: widget.readOnly ? null : (d) => _startDrag(d.localPosition, size),
            onPanUpdate: widget.readOnly ? null : (d) {
              // Track if this is still a tap (small displacement)
              if (_panDownPos != null &&
                  (d.localPosition - _panDownPos!).distance > 12) {
                _panDownPos = null; // converted to a drag, not a tap
              }
              _updateDrag(d.localPosition, size);
            },
            onPanEnd: widget.readOnly ? null : (d) {
              // If panDownPos was not cleared (displacement stayed small), treat as tap
              if (_panDownPos != null && widget.onVertexTap != null) {
                final idx = _hitTestHandle(_panDownPos!, size);
                if (idx != null) widget.onVertexTap!(idx);
              }
              _panDownPos = null;
              _endDrag();
            },
            onPanCancel: widget.readOnly ? null : () {
              _panDownPos = null;
              _endDrag();
            },
            child: CustomPaint(
              size: Size.square(size),
              painter: _SpiderPainter(
                labels: widget.labels,
                values: _display,
                steps: widget.steps,
                maxValue: widget.maxValue,
                theme: Theme.of(context),
                dragIndex: widget.readOnly ? null : _dragIndex,
                fillColor: widget.fillColor,
                strokeColor: widget.strokeColor,
              ),
            ),
          ),
        );
      },
    );
  }

  void _startDrag(Offset p, double size) {
    final idx = _hitTestHandle(p, size) ?? _nearestAxis(p, size);
    if (idx != null) {
      setState(() => _dragIndex = idx);
      _applyPoint(p, size, idx);
    }
  }

  void _updateDrag(Offset p, double size) {
    final idx = _dragIndex;
    if (idx == null) return;
    _applyPoint(p, size, idx);
  }

  void _endDrag() {
    if (_dragIndex != null) {
      setState(() => _dragIndex = null);
    }
  }

  void _applyPoint(Offset p, double size, int idx) {
    final center = Offset(size / 2, size / 2);
    final v = p - center;

    final n = widget.labels.length;
    final angle = _axisAngle(idx, n);

    final ax = Offset(math.cos(angle), math.sin(angle));
    final proj = (v.dx * ax.dx + v.dy * ax.dy);

    final radius = size * 0.38;
    final clamped = proj.clamp(0.0, radius);
    final val = (clamped / radius) * widget.maxValue;

    final next = List<double>.from(_display);
    next[idx] = val.clamp(0.0, widget.maxValue);
    setState(() => _display = next);
    widget.onChanged(next);
  }

  int? _hitTestHandle(Offset p, double size) {
    final center = Offset(size / 2, size / 2);
    final radius = size * 0.38;
    final n = widget.labels.length;

    // Larger so the "top point" is easier to grab.
    const handleR = 18.0;

    for (var i = 0; i < n; i++) {
      final angle = _axisAngle(i, n);
      final r = (_display[i].clamp(0.0, widget.maxValue) / widget.maxValue) * radius;
      final hp = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if ((p - hp).distance <= handleR) return i;
    }
    return null;
  }

  int? _nearestAxis(Offset p, double size) {
    final center = Offset(size / 2, size / 2);
    final v = p - center;
    if (v.distance < 12) return null;

    final theta = math.atan2(v.dy, v.dx);
    final n = widget.labels.length;

    double best = double.infinity;
    int? bestIdx;

    for (var i = 0; i < n; i++) {
      final a = _axisAngle(i, n);
      final d = _angleDiff(theta, a);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  double _angleDiff(double a, double b) {
    var d = (a - b).abs();
    while (d > math.pi) d = (2 * math.pi) - d;
    return d;
  }

  double _axisAngle(int i, int n) {
    final step = 2 * math.pi / n;
    return -math.pi / 2 + step * i;
  }
}

class _SpiderPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final int steps;
  final double maxValue;
  final ThemeData theme;
  final int? dragIndex;
  final Color? fillColor;
  final Color? strokeColor;

  _SpiderPainter({
    required this.labels,
    required this.values,
    required this.steps,
    required this.maxValue,
    required this.theme,
    required this.dragIndex,
    this.fillColor,
    this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n < 3) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;

    final gridPaint = Paint()
      ..color = theme.dividerColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // rings
    for (var s = 1; s <= steps; s++) {
      final r = radius * (s / steps);
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = _axisAngle(i, n);
        final p = center + Offset(math.cos(a), math.sin(a)) * r;
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // axes
    for (var i = 0; i < n; i++) {
      final a = _axisAngle(i, n);
      final p = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawLine(center, p, gridPaint);
    }

    // labels at axis tips
    for (var i = 0; i < n; i++) {
      final a = _axisAngle(i, n);
      final tip = center + Offset(math.cos(a), math.sin(a)) * (radius * 1.12);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.85),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);

      final draw = tip - Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, draw);
    }

    // polygon
    final poly = Path();
    for (var i = 0; i < n; i++) {
      final a = _axisAngle(i, n);
      final v = values[i].clamp(0.0, maxValue);
      final r = radius * (v / maxValue);
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) poly.moveTo(p.dx, p.dy);
      else poly.lineTo(p.dx, p.dy);
    }
    poly.close();

    final fill = Paint()
      ..color = (fillColor ?? theme.colorScheme.primary.withOpacity(0.18))
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = (strokeColor ?? theme.colorScheme.primary.withOpacity(0.85))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(poly, fill);
    canvas.drawPath(poly, stroke);

    // handles
    for (var i = 0; i < n; i++) {
      final a = _axisAngle(i, n);
      final v = values[i].clamp(0.0, maxValue);
      final r = radius * (v / maxValue);
      final p = center + Offset(math.cos(a), math.sin(a)) * r;

      final isActive = (dragIndex == i);
      final handleFill = Paint()
        ..color = isActive ? theme.colorScheme.primary : theme.colorScheme.primary.withOpacity(0.9)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p, isActive ? 7.5 : 6.5, handleFill);
      canvas.drawCircle(
        p,
        isActive ? 11 : 10,
        Paint()
          ..color = theme.scaffoldBackgroundColor.withOpacity(0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  double _axisAngle(int i, int n) {
    final step = 2 * math.pi / n;
    return -math.pi / 2 + step * i;
  }

  @override
  bool shouldRepaint(covariant _SpiderPainter old) {
    if (old.steps != steps) return true;
    if (old.dragIndex != dragIndex) return true;
    if (old.labels.length != labels.length) return true;
    if (old.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if ((old.values[i] - values[i]).abs() > 1e-6) return true;
    }
    return false;
  }
}
