
// lib/screens/system_dashboard_screen.dart
// Phase 4: System dashboard (descriptive, no forecasting).

import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/system_metrics_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class SystemDashboardScreen extends StatefulWidget {
  const SystemDashboardScreen({super.key});

  @override
  State<SystemDashboardScreen> createState() => _SystemDashboardScreenState();
}

class _SystemDashboardScreenState extends State<SystemDashboardScreen> {
  final _svc = SystemMetricsService();
  DateTime _end = DateTime.now();
  int _days = 14;
  List<SystemDailyMetrics> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.getRange(_end, _days, force: false);
    setState(() => _rows = list);
  }

  Future<void> _recompute() async {
    final list = await _svc.getRange(_end, _days, force: true);
    setState(() => _rows = list);
  }

  String _p(double? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(0)}%';
  String _f(double? x) => x == null ? '—' : x.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final latest = _rows.isNotEmpty ? _rows.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh (cache)',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Recompute (force)',
            onPressed: _recompute,
            icon: const Icon(Icons.replay),
          ),
          if (latest != null)
            IconButton(
              tooltip: 'Show derivation',
              onPressed: () => _showDerivation(latest),
              icon: const Icon(Icons.info_outline),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (latest != null) _summary(latest),
            const SizedBox(height: 12),
            Expanded(child: _table()),
          ],
        ),
      ),
    );
  }

  Widget _summary(SystemDailyMetrics m) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          _kv('cov_entry', _p(m.covEntry)),
          const SizedBox(width: 14),
          _kv('w_mean', _f(m.wMean)),
          const SizedBox(width: 14),
          _kv('v_verif', _f(m.vVerif)),
          const SizedBox(width: 14),
          _kv('override', '${m.overriddenCells ?? 0}'),
          const SizedBox(width: 14),
          _kv('events', '${m.refreshCount ?? 0}/${m.collapseCount ?? 0}'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _table() {
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = _rows[i];
        return ListTile(
          title: Text(m.date),
          subtitle: Text('cov_entry ${_p(m.covEntry)} • w ${_f(m.wMean)} • v_verif ${_f(m.vVerif)}'),
          trailing: Text('Ovr ${m.overriddenCells ?? 0}', style: const TextStyle(color: AppTheme.textLight)),
          onTap: () => _showDerivation(m),
        );
      },
    );
  }

  void _showDerivation(SystemDailyMetrics m) {
    String pretty = '';
    final raw = (m.calcInputsJson ?? '').trim();
    if (raw.isEmpty) {
      pretty = '—';
    } else {
      try {
        final obj = jsonDecode(raw);
        pretty = const JsonEncoder.withIndent('  ').convert(obj);
      } catch (_) {
        pretty = raw; // fallback
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Derivation • ${m.date}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _kv('calc_rule_id', m.ruleId),
                const SizedBox(height: 10),
                const Text('calc_inputs_json', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 420),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      pretty,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.25),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}
