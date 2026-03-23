// lib/services/input_coverage_service.dart
//
// Coverage (resolution) computation for progressive disclosure input.
// Maps existing taxonomy levels:
//   ROOT.* = Plane
//   L2.*   = Field
//   LEAF.* = Node
//
// Designed for modular future inputs (Dexcom/Fitbit/etc) via InputObservationProvider.

import '../models/models.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../services/entry_service.dart';
import '../database/database_helper.dart';
import '../canon/symbol_governance.dart';

/// Minimal observation metadata used by coverage. This is intentionally small
/// so future providers (wearables, imports) can participate without coupling.
class ObservedMetricSet {
  final Set<String> presentMetricIds; // metric_id present for a given date/entry
  const ObservedMetricSet(this.presentMetricIds);

  bool has(String metricId) => presentMetricIds.contains(metricId);
}

/// Provider abstraction so we can later compose DB + sensor + import sources.
/// For v1, DB is the only provider.
abstract class InputObservationProvider {
  Future<Entry?> getEntryForDate(DateTime date);
  Future<ObservedMetricSet> getObservedMetricsForEntry(int entryId);
}

/// Default provider backed by the local SQLite DB.
class DbObservationProvider implements InputObservationProvider {
  final DatabaseHelper _db;
  DbObservationProvider(this._db);

  @override
  Future<Entry?> getEntryForDate(DateTime date) async {
    final entries = await _db.getEntriesForDateTyped(date);
    if (entries.isEmpty) return null;
    // prefer baseline entry if multiple exist; else most recent
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.first;
  }

  @override
  Future<ObservedMetricSet> getObservedMetricsForEntry(int entryId) async {
    final ids = await _db.getMetricIdsForEntry(entryId);
    return ObservedMetricSet(ids.toSet());
  }
}

class CoverageResult {
  final double covPlaneInternal;
  final double covPlaneExternal;
  final double covPlaneOutput;
  final double covEntry;

  const CoverageResult({
    required this.covPlaneInternal,
    required this.covPlaneExternal,
    required this.covPlaneOutput,
    required this.covEntry,
  });

  // Compatibility aliases (UI uses IN/OUT/BEH naming in some screens)
  double get covIn => covPlaneInternal;
  double get covOut => covPlaneExternal;
  double get covBeh => covPlaneOutput;

  // Compatibility aliases (some screens use ROOT.I/E/O naming)
  double get covPlaneI => covPlaneInternal;
  double get covPlaneE => covPlaneExternal;
  double get covPlaneO => covPlaneOutput;

  Map<String, dynamic> toJson() => {
        'cov_internal': covPlaneInternal,
        'cov_external': covPlaneExternal,
        'cov_output': covPlaneOutput,
        'cov_entry': covEntry,
      };
}

/// Computes coverage using taxonomy structure, not hardcoded 3×3,
/// so taxonomy can evolve without rewriting the algorithm (as long as it stays tree-like).
class InputCoverageService {
  static final InputCoverageService instance = InputCoverageService();

  InputCoverageService({
    InputObservationProvider? provider,
    DatabaseHelper? db,
  })  : _db = db ?? DatabaseHelper.instance,
        _provider = provider ?? DbObservationProvider(db ?? DatabaseHelper.instance);

  final DatabaseHelper _db;
  final InputObservationProvider _provider;

  /// Compute coverage for a calendar date. If no entry exists, returns null.
  Future<CoverageResult?> computeForDate(DateTime date) async {
    final entry = await _provider.getEntryForDate(date);
    if (entry?.id == null) return null;

    final observed = await _provider.getObservedMetricsForEntry(entry!.id!);

    // Planes are the three roots currently used by the app.
    final covI = _computeDomainCoverage('ROOT.I', observed);
    final covE = _computeDomainCoverage('ROOT.E', observed);
    final covO = _computeDomainCoverage('ROOT.O', observed);

    final covEntry = (covI + covE + covO) / 3.0;

    final result = CoverageResult(
      covPlaneInternal: covI,
      covPlaneExternal: covE,
      covPlaneOutput: covO,
      covEntry: covEntry,
    );

    // Optional cache for audit + speed.
    await _db.upsertCoverageDaily(
      date: _yyyyMmDd(date),
      covI: covI,
      covE: covE,
      covO: covO,
      covEntry: covEntry,
      calcRuleId: CanonRuleIds.coverageV1,
      calcInputsJson: '{"source":"MetricValue presence","taxonomy":"LOCKED v1.0"}',
    );

    return result;
  }

  /// Convenience for callers that require coverage to exist.
  /// Throws if no entry exists for the date.
  Future<CoverageResult> computeAndPersistForDate(DateTime date) async {
    final res = await computeForDate(date);
    if (res == null) {
      throw Exception('No entry exists for date ${_yyyyMmDd(date)}');
    }
    return res;
  }

  double _computeDomainCoverage(String rootId, ObservedMetricSet observed) {
    final root = kTaxonomy[rootId];
    if (root == null) return 0.0;

    final planeIds = root.children;
    if (planeIds.isEmpty) return 0.33; // defensive: still treat as plane-only

    final scores = <double>[];
    for (final planeId in planeIds) {
      scores.add(_planeBranchScore(planeId, observed));
    }
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  double _planeBranchScore(String planeId, ObservedMetricSet observed) {
    final plane = kTaxonomy[planeId];
    if (plane == null) return 0.33;

    // Node-entered?
    final indicatorIds = plane.children;
    final anyIndicatorPresent = indicatorIds.any(observed.has);

    if (anyIndicatorPresent) return 1.0;

    // Field-entered?
    if (observed.has(planeId)) return 0.66;

    // Domain-only (domain slider entered; planes/indicators not)
    return 0.33;
  }

  String _yyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
