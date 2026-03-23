import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Simple radar-like painter for FrequencyComposition.
/// (Kept here because InputScreen references FrequencyRadar directly.)
class FrequencyRadar extends StatelessWidget {
  final int sense;
  final int maintain;
  final int explore;
  final int enforce;
  final double size;

  const FrequencyRadar({
    super.key,
    required this.sense,
    required this.maintain,
    required this.explore,
    required this.enforce,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RadarPainter(
        values: [
          sense / 100.0,
          maintain / 100.0,
          explore / 100.0,
          enforce / 100.0,
        ],
        labels: const ['Sense', 'Maintain', 'Explore', 'Enforce'],
        textStyle: Theme.of(context).textTheme.bodySmall,
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).dividerColor,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values; // 0..1
  final List<String> labels;
  final TextStyle? textStyle;
  final Color color;
  final Color gridColor;

  _RadarPainter({
    required this.values,
    required this.labels,
    required this.textStyle,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.38;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withOpacity(0.7);

    for (int k = 1; k <= 3; k++) {
      final rr = r * (k / 3.0);
      final path = Path();
      for (int i = 0; i < 4; i++) {
        final a = (-math.pi / 2) + i * (math.pi / 2);
        final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }

    for (int i = 0; i < 4; i++) {
      final a = (-math.pi / 2) + i * (math.pi / 2);
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      canvas.drawLine(c, p, grid);

      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);

      final labelOffset = c + Offset(math.cos(a) * (r + 18), math.sin(a) * (r + 18));
      tp.paint(canvas, labelOffset - Offset(tp.width / 2, tp.height / 2));
    }

    final poly = Path();
    for (int i = 0; i < 4; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final a = (-math.pi / 2) + i * (math.pi / 2);
      final p = c + Offset(math.cos(a) * (r * v), math.sin(a) * (r * v));
      if (i == 0) poly.moveTo(p.dx, p.dy);
      else poly.lineTo(p.dx, p.dy);
    }
    poly.close();

    canvas.drawPath(poly, Paint()..style = PaintingStyle.fill..color = color.withOpacity(0.18));
    canvas.drawPath(poly, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = color.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.values != values || old.color != color || old.gridColor != gridColor;
}

/// Basic single-series line chart (legacy use in some screens).
class SimpleLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> xLabels;
  final double height;

  const SimpleLineChart({
    super.key,
    required this.values,
    required this.xLabels,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(
          values: values,
          gridColor: Theme.of(context).dividerColor,
          lineColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ─── MultiLineChart ───────────────────────────────────────────────────────────
//
// Renders one chart for all selected series with:
//   • Explicit per-series colors (via colorById)
//   • Y-axis labels on the left (0 / 25 / 50 / 75 / 100 or 0.0 / 0.5 / 1.0)
//   • X-axis date labels at start, middle, end
//   • NaN-gap support (lifts the pen at missing data points)
//   • Small data-point dots
//   • Tap/drag crosshair with tooltip (P1.1)
//   • Clickable legend rows (onLegendTap to let parent assign new color)

class MultiLineChart extends StatefulWidget {
  final Map<String, List<double>> seriesById;
  final List<DateTime> dates;
  final Map<String, String> labelsById;
  final Map<String, Color> colorById;
  final double minY;
  final double maxY;
  final List<List<int>?>? bandVectors;

  /// Called when the user taps the colored dot in the legend.
  final void Function(String id)? onLegendTap;

  const MultiLineChart({
    super.key,
    required this.seriesById,
    required this.dates,
    required this.labelsById,
    required this.colorById,
    this.minY = 0,
    this.maxY = 100,
    this.bandVectors,
    this.onLegendTap,
  });

  @override
  State<MultiLineChart> createState() => _MultiLineChartState();
}

class _MultiLineChartState extends State<MultiLineChart> {
  // Crosshair state — null means no crosshair visible.
  int? _hoverIndex;

  // Chart layout constants (must match _MultiLinePainter).
  static const _padLeft   = 44.0;
  static const _padRight  =  8.0;
  static const _padTop    = 10.0;
  static const _chartH    = 300.0;

  int _maxLen() {
    int m = 0;
    for (final s in widget.seriesById.values) {
      if (s.length > m) m = s.length;
    }
    return m;
  }

  /// Convert a raw x pixel position (within the chart SizedBox) → series index.
  int _xToIndex(double localX, double totalWidth) {
    final maxLen = _maxLen();
    if (maxLen < 2) return 0;
    final w = totalWidth - _padLeft - _padRight;
    final frac = ((localX - _padLeft) / w).clamp(0.0, 1.0);
    return (frac * (maxLen - 1)).round();
  }

  void _onTouch(double localX, double totalWidth) {
    final idx = _xToIndex(localX, totalWidth);
    if (idx != _hoverIndex) setState(() => _hoverIndex = idx);
  }

  void _clearTouch() => setState(() => _hoverIndex = null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = widget.seriesById.keys.toList();

    if (ids.isEmpty || widget.dates.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('No data', style: TextStyle(color: AppTheme.textLight))),
      );
    }

    final bool normalized = (widget.maxY - widget.minY).abs() < 1.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Chart canvas with crosshair overlay ──────────────────────────────
        LayoutBuilder(
          builder: (ctx, constraints) {
            final totalWidth = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown:       (d) => _onTouch(d.localPosition.dx, totalWidth),
              onLongPressStart:(d) => _onTouch(d.localPosition.dx, totalWidth),
              onLongPressMoveUpdate: (d) => _onTouch(d.localPosition.dx, totalWidth),
              onLongPressEnd:  (_)  => _clearTouch(),
              onHorizontalDragUpdate: (d) => _onTouch(d.localPosition.dx, totalWidth),
              onHorizontalDragEnd:    (_)  => _clearTouch(),
              child: SizedBox(
                height: _chartH,
                width: totalWidth,
                child: Stack(
                  children: [
                    // Base line chart
                    CustomPaint(
                      size: Size(totalWidth, _chartH),
                      painter: _MultiLinePainter(
                        ids: ids,
                        seriesById: widget.seriesById,
                        dates: widget.dates,
                        minY: widget.minY,
                        maxY: widget.maxY,
                        normalized: normalized,
                        gridColor: theme.dividerColor,
                        axisLabelStyle: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textLight,
                          fontFamily: 'monospace',
                        ),
                        colorById: widget.colorById,
                        bandVectors: widget.bandVectors,
                        bandBaseColor: theme.colorScheme.secondary,
                      ),
                    ),
                    // Crosshair overlay (only when touching)
                    if (_hoverIndex != null)
                      CustomPaint(
                        size: Size(totalWidth, _chartH),
                        painter: _CrosshairPainter(
                          index: _hoverIndex!,
                          maxLen: _maxLen(),
                          padLeft: _padLeft,
                          padRight: _padRight,
                          padTop: _padTop,
                          padBottom: 28.0,
                          lineColor: theme.dividerColor.withOpacity(0.8),
                        ),
                      ),
                    // Tooltip card
                    if (_hoverIndex != null)
                      _TooltipCard(
                        index: _hoverIndex!,
                        maxLen: _maxLen(),
                        totalWidth: totalWidth,
                        chartHeight: _chartH,
                        padLeft: _padLeft,
                        padRight: _padRight,
                        padTop: _padTop,
                        ids: ids,
                        dates: widget.dates,
                        seriesById: widget.seriesById,
                        labelsById: widget.labelsById,
                        colorById: widget.colorById,
                        normalized: normalized,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: ids.map((id) {
            final color = widget.colorById[id] ?? AppTheme.primary;
            final label = widget.labelsById[id] ?? id;
            return GestureDetector(
              onTap: widget.onLegendTap != null ? () => widget.onLegendTap!(id) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 3)],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMed)),
                  if (widget.onLegendTap != null) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.colorize, size: 11, color: AppTheme.textLight),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Crosshair painter ────────────────────────────────────────────────────────

class _CrosshairPainter extends CustomPainter {
  final int index;
  final int maxLen;
  final double padLeft, padRight, padTop, padBottom;
  final Color lineColor;

  const _CrosshairPainter({
    required this.index,
    required this.maxLen,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.padBottom,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (maxLen < 2) return;
    final w = size.width - padLeft - padRight;
    final h = size.height - padTop - padBottom;
    final x = padLeft + w * (index / (maxLen - 1));

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed vertical line
    const dashH = 6.0;
    double y = padTop;
    while (y < padTop + h) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dashH, padTop + h)), paint);
      y += dashH * 1.8;
    }

    // Circle at crosshair base
    canvas.drawCircle(Offset(x, padTop + h), 3, Paint()..color = lineColor..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => old.index != index;
}

// ─── Tooltip card ─────────────────────────────────────────────────────────────

class _TooltipCard extends StatelessWidget {
  final int index;
  final int maxLen;
  final double totalWidth;
  final double chartHeight;
  final double padLeft, padRight, padTop;
  final List<String> ids;
  final List<DateTime> dates;
  final Map<String, List<double>> seriesById;
  final Map<String, String> labelsById;
  final Map<String, Color> colorById;
  final bool normalized;

  const _TooltipCard({
    required this.index,
    required this.maxLen,
    required this.totalWidth,
    required this.chartHeight,
    required this.padLeft,
    required this.padRight,
    required this.padTop,
    required this.ids,
    required this.dates,
    required this.seriesById,
    required this.labelsById,
    required this.colorById,
    required this.normalized,
  });

  @override
  Widget build(BuildContext context) {
    if (maxLen < 2 || index >= dates.length) return const SizedBox.shrink();

    final w = totalWidth - padLeft - padRight;
    final xFrac = index / (maxLen - 1);
    final xPos  = padLeft + w * xFrac;

    final date = dates[index];
    final dateLabel = '${date.month}/${date.day}/${date.year}';

    // Tooltip width and positioning
    const cardW = 148.0;
    // Keep card inside bounds
    double left = xPos + 8;
    if (left + cardW > totalWidth - padRight) left = xPos - cardW - 8;
    if (left < padLeft) left = padLeft;

    return Positioned(
      left: left,
      top: padTop + 4,
      child: IgnorePointer(
        child: Container(
          width: cardW,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
            boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dateLabel, style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppTheme.textDark, fontFamily: 'monospace',
              )),
              const SizedBox(height: 6),
              ...ids.map((id) {
                final ys = seriesById[id];
                final color = colorById[id] ?? AppTheme.primary;
                final label = labelsById[id] ?? id;
                final double? val = (ys != null && index < ys.length && ys[index].isFinite)
                    ? ys[index] : null;
                final valStr = val == null
                    ? '—'
                    : normalized
                        ? val.toStringAsFixed(2)
                        : val.toStringAsFixed(0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    Expanded(child: Text(label,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMed),
                      overflow: TextOverflow.ellipsis,
                    )),
                    Text(valStr, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: val != null ? color : AppTheme.textLight,
                      fontFamily: 'monospace',
                    )),
                  ]),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiLinePainter extends CustomPainter {
  final List<String> ids;
  final Map<String, List<double>> seriesById;
  final List<DateTime> dates;
  final double minY;
  final double maxY;
  final bool normalized;
  final Color gridColor;
  final TextStyle axisLabelStyle;
  final Map<String, Color> colorById;
  final List<List<int>?>? bandVectors;
  final Color bandBaseColor;

  static const _padLeft   = 44.0; // room for Y-axis labels
  static const _padRight  =  8.0;
  static const _padTop    = 10.0;
  static const _padBottom = 28.0; // room for X-axis dates

  _MultiLinePainter({
    required this.ids,
    required this.seriesById,
    required this.dates,
    required this.minY,
    required this.maxY,
    required this.normalized,
    required this.gridColor,
    required this.axisLabelStyle,
    required this.colorById,
    required this.bandVectors,
    required this.bandBaseColor,
  });

  int _dominantIndex(List<int>? v) {
    if (v == null || v.length < 4) return -1;
    int best = 0;
    for (int i = 1; i < 4; i++) {
      if (v[i] > v[best]) best = i;
    }
    return best;
  }

  void _drawText(Canvas canvas, String text, Offset offset, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: axisLabelStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: 60);
    final dx = align == TextAlign.right
        ? offset.dx - tp.width
        : align == TextAlign.center
            ? offset.dx - tp.width / 2
            : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ids.isEmpty) return;

    final w = size.width - _padLeft - _padRight;
    final h = size.height - _padTop - _padBottom;
    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);

    // Compute maxLen
    int maxLen = 0;
    for (final id in ids) {
      maxLen = math.max(maxLen, seriesById[id]?.length ?? 0);
    }
    if (maxLen < 2) return;

    final denom = math.max(1, maxLen - 1);

    double toX(int i) => _padLeft + w * (i / denom);
    double toY(double v) {
      final norm = ((v - minY) / span).clamp(0.0, 1.0);
      return _padTop + h * (1 - norm);
    }

    // ── Band overlay (visual only) ───────────────────────────────────────────
    if (bandVectors != null && bandVectors!.isNotEmpty) {
      for (int i = 0; i < maxLen; i++) {
        final idx = i < bandVectors!.length ? _dominantIndex(bandVectors![i]) : -1;
        if (idx < 0) continue;
        final opacity = (0.04 + idx * 0.015).clamp(0.02, 0.10);
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = bandBaseColor.withOpacity(opacity);
        final x0 = toX(i);
        final x1 = i + 1 < maxLen ? toX(i + 1) : toX(i) + w / denom;
        canvas.drawRect(Rect.fromLTWH(x0, _padTop, x1 - x0, h), paint);
      }
    }

    // ── Y-axis grid lines + labels ───────────────────────────────────────────
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withOpacity(0.35);

    final List<double> yTicks = normalized
        ? [0.0, 0.25, 0.5, 0.75, 1.0]
        : [0, 25, 50, 75, 100];

    for (final v in yTicks) {
      final y = toY(v);
      canvas.drawLine(Offset(_padLeft, y), Offset(_padLeft + w, y), gridPaint);
      final label = normalized
          ? v.toStringAsFixed(2)
          : v.toInt().toString();
      _drawText(canvas, label, Offset(_padLeft - 4, y), align: TextAlign.right);
    }

    // ── X-axis date labels (start, 1/3, 2/3, end) ────────────────────────────
    if (dates.isNotEmpty) {
      String fmt(DateTime d) =>
          '${d.month}/${d.day}';
      final xPositions = [0, (dates.length / 3).round(), (2 * dates.length / 3).round(), dates.length - 1]
          .where((i) => i >= 0 && i < dates.length)
          .toSet()
          .toList()
        ..sort();
      for (final i in xPositions) {
        final x = toX(i);
        final y = _padTop + h + 6;
        _drawText(canvas, fmt(dates[i]), Offset(x, y), align: TextAlign.center);
        // small tick
        canvas.drawLine(
          Offset(x, _padTop + h),
          Offset(x, _padTop + h + 4),
          gridPaint,
        );
      }
    }

    // ── Border left + bottom ─────────────────────────────────────────────────
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withOpacity(0.6);
    canvas.drawLine(Offset(_padLeft, _padTop), Offset(_padLeft, _padTop + h), axisPaint);
    canvas.drawLine(Offset(_padLeft, _padTop + h), Offset(_padLeft + w, _padTop + h), axisPaint);

    // ── Series lines ──────────────────────────────────────────────────────────
    for (final id in ids) {
      final ys = seriesById[id] ?? const <double>[];
      if (ys.isEmpty) continue;
      final color = colorById[id] ?? AppTheme.primary;

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;

      // Draw segments (lift pen at NaN gaps)
      final path = Path();
      bool inSeg = false;
      for (int i = 0; i < ys.length; i++) {
        final v = ys[i];
        if (!v.isFinite) {
          inSeg = false;
          continue;
        }
        final x = toX(i);
        final y = toY(v);
        if (!inSeg) {
          path.moveTo(x, y);
          inSeg = true;
        } else {
          path.lineTo(x, y);
        }
        // dot at each finite point
        canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      }
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) {
    return old.ids != ids ||
        old.seriesById != seriesById ||
        old.colorById != colorById ||
        old.minY != minY ||
        old.maxY != maxY ||
        old.bandVectors != bandVectors;
  }
}

// ─── Color picker sheet ───────────────────────────────────────────────────────
//
// Shows a row of palette swatches. Returns the chosen Color.
// Usage: await showColorPickerSheet(context, currentColor: c)

Future<Color?> showColorPickerSheet(BuildContext context, {required Color currentColor}) {
  return showModalBottomSheet<Color>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose color', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AppTheme.seriesPalette.map((c) {
                final selected = c.value == currentColor.value;
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(color: c.withOpacity(0.5), blurRadius: selected ? 8 : 2),
                      ],
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// ─── Legacy _LinePainter (used by SimpleLineChart) ────────────────────────────

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color gridColor;
  final Color lineColor;

  _LinePainter({required this.values, required this.gridColor, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minY = values.reduce(math.min);
    final maxY = values.reduce(math.max);
    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);

    const pad = 10.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withOpacity(0.5);

    for (int i = 0; i <= 4; i++) {
      final y = pad + h * (i / 4.0);
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), grid);
    }

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = pad + w * (i / math.max(1, values.length - 1));
      final yNorm = (values[i] - minY) / span;
      final y = pad + h * (1 - yNorm);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }

    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.gridColor != gridColor || old.lineColor != lineColor;
}
