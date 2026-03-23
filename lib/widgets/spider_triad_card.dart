
import 'package:flutter/material.dart';

class SpiderTriadCard extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<double> values;
  final ValueChanged<List<double>> onChanged;

  const SpiderTriadCard({
    super.key,
    required this.title,
    required this.labels,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  "Spider chart placeholder (CustomPainter based)\nTriad: ${labels.join(', ')}",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
