import 'package:flutter/material.dart';
import 'spider_chart.dart';

/// Card wrapper for SpiderChart.
/// If onChanged is omitted, chart renders read-only and expects edits via onEdit.
class SpiderInputCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<String> labels;
  final List<num> values; // accepts int/num; coerces to double 0..100
  final ValueChanged<List<double>>? onChanged; // optional
  final VoidCallback? onEdit;
  final int steps;
  final double height;

  const SpiderInputCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.labels,
    required this.values,
    this.onChanged,
    this.onEdit,
    this.steps = 4,
    this.height = 240,
  }) : assert(labels.length == values.length);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final readOnly = onChanged == null;

    final dv = values.map((v) => v.toDouble()).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: t.textTheme.titleMedium)),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                  ),
              ],
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: height,
              child: SpiderChart(
                labels: labels,
                values: dv,
                steps: steps,
                readOnly: readOnly,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
