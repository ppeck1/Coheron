// lib/widgets/nested_radar_input.dart
// Coheron v2.4 — Recursive radar input widget.
//
// Interaction grammar:
//   Domain radar  (always visible)
//     → tap a domain  → Plane radar for that domain
//       → tap a plane → Indicator radar for that plane
//
// No sliders at any depth level.
// Fine-tune affordance: small numeric badge tap opens a compact value dialog.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../theme/app_theme.dart';
import 'spider_chart.dart';

// ─── Public widget ────────────────────────────────────────────────────────────

/// Stateful nested radar input.
/// Owns drill-down state: which domain is open, which plane is open.
/// Calls [onValuesChanged] whenever any value changes.
class NestedRadarInput extends StatefulWidget {
  /// Current flat value map (metric_id → 0–100). The widget reads and writes
  /// into this; the parent stores the authoritative copy.
  final Map<String, int> values;
  final void Function(Map<String, int> updated) onValuesChanged;

  const NestedRadarInput({
    super.key,
    required this.values,
    required this.onValuesChanged,
  });

  @override
  State<NestedRadarInput> createState() => _NestedRadarInputState();
}

class _NestedRadarInputState extends State<NestedRadarInput>
    with TickerProviderStateMixin {
  // null = no domain open, 'ROOT.I' / 'ROOT.E' / 'ROOT.O' = domain open
  String? _openDomainId;
  // null = no plane open, L2.* = plane open
  String? _openPlaneId;

  late final AnimationController _domainCtl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _domainAnim =
      CurvedAnimation(parent: _domainCtl, curve: Curves.easeOutCubic);

  late final AnimationController _planeCtl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _planeAnim =
      CurvedAnimation(parent: _planeCtl, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _domainCtl.dispose();
    _planeCtl.dispose();
    super.dispose();
  }

  // ── Value helpers ────────────────────────────────────────────────────────────

  int _val(String id) => widget.values[id] ?? 50;

  void _set(String id, double v) {
    final next = Map<String, int>.from(widget.values);
    next[id] = v.round().clamp(0, 100);
    widget.onValuesChanged(next);
  }

  void _setAll(List<String> ids, List<double> vals) {
    final next = Map<String, int>.from(widget.values);
    for (var i = 0; i < ids.length; i++) {
      next[ids[i]] = vals[i].round().clamp(0, 100);
    }
    widget.onValuesChanged(next);
  }

  // ── Drill-down control ───────────────────────────────────────────────────────

  void _selectDomain(int idx) {
    final domainId = getDomainIds()[idx];
    final opening = _openDomainId != domainId;
    setState(() {
      _openDomainId = opening ? domainId : null;
      _openPlaneId = null;
    });
    if (opening) {
      // Seed plane values on first open
      for (final planeId in getPlanesForDomain(domainId)) {
        if (!widget.values.containsKey(planeId)) {
          _set(planeId, _val(domainId).toDouble());
        }
      }
      _planeCtl.reset();
      _domainCtl.forward(from: 0);
    } else {
      _domainCtl.reverse();
      _planeCtl.reverse();
    }
  }

  void _selectPlane(int idx) {
    if (_openDomainId == null) return;
    final planeIds = getPlanesForDomain(_openDomainId!);
    final planeId = planeIds[idx];
    final opening = _openPlaneId != planeId;
    setState(() => _openPlaneId = opening ? planeId : null);
    if (opening) {
      // Seed indicator values on first open
      for (final indId in getIndicatorsForPlane(planeId)) {
        if (!widget.values.containsKey(indId)) {
          _set(indId, _val(planeId).toDouble());
        }
      }
      _planeCtl.forward(from: 0);
    } else {
      _planeCtl.reverse();
    }
  }

  // ── Fine-tune dialog ─────────────────────────────────────────────────────────

  Future<void> _fineTune(BuildContext ctx, String id, Color color) async {
    int v = _val(id);
    await showDialog<void>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
        title: Text(getLabel(id),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$v', style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w800, color: color)),
          Slider(
            value: v.toDouble(), min: 0, max: 100, divisions: 100,
            activeColor: color, thumbColor: color,
            onChanged: (x) { setD(() => v = x.round()); _set(id, x); },
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('0 = worst', style: TextStyle(fontSize: 10, color: AppTheme.textLight)),
            Text('100 = best', style: TextStyle(fontSize: 10, color: AppTheme.textLight)),
          ]),
        ]),
        actions: [TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('Done'),
        )],
      )),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final domainIds = getDomainIds();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Level 1: Domain radar ──────────────────────────────────────────────
      _RadarCard(
        title: 'Domain State',
        subtitle: 'Drag vertex to sculpt · tap label to drill into planes',
        labels: domainIds.map(getLabel).toList(),
        values: domainIds.map((id) => _val(id).toDouble()).toList(),
        activeIndex: _openDomainId != null
            ? domainIds.indexOf(_openDomainId!) : null,
        fillColor: AppTheme.primary.withOpacity(0.14),
        strokeColor: AppTheme.primary,
        onChanged: (vals) => _setAll(domainIds, vals),
        onVertexTap: _selectDomain,
        onBadgeTap: (i) => _fineTune(context, domainIds[i],
            AppTheme.planeColor(domainIds[i])),
        valueFn: (i) => _val(domainIds[i]),
        badgeColor: (i) => AppTheme.planeColor(domainIds[i]),
      ),

      // ── Level 2: Plane radar (animated in) ────────────────────────────────
      if (_openDomainId != null)
        AnimatedBuilder(
          animation: _domainAnim,
          builder: (_, child) => ClipRect(
            child: Align(
              heightFactor: _domainAnim.value,
              child: Opacity(opacity: _domainAnim.value, child: child),
            ),
          ),
          child: _buildPlaneRadar(context, _openDomainId!),
        ),

      // ── Level 3: Indicator radar (animated in) ────────────────────────────
      if (_openPlaneId != null)
        AnimatedBuilder(
          animation: _planeAnim,
          builder: (_, child) => ClipRect(
            child: Align(
              heightFactor: _planeAnim.value,
              child: Opacity(opacity: _planeAnim.value, child: child),
            ),
          ),
          child: _buildIndicatorRadar(context, _openPlaneId!),
        ),
    ]);
  }

  Widget _buildPlaneRadar(BuildContext context, String domainId) {
    final planeIds  = getPlanesForDomain(domainId);
    final color     = AppTheme.planeColor(domainId);
    final domainLabel = getLabel(domainId);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _RadarCard(
        title: '$domainLabel — Planes',
        subtitle: 'Drag vertex to sculpt · tap label to drill into indicators.',
        labels: planeIds.map(getLabel).toList(),
        values: planeIds.map((id) => _val(id).toDouble()).toList(),
        activeIndex: _openPlaneId != null
            ? planeIds.indexOf(_openPlaneId!) : null,
        fillColor: color.withOpacity(0.12),
        strokeColor: color,
        onChanged: (vals) => _setAll(planeIds, vals),
        onVertexTap: _selectPlane,
        onBadgeTap: (i) => _fineTune(context, planeIds[i], color),
        valueFn: (i) => _val(planeIds[i]),
        badgeColor: (_) => color,
        accentBand: _DomainBand(label: domainLabel, color: color),
      ),
    );
  }

  Widget _buildIndicatorRadar(BuildContext context, String planeId) {
    final indicatorIds = getIndicatorsForPlane(planeId);
    final domainId     = getDomainForId(planeId) ?? 'ROOT.I';
    final color        = AppTheme.planeColor(domainId);
    final planeLabel   = getLabel(planeId);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _RadarCard(
        title: '$planeLabel — Indicators',
        subtitle: 'Deepest detail level.',
        labels: indicatorIds.map(getLabel).toList(),
        values: indicatorIds.map((id) => _val(id).toDouble()).toList(),
        activeIndex: null,
        fillColor: color.withOpacity(0.08),
        strokeColor: color.withOpacity(0.7),
        onChanged: (vals) => _setAll(indicatorIds, vals),
        onVertexTap: null,  // no further drill-down
        onBadgeTap: (i) => _fineTune(context, indicatorIds[i], color),
        valueFn: (i) => _val(indicatorIds[i]),
        badgeColor: (_) => color.withOpacity(0.7),
        accentBand: _DomainBand(label: planeLabel, color: color),
      ),
    );
  }
}

