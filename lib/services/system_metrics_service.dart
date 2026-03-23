
// lib/services/system_metrics_service.dart
// Phase 4: System dashboard metrics (descriptive only).
//
// Computes conservative daily aggregates from:
// - InputCoverageDaily (cov_entry)
// - RolePlaneEpistemics (q,c sources -> overridden count; w mean)
// - EventLog (refresh/collapse counts)
//
// No prediction. All heuristic values are labeled via calc_rule_id.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/input_coverage_service.dart';
import '../services/event_service.dart';

class SystemMetricsService {
  SystemMetricsService({
    DatabaseHelper? db,
    InputCoverageService? coverageService,
    EventService? eventService,
  })  : _db = db ?? DatabaseHelper.instance,
        _coverage = coverageService ?? InputCoverageService(db: db),
        _events = eventService ?? EventService(db: db);

  final DatabaseHelper _db;
  final InputCoverageService _coverage;
  final EventService _events;

  /// Compute and cache daily system metrics.
  Future<SystemDailyMetrics?> computeDaily(DateTime day, {double lambdaSub = 0.12}) async {
    final date = _fmt(day);
    final db = await _db.database;

    // Coverage
    final cov = await _coverage.computeForDate(day);
    final covEntry = cov?.covEntry;

    // Epistemics
    final epRows = await _db.listRolePlaneEpistemics(date);
    double? wMean;
    int overridden = 0;
    if (epRows.isNotEmpty) {
      double sum = 0;
      int n = 0;
      for (final r in epRows) {
        final q = (r['q_0_1'] as num?)?.toDouble() ?? 0;
        final c = (r['c_0_1'] as num?)?.toDouble() ?? 0;
        sum += (q * c);
        n += 1;
        final qs = (r['q_source'] as String?) ?? 'calc';
        final cs = (r['c_source'] as String?) ?? 'calc';
        if (qs == 'user' || cs == 'user') overridden += 1;
      }
      wMean = n > 0 ? (sum / n) : null;
    }

    // Events counts (same day window)
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    final refreshEvents = await _events.listEvents(start: start, end: end, type: EventType.refresh);
    final collapseEvents = await _events.listEvents(start: start, end: end, type: EventType.collapse);

    // Heuristic k_sub: simple descriptive reactivity = normalized event pressure.
    // label as heuristic_k_sub_v1
    double? kSub;
    final rCount = refreshEvents.length;
    final cCount = collapseEvents.length;
    if (rCount + cCount > 0) {
      kSub = (cCount + 0.5 * rCount).clamp(0, 10).toDouble();
      // Map to 0..1-ish range for display
      kSub = (kSub / 10.0).clamp(0.0, 1.0);
    }

    // Visibility metrics: conservative; reflect how much is measured + how trustworthy.
    // v_vis = covEntry (0..1), v_verif = covEntry * wMean
    final vVis = covEntry;
    final vVerif = (covEntry != null && wMean != null) ? (covEntry * wMean) : null;

    final inputs = <String, Object?>{
      'cov_entry': covEntry,
      'w_mean': wMean,
      'overridden_cells': overridden,
      'refresh_count': rCount,
      'collapse_count': cCount,
      'lambda_sub': lambdaSub,
      'k_sub': kSub,
    };

    final metrics = SystemDailyMetrics(
      date: date,
      covEntry: covEntry,
      wMean: wMean,
      overriddenCells: overridden,
      lambdaSub: lambdaSub,
      kSub: kSub,
      vVis: vVis,
      vVerif: vVerif,
      refreshCount: rCount,
      collapseCount: cCount,
      ruleId: 'system_metrics_v1',
      calcInputsJson: jsonEncode(inputs),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await db.insert('SystemDailyMetrics', metrics.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    return metrics;
  }

  Future<SystemDailyMetrics?> getCached(String date) async {
    final db = await _db.database;
    final rows = await db.query('SystemDailyMetrics',
        where: 'date_yyyy_mm_dd = ?', whereArgs: [date], limit: 1);
    if (rows.isEmpty) return null;
    return SystemDailyMetrics.fromMap(rows.first);
  }

  Future<List<SystemDailyMetrics>> computeRange(DateTime end, int days, {double lambdaSub = 0.12}) async {
    return getRange(end, days, lambdaSub: lambdaSub, force: true);
  }

  /// Range fetch that uses cached rows by default.
  ///
  /// Policy (Phase 4C):
  /// - If a cached row exists for the day, return it unless [force] is true.
  /// - If missing, compute and cache.
  ///
  /// Staleness invalidation hooks (entry/event/epistemics change tracking)
  /// are added in a later patch; for now, the user can force recompute.
  Future<List<SystemDailyMetrics>> getRange(DateTime end, int days,
      {double lambdaSub = 0.12, bool force = false}) async {
    final out = <SystemDailyMetrics>[];
    for (int i = 0; i < days; i++) {
      final d = end.subtract(Duration(days: i));
      final date = _fmt(d);
      SystemDailyMetrics? m;
      if (!force) {
        m = await getCached(date);
      }
      m ??= await computeDaily(d, lambdaSub: lambdaSub);
      if (m != null) out.add(m);
    }
    return out;
  }

  String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
