
// lib/screens/lattice_inspector_screen.dart
// Phase 3A: Integrity layer inspector for Role×Plane epistemics.

import 'package:flutter/material.dart';
import '../taxonomy/taxonomy_locked.dart';

import '../canon/roles.dart';
import '../services/epistemics_service.dart';
import '../services/input_coverage_service.dart';
import '../theme/app_theme.dart';

class LatticeInspectorScreen extends StatefulWidget {
  const LatticeInspectorScreen({super.key});

  @override
  State<LatticeInspectorScreen> createState() => _LatticeInspectorScreenState();
}

class _LatticeInspectorScreenState extends State<LatticeInspectorScreen> {
  final _epi = EpistemicsService();
  final _cov = InputCoverageService();
  DateTime _day = DateTime.now();
  Map<String, Map<String, Object?>> _cells = {}; // key: role|plane

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _load() async {
    await _epi.ensureDefaultsForDate(_day);
    final date = _fmt(_day);
    final rows = await _epi.listForDate(date);
    final map = <String, Map<String, Object?>>{};
    for (final r in rows) {
      final role = (r['role_id'] as String?) ?? '';
      final plane = (r['plane_id'] as String?) ?? '';
      map['$role|$plane'] = r;
    }
    setState(() => _cells = map);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _day = picked);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final planes = const <String>['ROOT.I', 'ROOT.E', 'ROOT.O'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lattice Inspector'),
        actions: [
          IconButton(onPressed: _pickDay, icon: const Icon(Icons.calendar_month)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _header(context),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                children: [
                  _planeHeaderRow(planes),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: kCanonRoles.map((role) => _roleRow(role, planes)).toList(),
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

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Text(_fmt(_day), style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        const Text('q/c source: calc vs user', style: TextStyle(color: AppTheme.textLight)),
      ],
    );
  }

  Widget _planeHeaderRow(List<String> planes) {
    return Row(
      children: [
        const SizedBox(width: 70),
        for (final p in planes)
          Expanded(
            child: Center(
              // UI must never leak internal metric IDs (e.g., ROOT.I).
              child: Text(labelForMetricId(p), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _roleRow(CanonRole role, List<String> planes) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(role.id, style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final p in planes) Expanded(child: _cell(role.id, p)),
        ],
      ),
    );
  }

  Widget _cell(String roleId, String planeId) {
    final r = _cells['$roleId|$planeId'];
    final q = (r?['q_0_1'] as num?)?.toDouble() ?? 0;
    final c = (r?['c_0_1'] as num?)?.toDouble() ?? 0;
    final w = q * c;
    final qs = (r?['q_source'] as String?) ?? 'calc';
    final cs = (r?['c_source'] as String?) ?? 'calc';
    final source = (qs == 'user' || cs == 'user') ? 'user' : 'calc';

    return InkWell(
      onTap: () => _openCell(roleId, planeId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: source == 'user' ? AppTheme.accent : AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('w=${w.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('q=${q.toStringAsFixed(2)}  c=${c.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMed)),
            const SizedBox(height: 2),
            Text(source, style: TextStyle(fontSize: 12, color: source == 'user' ? AppTheme.accent : AppTheme.textLight)),
          ],
        ),
      ),
    );
  }

  Future<void> _openCell(String roleId, String planeId) async {
    final cov = await _cov.computeForDate(_day);
    final covPlane = switch (planeId) {
      'ROOT.I' => cov?.covPlaneI,
      'ROOT.E' => cov?.covPlaneE,
      'ROOT.O' => cov?.covPlaneO,
      _ => null,
    };
    final covEntry = cov?.covEntry;

    final r = _cells['$roleId|$planeId'];
    var q = (r?['q_0_1'] as num?)?.toDouble() ?? 0.5;
    var c = (r?['c_0_1'] as num?)?.toDouble() ?? 0.5;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$roleId × ${labelForMetricId(planeId)}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('cov_plane=${covPlane?.toStringAsFixed(2) ?? '—'}   cov_entry=${covEntry?.toStringAsFixed(2) ?? '—'}',
                    style: const TextStyle(color: AppTheme.textMed)),
                const SizedBox(height: 12),
                Text('q (measurement quality): ${q.toStringAsFixed(2)}'),
                Slider(
                  value: q.clamp(0.0, 1.0),
                  min: 0, max: 1,
                  onChanged: (v) => setSheet(() => q = v),
                ),
                Text('c (interpretation confidence): ${c.toStringAsFixed(2)}'),
                Slider(
                  value: c.clamp(0.0, 1.0),
                  min: 0, max: 1,
                  onChanged: (v) => setSheet(() => c = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await _epi.revertToComputed(_day, roleId: roleId, planeId: planeId);
                        Navigator.pop(context);
                      },
                      child: const Text('Revert to computed'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () async {
                        await _epi.setOverride(_day, roleId: roleId, planeId: planeId, q: q, c: c);
                        Navigator.pop(context);
                      },
                      child: const Text('Save override'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        });
      },
    );

    await _load();
  }
}