// ─── Radar card ───────────────────────────────────────────────────────────────

class _DomainBand {
  final String label;
  final Color color;
  const _DomainBand({required this.label, required this.color});
}

class _RadarCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> labels;
  final List<double> values;
  final int? activeIndex;
  final Color fillColor;
  final Color strokeColor;
  final ValueChanged<List<double>> onChanged;
  final void Function(int idx)? onVertexTap;
  final void Function(int idx) onBadgeTap;
  final int Function(int) valueFn;
  final Color Function(int) badgeColor;
  final _DomainBand? accentBand;

  const _RadarCard({
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.values,
    required this.activeIndex,
    required this.fillColor,
    required this.strokeColor,
    required this.onChanged,
    required this.onVertexTap,
    required this.onBadgeTap,
    required this.valueFn,
    required this.badgeColor,
    this.accentBand,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = accentBand?.color ?? AppTheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activeIndex != null
              ? borderColor.withOpacity(0.5)
              : AppTheme.divider,
        ),
        boxShadow: const [BoxShadow(
          color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Accent top band (for drill-down levels)
        if (accentBand != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: accentBand!.color.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(children: [
              Container(
                width: 3, height: 14,
                decoration: BoxDecoration(
                  color: accentBand!.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(accentBand!.label,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: accentBand!.color,
                    letterSpacing: 0.5,
                  )),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14,
                color: AppTheme.textDark)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(
                fontSize: 11, color: AppTheme.textLight)),
          ]),
        ),

        // Radar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            height: 220,
            child: _TappableRadar(
              labels: labels,
              values: values,
              fillColor: fillColor,
              strokeColor: strokeColor,
              activeIndex: activeIndex,
              onChanged: onChanged,
              onVertexTap: onVertexTap,
            ),
          ),
        ),

        // Value badges row
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(labels.length, (i) {
              final c = badgeColor(i);
              final active = activeIndex == i;
              // At drill-down levels: tap badge → drill-down
              // At indicator level (no further drill): long-press → fine-tune
              final canDrillDown = onVertexTap != null;
              return GestureDetector(
                onTap: canDrillDown
                    ? () => onVertexTap!(i)
                    : () => onBadgeTap(i),
                onLongPress: canDrillDown
                    ? () => onBadgeTap(i)   // fine-tune is secondary, long-press only
                    : () => onBadgeTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? c.withOpacity(0.14) : c.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? c : c.withOpacity(0.3),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(labels[i],
                        style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w600,
                          color: active ? c : AppTheme.textLight,
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(height: 1),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${valueFn(i)}',
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: c,
                          )),
                      const SizedBox(width: 2),
                      Icon(
                        canDrillDown
                            ? (active ? Icons.expand_less : Icons.chevron_right)
                            : Icons.drag_handle,
                        size: 11, color: c.withOpacity(0.7),
                      ),
                    ]),
                  ]),
                ),
              );
            }),
          ),
        ),

        // Contextual hint
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(
            onVertexTap != null
                ? (activeIndex != null
                    ? 'Tap to switch · drag vertex to sculpt'
                    : 'Drag vertex to sculpt · tap label to drill down')
                : 'Drag vertex to adjust · long-press label to fine-tune',
            style: const TextStyle(fontSize: 10, color: AppTheme.textLight),
          ),
        ),
      ]),
    );
  }
}

