// lib/screens/atlas_screen.dart
// Atlas v2.0 — Primary home screen.
// Layout: 3×3 grid of plane tiles (Domains = columns, Planes = rows).
// Each tile shows: plane label, mini radar of 3 indicators, magnitude fill,
// trend glyph, and selection border.
// Above the grid: summary strip (Observed, Δ, Signal/Noise, Coverage).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/entry_service.dart';
import '../services/app_events.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../theme/app_theme.dart';
import 'system_views_screen.dart';

class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});

  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  Entry? _latest;
  Entry? _prev;
  Map<String, int> _values = {};
  Map<String, int> _prevValues = {};
  bool _loading = true;

  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () => _load();
    AppEvents.entrySavedTick.addListener(_listener);
    _load();
  }

  @override
  void dispose() {
    AppEvents.entrySavedTick.removeListener(_listener);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entry = await EntryService.instance.getCurrentEntry();
    Map<String, int> vals = {};
    if (entry?.id != null) {
      vals = await EntryService.instance.getMetricValues(entry!.id!);
    }

    // Load previous entry for trend/delta
    Entry? prev;
    Map<String, int> prevVals = {};
    if (entry != null) {
      prev = await EntryService.instance.getPreviousEntry(entry.timestamp);
      if (prev?.id != null) {
        prevVals = await EntryService.instance.getMetricValues(prev!.id!);
      }
    }

    if (mounted) {
      setState(() {
        _latest = entry;
        _values = vals;
        _prev = prev;
        _prevValues = prevVals;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _buildAtlas(context),
      ),
    );
  }

  Widget _buildAtlas(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(child: _buildSummaryStrip()),
        SliverToBoxAdapter(child: _buildDomainComparison()),
        SliverToBoxAdapter(child: _buildDomainHeaders()),
        SliverToBoxAdapter(child: _buildGrid(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ts = _latest != null ? DateTime.tryParse(_latest!.timestamp) : null;
    final tsLabel = ts != null
        ? '${ts.month}/${ts.day}/${ts.year}  ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ATLAS',
                    style: CTypography.telemetryTitle.copyWith(
                        color: AppTheme.textDark, letterSpacing: 3)),
                if (tsLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(tsLabel,
                      style: CTypography.telemetry
                          .copyWith(color: AppTheme.textLight, fontSize: 11)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: AppTheme.textLight,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip() {
    if (_latest == null) return _buildEmptyStrip();

    // Compute summary stats from domain values
    final domainIds = getDomainIds();
    final domainVals = domainIds
        .map((d) => _values[d])
        .whereType<int>()
        .toList();

    final observed = domainVals.isEmpty
        ? null
        : domainVals.fold(0, (a, b) => a + b) / domainVals.length;

    // Δ from previous
    double? delta;
    if (_prevValues.isNotEmpty && observed != null) {
      final prevDomainVals = domainIds
          .map((d) => _prevValues[d])
          .whereType<int>()
          .toList();
      if (prevDomainVals.isNotEmpty) {
        final prevMean =
            prevDomainVals.fold(0, (a, b) => a + b) / prevDomainVals.length;
        delta = observed - prevMean;
      }
    }

    // Signal / Noise — ratio of plane values to indicator dispersion
    final allLeafVals = _values.entries
        .where((e) => e.key.startsWith('LEAF.'))
        .map((e) => e.value.toDouble())
        .toList();
    double? snRatio;
    if (allLeafVals.length >= 2) {
      final mean = allLeafVals.fold(0.0, (a, b) => a + b) / allLeafVals.length;
      final variance = allLeafVals
              .map((v) => (v - mean) * (v - mean))
              .fold(0.0, (a, b) => a + b) /
          allLeafVals.length;
      final noise = math.sqrt(variance);
      snRatio = noise > 0 ? mean / noise : null;
    }

    // Coverage
    final coverage = _latest!.completionPercent;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCell('OBSERVED',
              observed != null ? observed.toStringAsFixed(0) : '—', null),
          _divider(),
          _statCell(
            'Δ',
            delta != null
                ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}'
                : '—',
            delta == null
                ? null
                : (delta >= 0 ? AppTheme.primary : AppTheme.accent),
          ),
          _divider(),
          _statCell(
            'S/N',
            snRatio != null ? snRatio.toStringAsFixed(1) : '—',
            null,
          ),
          _divider(),
          _statCell(
            'COVERAGE',
            '${coverage.toStringAsFixed(0)}%',
            coverage > 60
                ? AppTheme.primary
                : coverage > 30
                    ? const Color(0xFFD4A017)
                    : AppTheme.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCell('OBSERVED', '—', null),
          _divider(),
          _statCell('Δ', '—', null),
          _divider(),
          _statCell('S/N', '—', null),
          _divider(),
          _statCell('COVERAGE', '—', null),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color? valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: CTypography.telemetry.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppTheme.textDark,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: CTypography.telemetryLabel
                .copyWith(color: AppTheme.textLight, fontSize: 8)),
      ],
    );
  }

  Widget _divider() => Container(
        height: 28,
        width: 1,
        color: AppTheme.divider,
      );

  Widget _buildDomainComparison() {
    final domainIds = getDomainIds();
    // Normalized 0..1 values for each domain
    final domainVals = domainIds.map((id) {
      final v = _values[id];
      return v != null ? v / 100.0 : 0.0;
    }).toList();

    final hasData = domainVals.any((v) => v > 0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('DOMAIN  OVERVIEW',
              style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: AppTheme.textLight, letterSpacing: 1.2,
              )),
          const Spacer(),
          // Domain value pills
          ...domainIds.asMap().entries.map((e) {
            final color = AppTheme.planeColor(e.value);
            final val = _values[e.value];
            return Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                )),
                const SizedBox(width: 4),
                Text(
                  val != null ? '$val' : '—',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color,
                  ),
                ),
              ]),
            );
          }),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 140,
          child: hasData
              ? CustomPaint(
                  painter: _DomainComparisonPainter(
                    domainVals: domainVals,
                    colors: domainIds.map(AppTheme.planeColor).toList(),
                    labels: domainIds.map(getLabel).toList(),
                  ),
                  size: const Size(double.infinity, 140),
                )
              : const Center(
                  child: Text('Log a check-in to see domain state.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                ),
        ),
      ]),
    );
  }
  Widget _buildDomainHeaders() {
    const domainIds = ['ROOT.I', 'ROOT.E', 'ROOT.O'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: domainIds.map((d) => Expanded(
          child: Center(
            child: Text(
              getLabel(d).toUpperCase(),
              style: CTypography.telemetryLabel.copyWith(
                color: AppTheme.planeColor(d),
                fontSize: 8,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    // 3×3 grid: columns = domains, rows = plane positions (positional only)
    // Row 0: Body          | Safety  | Follow-through
    // Row 1: Attention     | Support | Activity
    // Row 2: Affect        | Demands | Recovery
    const domainIds = ['ROOT.I', 'ROOT.E', 'ROOT.O'];
    final planesByDomain = domainIds.map((d) => getPlanesForDomain(d)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: List.generate(3, (row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(3, (col) {
                final planeId = planesByDomain[col][row];
                final domainId = domainIds[col];
                return Expanded(
                  child: _PlaneTile(
                    planeId: planeId,
                    domainId: domainId,
                    values: _values,
                    prevValues: _prevValues,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SystemViewsScreen(initialSelected: {planeId}),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Domain Comparison Painter ────────────────────────────────────────────────

/// Paints three overlapping polygons on a shared 3-axis (equilateral triangle)
/// radar — one per domain, each in its canonical color.
class _DomainComparisonPainter extends CustomPainter {
  final List<double> domainVals; // 0..1, length 3
  final List<Color> colors;
  final List<String> labels;

  const _DomainComparisonPainter({
    required this.domainVals,
    required this.colors,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const n = 3;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;

    // Grid rings
    final gridPaint = Paint()
      ..color = const Color(0xFFD0CEC8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (var s = 1; s <= 4; s++) {
      final r = radius * (s / 4);
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = center + Offset(math.cos(_angle(i)), math.sin(_angle(i))) * r;
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Axes
    for (var i = 0; i < n; i++) {
      final tip = center + Offset(math.cos(_angle(i)), math.sin(_angle(i))) * radius;
      canvas.drawLine(center, tip, gridPaint);
    }

    // Three overlapping polygons, back-to-front by value (largest last)
    final order = [0, 1, 2]..sort((a, b) =>
        domainVals[b].compareTo(domainVals[a]));

    for (final di in order) {
      final v = domainVals[di].clamp(0.0, 1.0);
      if (v <= 0) continue;
      final color = colors[di];

      final poly = Path();
      for (var i = 0; i < n; i++) {
        final r = radius * v;
        final p = center + Offset(math.cos(_angle(i)), math.sin(_angle(i))) * r;
        if (i == 0) poly.moveTo(p.dx, p.dy);
        else poly.lineTo(p.dx, p.dy);
      }
      poly.close();

      canvas.drawPath(poly, Paint()
        ..color = color.withOpacity(0.12)
        ..style = PaintingStyle.fill);
      canvas.drawPath(poly, Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);

      // Dot at this domain's vertex
      final domainTip = center +
          Offset(math.cos(_angle(di)), math.sin(_angle(di))) * radius * v;
      canvas.drawCircle(domainTip, 5, Paint()..color = color);
    }

    // Labels at axis tips
    for (var i = 0; i < n; i++) {
      final tip = center + Offset(math.cos(_angle(i)), math.sin(_angle(i))) * (radius * 1.22);
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: colors[i],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 70);
      tp.paint(canvas, tip - Offset(tp.width / 2, tp.height / 2));
    }
  }

  static double _angle(int i) => -math.pi / 2 + (2 * math.pi / 3) * i;

  @override
  bool shouldRepaint(covariant _DomainComparisonPainter old) =>
      old.domainVals != domainVals;
}

// ─── Plane Tile ───────────────────────────────────────────────────────────────

class _PlaneTile extends StatelessWidget {
  final String planeId;
  final String domainId;
  final Map<String, int> values;
  final Map<String, int> prevValues;
  final VoidCallback onTap;

  const _PlaneTile({
    required this.planeId,
    required this.domainId,
    required this.values,
    required this.prevValues,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final domainColor = AppTheme.planeColor(domainId);
    final planeVal = values[planeId];
    final prevVal = prevValues[planeId];
    final indicatorIds = getIndicatorsForPlane(planeId);

    // Trend glyph
    String? trendGlyph;
    Color? trendColor;
    if (planeVal != null && prevVal != null) {
      final d = planeVal - prevVal;
      if (d > 3) { trendGlyph = '↑'; trendColor = AppTheme.primary; }
      else if (d < -3) { trendGlyph = '↓'; trendColor = AppTheme.accent; }
      else { trendGlyph = '→'; trendColor = AppTheme.textLight; }
    }

    // Magnitude fill — based on plane value
    final fillFraction = planeVal != null ? (planeVal / 100.0).clamp(0.0, 1.0) : 0.0;

    // Uncertainty halo — proxy: inverse of coverage for this plane's indicators
    final indicatorCoverage = indicatorIds
        .where((id) => values.containsKey(id))
        .length / indicatorIds.length;
    final hasHalo = indicatorCoverage < 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: domainColor.withOpacity(0.35),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: domainColor.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Magnitude fill (bottom)
            if (fillFraction > 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12)),
                  child: Container(
                    height: fillFraction * 80,
                    color: domainColor.withOpacity(0.07),
                  ),
                ),
              ),

            // Uncertainty halo ring
            if (hasHalo)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFD4A017).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Plane label + trend
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          getLabel(planeId),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trendGlyph != null) ...[
                        const SizedBox(width: 2),
                        Text(trendGlyph,
                            style: TextStyle(
                                fontSize: 10,
                                color: trendColor,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Mini radar
                  _MiniRadar(
                    indicatorIds: indicatorIds,
                    values: values,
                    color: domainColor,
                  ),

                  const SizedBox(height: 6),

                  // Value readout
                  Text(
                    planeVal != null ? '$planeVal' : '—',
                    style: CTypography.telemetry.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: planeVal != null ? domainColor : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mini Radar ───────────────────────────────────────────────────────────────

class _MiniRadar extends StatelessWidget {
  final List<String> indicatorIds;
  final Map<String, int> values;
  final Color color;

  const _MiniRadar({
    required this.indicatorIds,
    required this.values,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: CustomPaint(
        painter: _RadarPainter(
          indicatorIds: indicatorIds,
          values: values,
          color: color,
        ),
        size: const Size(double.infinity, 44),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<String> indicatorIds;
  final Map<String, int> values;
  final Color color;

  _RadarPainter({
    required this.indicatorIds,
    required this.values,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = indicatorIds.length;
    if (n < 3) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 2;

    // Draw ring guides
    final ringPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (final fraction in [0.33, 0.66, 1.0]) {
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = (2 * math.pi * i / n) - math.pi / 2;
        final x = cx + r * fraction * math.cos(angle);
        final y = cy + r * fraction * math.sin(angle);
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, ringPaint);
    }

    // Draw spokes
    final spokePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..strokeWidth = 0.5;
    for (int i = 0; i < n; i++) {
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
        spokePaint,
      );
    }

    // Draw filled area
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final val = (values[indicatorIds[i]] ?? 0) / 100.0;
      final angle = (2 * math.pi * i / n) - math.pi / 2;
      pts.add(Offset(cx + r * val * math.cos(angle),
          cy + r * val * math.sin(angle)));
    }

    final hasData = indicatorIds.any((id) => values.containsKey(id));

    if (hasData) {
      final fillPath = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        fillPath.lineTo(pts[i].dx, pts[i].dy);
      }
      fillPath.close();

      canvas.drawPath(
          fillPath,
          Paint()
            ..color = color.withOpacity(0.18)
            ..style = PaintingStyle.fill);

      canvas.drawPath(
          fillPath,
          Paint()
            ..color = color.withOpacity(0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..strokeJoin = StrokeJoin.round);

      // Dots at each vertex
      for (final pt in pts) {
        canvas.drawCircle(pt, 2.0, Paint()..color = color.withOpacity(0.9));
      }
    } else {
      // No data — draw faint center dot
      canvas.drawCircle(
          Offset(cx, cy),
          2.0,
          Paint()..color = color.withOpacity(0.3));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.values != values || old.color != color;
}
