// lib/widgets/common_widgets.dart

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

// ─── Score circle ─────────────────────────────────────────────────────────────

class ScoreCircle extends StatelessWidget {
  final double score;
  final double? lower;
  final double? upper;
  final double? confidence;
  final double size;

  const ScoreCircle({
    super.key,
    required this.score,
    this.lower,
    this.upper,
    this.confidence,
    this.size = 100,
  });

  Color _color(double s) {
    if (s >= 70) return const Color(0xFF1A8A8A);
    if (s >= 45) return const Color(0xFFE8972D);
    return const Color(0xFFD94F3D);
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(score);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _CirclePainter(value: score / 100, color: color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score.round().toString(),
                    style: TextStyle(
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1,
                    ),
                  ),
                  Text(
                    '/100',
                    style: TextStyle(
                        fontSize: size * 0.11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (lower != null && upper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${lower!.round()} – ${upper!.round()}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textLight),
            ),
          ),
        if (confidence != null)
          Text(
            'Confidence ${confidence!.round()}/100',
            style: const TextStyle(fontSize: 11, color: AppTheme.textLight),
          ),
      ],
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double value;
  final Color color;
  const _CirclePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final bgPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    final fgPaint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // -π/2 (top)
      value * 6.2832,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.value != value || old.color != color;
}

// ─── Labeled slider ───────────────────────────────────────────────────────────

class LabeledSlider extends StatelessWidget {
  final String label;
  final String description;
  final double value;
  final String leftLabel;
  final String rightLabel;
  final ValueChanged<double> onChanged;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.leftLabel = '0',
    this.rightLabel = '10',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.textDark)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  value.round().toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 10,
            divisions: 10,
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(leftLabel,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textLight)),
              Text(rightLabel,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textLight)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const SectionCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }
}

// ─── Collapsible section ──────────────────────────────────────────────────────

class CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textLight,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

// ─── Area summary tile ────────────────────────────────────────────────────────

class AreaSummaryTile extends StatelessWidget {
  final String emoji;
  final String name;
  final double areaScore;
  final double certaintyScore;
  final double overloadScore;
  final bool skipped;
  final VoidCallback? onTap;

  const AreaSummaryTile({
    super.key,
    required this.emoji,
    required this.name,
    required this.areaScore,
    required this.certaintyScore,
    required this.overloadScore,
    this.skipped = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14)),
                  if (!skipped)
                    Text(
                      'Certainty ${certaintyScore.round()}/100',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textLight),
                    ),
                  if (skipped)
                    const Text('Skipped',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textLight)),
                ],
              ),
            ),
            if (!skipped) ...[
              _BarMini(value: areaScore / 100, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                areaScore.round().toString(),
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppTheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarMini extends StatelessWidget {
  final double value;
  final Color color;
  const _BarMini({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

// ─── Signal card ──────────────────────────────────────────────────────────────

class SignalCard extends StatelessWidget {
  final Signal signal;

  const SignalCard({super.key, required this.signal});

  Color get _color => switch (signal.severity) {
        SignalSeverity.warn => const Color(0xFFD94F3D),
        SignalSeverity.watch => const Color(0xFFE8972D),
        SignalSeverity.info => AppTheme.primary,
      };

  String get _label => switch (signal.severity) {
        SignalSeverity.warn => 'WARN',
        SignalSeverity.watch => 'WATCH',
        SignalSeverity.info => 'INFO',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: _color.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _color,
                        letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    signal.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              signal.triggerReason,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMed),
            ),
            if (signal.contributingFactors.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...signal.contributingFactors.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('· ',
                            style: TextStyle(color: AppTheme.textLight)),
                        Expanded(
                          child: Text(f,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textLight)),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Metric stat chip ─────────────────────────────────────────────────────────

class StatChip extends StatelessWidget {
  final String label;
  final String value;

  const StatChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.textDark)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textLight)),
        ],
      ),
    );
  }
}

// ─── Phase 2 helper widgets ─────────────────────────────────────────────────

class InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const InfoCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class SystemLoadPanel extends StatelessWidget {
  final double rootI;
  final double rootE;
  final double rootO;
  final double threshold;

  const SystemLoadPanel({
    super.key,
    required this.rootI,
    required this.rootE,
    required this.rootO,
    this.threshold = 7.0,
  });

  Widget _bar(BuildContext context, String label, double v) {
    final t = (v / 10.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 74, child: Text(label, style: const TextStyle(color: AppTheme.textMed))),
          Expanded(
            child: SizedBox(
              height: 14,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: t,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 34, child: Text(v.toStringAsFixed(1), style: const TextStyle(color: AppTheme.textDark))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CURRENT STATE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppTheme.textLight)),
          const SizedBox(height: 8),
          _bar(context, 'Internal', rootI),
          _bar(context, 'External', rootE),
          _bar(context, 'Output', rootO),
        ],
      ),
    );
  }
}
