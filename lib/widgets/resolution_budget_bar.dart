import 'package:flutter/material.dart';

/// ResolutionBudgetBar
///
/// UI contract for epistemic honesty:
/// - shows per-plane coverage + entry coverage (if available)
/// - provides two non-moral "boost" actions to expand input depth
///
/// Coverage is advisory here; substrate computes/persists coverage on save.
class ResolutionBudgetBar extends StatelessWidget {
  final double? covIn;
  final double? covOut;
  final double? covBeh;
  final double? covEntry;
  final bool loading;
  final VoidCallback onBoostPlanes;
  final VoidCallback onBoostIndicators;

  const ResolutionBudgetBar({
    super.key,
    required this.covIn,
    required this.covOut,
    required this.covBeh,
    required this.covEntry,
    required this.loading,
    required this.onBoostPlanes,
    required this.onBoostIndicators,
  });

  String _label(double? v) {
    if (v == null) return '—';
    if (v <= 0.45) return 'Coarse';
    if (v < 0.90) return 'Medium';
    return 'High';
  }

  Widget _chip(BuildContext context, String name, double? v) {
    final cs = Theme.of(context).colorScheme;
    final label = _label(v);
    final text = v == null ? '$name: $label' : '$name: $label ${(v * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entryLabel = _label(covEntry);
    final entryText = covEntry == null
        ? 'Today’s Resolution: $entryLabel'
        : 'Today’s Resolution: $entryLabel ${(covEntry! * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entryText,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, 'IN', covIn),
              _chip(context, 'OUT', covOut),
              _chip(context, 'BEH', covBeh),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBoostPlanes,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: cs.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('+6 sliders → Improve shape (Planes)', textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onBoostIndicators,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: cs.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('+18 sliders → Improve diagnostics (Indicators)', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'What this means',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            children: [
              _bullet(context, 'Coarse = trend trace … Medium = shape … High = diagnostic resolution.'),
              _bullet(context, 'Lower resolution automatically lowers default q/c unless you override later.'),
              _bullet(context, 'Calculated fills are labeled … they do not imply certainty.'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 6, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