// ─── Tappable radar (wraps SpiderChart with vertex tap detection) ─────────────

class _TappableRadar extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final Color fillColor;
  final Color strokeColor;
  final int? activeIndex;
  final ValueChanged<List<double>> onChanged;
  final void Function(int idx)? onVertexTap;

  const _TappableRadar({
    required this.labels,
    required this.values,
    required this.fillColor,
    required this.strokeColor,
    required this.activeIndex,
    required this.onChanged,
    required this.onVertexTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final size = math.min(constraints.maxWidth, constraints.maxHeight);
      return CustomPaint(
        size: Size.square(size),
        foregroundPainter: _ActiveHighlightPainter(
          n: labels.length,
          activeIndex: activeIndex,
          color: AppTheme.primary,
          size: size,
        ),
        child: SpiderChart(
          labels: labels,
          values: values,
          steps: 4,
          maxValue: 100,
          fillColor: fillColor,
          strokeColor: strokeColor,
          onChanged: onChanged,
          onVertexTap: onVertexTap,
        ),
      );
    });
  }
}

// Paints an active-axis highlight ring on top of the spider chart.
class _ActiveHighlightPainter extends CustomPainter {
  final int n;
  final int? activeIndex;
  final Color color;
  final double size;

  const _ActiveHighlightPainter({
    required this.n,
    required this.activeIndex,
    required this.color,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size sz) {
    final idx = activeIndex;
    if (idx == null || n == 0) return;
    final center = Offset(sz.width / 2, sz.height / 2);
    final radius = math.min(sz.width, sz.height) * 0.38;
    final angle  = -math.pi / 2 + (2 * math.pi / n) * idx;
    final tip    = center + Offset(math.cos(angle), math.sin(angle)) * radius;

    canvas.drawLine(
      center, tip,
      Paint()
        ..color = color.withOpacity(0.4)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      tip, 9,
      Paint()
        ..color = color.withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      tip, 9,
      Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ActiveHighlightPainter old) =>
      old.activeIndex != activeIndex || old.n != n;
}
