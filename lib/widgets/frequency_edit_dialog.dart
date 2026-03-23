import 'package:flutter/material.dart';

import '../models/models.dart';
import 'spider_chart.dart';

/// Editor for the 4-mode frequency composition (Sense/Maintain/Explore/Enforce).
/// Pure reflection-layer input: sums to 100, does not affect substrate coherence.
class FrequencyEditDialog extends StatefulWidget {
  final FrequencyComposition initial;
  const FrequencyEditDialog({super.key, required this.initial});

  @override
  State<FrequencyEditDialog> createState() => _FrequencyEditDialogState();
}

class _FrequencyEditDialogState extends State<FrequencyEditDialog> {
  late int sense;
  late int maintain;
  late int explore;
  late int enforce;

  @override
  void initState() {
    super.initState();
    sense = widget.initial.sense;
    maintain = widget.initial.maintain;
    explore = widget.initial.explore;
    enforce = widget.initial.enforce;
  }

  void _apply(List<double> vals) {
    final fc = FrequencyComposition(
      sense: vals[0].round(),
      maintain: vals[1].round(),
      explore: vals[2].round(),
      enforce: vals[3].round(),
      updatedAt: widget.initial.updatedAt,
    ).normalized();
    setState(() {
      sense = fc.sense;
      maintain = fc.maintain;
      explore = fc.explore;
      enforce = fc.enforce;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Frequency modes today'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Reflection layer… styles the band; also trended.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              width: 260,
              child: SpiderChart(
                labels: const ['Sense', 'Maintain', 'Explore', 'Enforce'],
                values: [
                  sense.toDouble(),
                  maintain.toDouble(),
                  explore.toDouble(),
                  enforce.toDouble(),
                ],
                onChanged: _apply,
                steps: 4,
                maxValue: 100,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Sense: $sense%')),
                Expanded(child: Text('Maintain: $maintain%')),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Explore: $explore%')),
                Expanded(child: Text('Enforce: $enforce%')),
              ],
            ),
            const SizedBox(height: 6),
            Text('Total: ${sense + maintain + explore + enforce}%'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            FrequencyComposition(sense: sense, maintain: maintain, explore: explore, enforce: enforce).normalized(),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
