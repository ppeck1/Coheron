// lib/screens/debug_substrate_screen.dart
// Stage 1C: Verification surface (NOT a user feature).
//
// Purpose:
// - Confirm coverage scalars are being computed + persisted.
// - Confirm q/c defaults are being written for all role×plane cells.
// - Provide an auditable readout without external sqlite tooling.

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/input_coverage_service.dart';
import '../services/epistemics_service.dart';
import '../canon/roles.dart';
import '../theme/app_theme.dart';

class DebugSubstrateScreen extends StatefulWidget {
  const DebugSubstrateScreen({super.key});

  @override
  State<DebugSubstrateScreen> createState() => _DebugSubstrateScreenState();
}

class _DebugSubstrateScreenState extends State<DebugSubstrateScreen> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  Map<String, Object?>? _covRow;
  List<Map<String, Object?>> _epiRows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateKey => _date.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = DatabaseHelper.instance;
      // Ensure coverage exists; if not, compute + upsert.
      final existing = await db.getCoverageDaily(_dateKey);
      if (existing == null) {
        final cov = await InputCoverageService.instance.computeAndPersistForDate(_date);
        // Also ensure epistemics defaults are present.
        await EpistemicsService().ensureDefaultsForDate(_date);
      }

      final covRow = await db.getCoverageDaily(_dateKey);
      final epiRows = await db.listRolePlaneEpistemics(_dateKey);

      setState(() {
        _covRow = covRow;
        _epiRows = epiRows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug: Substrate (Stage 1C)'),
        // Use theme-resolved colors (AppTheme has no `text` token).
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Pick date',
            icon: const Icon(Icons.calendar_today_rounded),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(_error!)
              : _content(),
    );
  }

  Widget _errorView(String msg) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Error', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.red)),
          const SizedBox(height: 10),
          Text(msg, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final cov = _covRow;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          title: 'Date',
          child: Text(_dateKey, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Coverage (InputCoverageDaily)',
          child: cov == null
              ? const Text('No row found')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('cov_in', cov['cov_in']),
                    _kv('cov_out', cov['cov_out']),
                    _kv('cov_beh', cov['cov_beh']),
                    _kv('cov_entry', cov['cov_entry']),
                    const Divider(height: 18),
                    _kv('calc_rule_id', cov['calc_rule_id']),
                    _kv('calc_inputs_json', (cov['calc_inputs_json'] ?? '').toString().take(160)),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Epistemics (RolePlaneEpistemics)',
          subtitle: 'Expect 9 rows (3 roles × 3 planes).',
          child: _epiRows.isEmpty
              ? const Text('No rows found')
              : Column(
                  children: _epiRows.map((r) {
                    final role = (r['role_id'] ?? '').toString();
                    final plane = (r['plane_id'] ?? '').toString();
                    final q = r['q_0_1'];
                    final c = r['c_0_1'];
                    final qs = r['q_source'];
                    final cs = r['c_source'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text('$role · $plane',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Text('q=$q ($qs)  c=$c ($cs)',
                              style: const TextStyle(fontFamily: 'monospace')),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Stage 1C Checks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1) Save an entry (plane-only). Expect cov ≈ 0.33 per plane.'),
              const SizedBox(height: 6),
              const Text('2) Save an entry with some Planes. Expect cov to rise toward 0.66.'),
              const SizedBox(height: 6),
              const Text('3) Save an entry with Indicators. Expect cov to reach 1.0.'),
              const SizedBox(height: 6),
              Text('4) Confirm epistemics rows exist for roles: ${kCanonRoles.map((r) => r.id).join(', ')} and planes: Internal / External / Output.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required String title, String? subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.6),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: AppTheme.textLight)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, Object? v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: AppTheme.textLight))),
          Expanded(child: Text(v?.toString() ?? 'null', style: const TextStyle(fontFamily: 'monospace'))),
        ],
      ),
    );
  }
}

extension _Take on String {
  String take(int n) => length <= n ? this : substring(0, n) + '…';
}
