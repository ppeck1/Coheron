// lib/services/entry_service.dart
// Canonical entry access layer.
// All screens MUST use these utilities for "current state".
// No direct DB calls for current-entry lookup outside this file.

import '../database/database_helper.dart';
import '../models/models.dart';
import 'input_coverage_service.dart';
import 'epistemics_service.dart';

class EntryService {
  EntryService._();
  static final EntryService instance = EntryService._();

  final _db = DatabaseHelper.instance;

  /// Most recent entry by created_at (timestamp), any type.
  /// If [within] is provided, only entries created within that window are considered.
  Future<Entry?> getCurrentEntry({Duration? within}) =>
      _db.getCurrentEntry(within: within);

  /// All entries for a specific calendar date, any type.
  Future<List<Entry>> getEntriesForDate(DateTime date) =>
      _db.getEntriesForDateTyped(date);

  /// All entries in an inclusive date range, any type.
  Future<List<Entry>> getEntriesInRange(DateTime start, DateTime end) =>
      _db.getEntriesInRange(start, end);

  /// Recent N entries across all types.
  Future<List<Entry>> getRecentEntries({int limit = 20}) =>
      _db.getRecentEntries(limit: limit);

  /// Save an entry and its metric values atomically.
  /// Returns the new entry ID.
  /// depthLevel is set on the Entry itself before calling.
  Future<int> saveEntryWithMetrics({
    required Entry entry,
    required Map<String, int> metricValues,
    FrequencyComposition? frequency,
    TemperamentComposition? temperament,
    int depthLevel = 1,  // kept for call-site compat; ignored (use entry.depthLevel)
  }) async {
    // Enforce that roots are always present.
    final m = Map<String, int>.from(metricValues);
    for (final domainId in const ['ROOT.I', 'ROOT.E', 'ROOT.O']) {
      m.putIfAbsent(domainId, () => 50);
    }
    // Atomic write: entry + metrics in one transaction.
    final entryId = await _db.saveEntryWithMetricsAtomic(entry, m);

    // Frequency composition is reflection-layer input (sums to 100).
    // Store if provided. This does not affect coherence math.
    if (frequency != null) {
      await _db.upsertFrequencyComposition(entryId, frequency.normalized());
    }

    // Temperament composition is reflection-layer input (sums to 100).
    // Store if provided. This does not affect coherence math.
    if (temperament != null) {
      await _db.upsertTemperamentComposition(entryId, temperament.normalized());
    }

    // Post-save substrate updates (non-visual, auditable):
    // - coverage cache
    // - default epistemics (q/c) derived from coverage when absent
    final date = DateTime.parse(entry.date);
    await InputCoverageService(db: _db).computeForDate(date);
    await EpistemicsService(db: _db).ensureDefaultsForDate(date);

    return entryId;
  }


  /// Update an existing entry and overwrite its metric values atomically.
  Future<void> updateEntryWithMetrics({
    required int entryId,
    required Entry entry,
    required Map<String, int> metricValues,
    FrequencyComposition? frequency,
    TemperamentComposition? temperament,
  }) async {
    final m = Map<String, int>.from(metricValues);
    for (final domainId in const ['ROOT.I', 'ROOT.E', 'ROOT.O']) {
      m.putIfAbsent(domainId, () => 50);
    }
    await _db.updateEntryWithMetricsAtomic(entryId: entryId, entry: entry, values: m);

    if (frequency != null) {
      await _db.upsertFrequencyComposition(entryId, frequency.normalized());
    }

    if (temperament != null) {
      await _db.upsertTemperamentComposition(entryId, temperament.normalized());
    }
  }

  /// Previous entry before the given timestamp (any type).
  Future<Entry?> getPreviousEntry(String timestamp) =>
      _db.getPreviousEntryByTimestamp(timestamp);

  /// Filtered history (Phase 2).
  Future<List<Entry>> searchEntries({
    DateTime? start,
    DateTime? end,
    List<EntryType>? types,
    List<int>? depths,
    String? text,
    int limit = 200,
  }) => _db.searchEntries(
        start: start, end: end, types: types, depths: depths, text: text, limit: limit);

  /// Load metric values for a given entry.
  Future<Map<String, int>> getMetricValues(int entryId) =>
      _db.getMetricValuesForEntry(entryId);

  // ─── Tags ────────────────────────────────────────────────────────────────

  Future<void> setTagsForEntry(int entryId, List<String> tags) =>
      _db.setTagsForEntry(entryId, tags);

  Future<List<String>> getTagsForEntry(int entryId) =>
      _db.getTagsForEntry(entryId);

  Future<List<String>> getAllTags({int limit = 200}) =>
      _db.getAllTags(limit: limit);

  Future<List<int>> getEntryIdsByTagClauses({
    List<String> includeTags = const [],
    List<String> excludeTags = const [],
  }) => _db.getEntryIdsByTagClauses(includeTags: includeTags, excludeTags: excludeTags);

  /// Time-series for a single metric, within a date range.
  Future<List<Map<String, dynamic>>> getMetricSeries(
          String metricId, DateTime start, DateTime end) =>
      _db.getMetricSeries(metricId, start, end);

  Future<List<Map<String, dynamic>>> getMetricSeriesForEntryIds(
          String metricId, DateTime start, DateTime end, List<int> entryIds) =>
      _db.getMetricSeriesForEntryIds(metricId, start, end, entryIds);

  // ─── Frequency composition ───────────────────────────────────────────────

  Future<FrequencyComposition?> getFrequencyComposition(int entryId) =>
      _db.getFrequencyComposition(entryId);

  Future<void> setFrequencyComposition(int entryId, FrequencyComposition fc) =>
      _db.upsertFrequencyComposition(entryId, fc.normalized());

  /// Convenience: fetch the most recent saved composition (any entry).
  Future<FrequencyComposition?> getLastKnownFrequencyComposition() async {
    final entries = await getRecentEntries(limit: 50);
    for (final e in entries) {
      if (e.id == null) continue;
      final fc = await _db.getFrequencyComposition(e.id!);
      if (fc != null && fc.total == 100) return fc;
    }
    return null;
  }

  // ─── Plane aux ───────────────────────────────────────────────────────────

  Future<PlaneAux?> getPlaneAux(int entryId, String planeId) =>
      _db.getPlaneAux(entryId, planeId);

  Future<void> setPlaneAux(int entryId, PlaneAux aux) =>
      _db.upsertPlaneAux(entryId, aux);

  // ─── Derived daily plane metrics ─────────────────────────────────────────

  static const int windowDaysDefault = 14;
  static const int minPointsRequired = 7;
  static const double pressureHighThresholdH = 7.0;
  static const double epsStableStep = 0.5;
  static const double volMax = 3.0;
  static const double slopeMax = 0.5;

  /// Fetch derived metrics for a date; compute/cache if missing.
  /// Planes are ROOT.I/E/O mapped to 0..10 pressure (ROOT value / 10).
  Future<Map<String, DerivedDailyPlaneMetrics>> getDerivedForDate(String date) async {
    final out = <String, DerivedDailyPlaneMetrics>{};
    for (final pid in const ['ROOT.I', 'ROOT.E', 'ROOT.O']) {
      final existing = await _db.getDerivedDailyPlaneMetrics(date, pid);
      if (existing != null) {
        out[pid] = existing;
      }
    }
    if (out.length == 3) return out;
    await _computeAndCacheDerivedAround(date, windowDays: windowDaysDefault);
    for (final pid in const ['ROOT.I', 'ROOT.E', 'ROOT.O']) {
      final m = await _db.getDerivedDailyPlaneMetrics(date, pid);
      if (m != null) out[pid] = m;
    }
    return out;
  }

  Future<void> _computeAndCacheDerivedAround(String endDate, {int windowDays = windowDaysDefault}) async {
    // Compute for the endDate only (Phase 2 minimal). Extend to rolling cache later.
    final end = DateTime.parse(endDate);
    final start = end.subtract(Duration(days: windowDays - 1));

    for (final pid in const ['ROOT.I', 'ROOT.E', 'ROOT.O']) {
      final series = await _db.getMetricSeries(pid, start, end);
      // series rows: {date, value}
      final vals = <double>[];
      final dates = <String>[];
      for (final r in series) {
        final v = (r['value'] as num).toDouble() / 10.0; // 0..10
        vals.add(v);
        dates.add((r['date'] as String?) ?? '');
      }

      final n = vals.length;
      if (n < minPointsRequired) {
        final m = DerivedDailyPlaneMetrics(
          date: endDate,
          planeId: pid,
          windowDays: windowDays,
          nPointsUsed: n,
          dwellHiRatio: null,
          dwellHiDays: null,
          volRawStddev: null,
          volScore0_10: null,
          steadinessScore0_10: null,
          trendRawSlopePerDay: null,
          trendScore: null,
          trendAbs: null,
          persistenceRatio: null,
          persistenceScore: null,
          hasMinPoints: false,
          isEstimate: true,
        );
        await _db.upsertDerivedDailyPlaneMetrics(m);
        continue;
      }

      final volRaw = _stddev(vals);
      final volScore = 10.0 * _clamp(volRaw / volMax, 0, 1);
      final steadiness = 10.0 - volScore; // per your definition

      // dwell_hi
      final dwellCount = vals.where((x) => x >= pressureHighThresholdH).length;
      final dwellRatio = dwellCount / n;

      // trend slope via simple linear regression over index days
      final slope = _linregSlope(vals);
      final trendScore = 10.0 * _clamp(slope / slopeMax, -1, 1);
      final trendAbs = trendScore.abs();

      // persistence: stable steps ratio
      int stableSteps = 0;
      for (int i = 1; i < vals.length; i++) {
        if ((vals[i] - vals[i - 1]).abs() < epsStableStep) stableSteps++;
      }
      final persistenceRatio = stableSteps / (n - 1);
      final persistenceScore = 10.0 * persistenceRatio;

      final m = DerivedDailyPlaneMetrics(
        date: endDate,
        planeId: pid,
        windowDays: windowDays,
        nPointsUsed: n,
        dwellHiRatio: dwellRatio,
        dwellHiDays: dwellCount,
        volRawStddev: volRaw,
        volScore0_10: volScore,
        steadinessScore0_10: steadiness,
        trendRawSlopePerDay: slope,
        trendScore: trendScore,
        trendAbs: trendAbs,
        persistenceRatio: persistenceRatio,
        persistenceScore: persistenceScore,
        hasMinPoints: true,
        isEstimate: false,
      );
      await _db.upsertDerivedDailyPlaneMetrics(m);
    }
  }

  /// Compute statistical summary for a metric series.
  MetricStats computeStats(List<Map<String, dynamic>> series) {
    if (series.isEmpty) return MetricStats.empty();
    final vals = series.map((r) => (r['value'] as num).toDouble()).toList();
    final n = vals.length.toDouble();
    final mean = vals.reduce((a, b) => a + b) / n;
    final variance = vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
    final sigma = variance <= 0 ? 0.0 : variance < 1e-10 ? 0.0 : _sqrt(variance);

    // Trend: simple linear regression slope β = Cov(t, X) / Var(t)
    final ts = List.generate(vals.length, (i) => i.toDouble());
    final tMean = ts.reduce((a, b) => a + b) / n;
    double covTX = 0, varT = 0;
    for (int i = 0; i < vals.length; i++) {
      covTX += (ts[i] - tMean) * (vals[i] - mean);
      varT  += (ts[i] - tMean) * (ts[i] - tMean);
    }
    final beta = varT <= 1e-10 ? 0.0 : covTX / varT;

    // Dwell: fraction of time above mean + k*sigma (k=0.5)
    const k = 0.5;
    final threshold = mean + k * sigma;
    final dwellCount = vals.where((v) => v > threshold).length;
    final dwell = dwellCount / vals.length;

    // Persistence: mean run length above mean
    int runLen = 0, runCount = 0, curRun = 0;
    for (final v in vals) {
      if (v > mean) {
        curRun++;
      } else {
        if (curRun > 0) { runLen += curRun; runCount++; curRun = 0; }
      }
    }
    if (curRun > 0) { runLen += curRun; runCount++; }
    final persistence = runCount > 0 ? runLen / runCount : 0.0;

    return MetricStats(
      n: vals.length, mean: mean, sigma: sigma,
      beta: beta, dwell: dwell, persistence: persistence,
      min: vals.reduce((a, b) => a < b ? a : b),
      max: vals.reduce((a, b) => a > b ? a : b),
    );
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x / 2;
    for (int i = 0; i < 50; i++) r = (r + x / r) / 2;
    return r;
  }

  static double _clamp(double x, double lo, double hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
  }

  static double _stddev(List<double> xs) {
    final n = xs.length;
    if (n <= 1) return 0;
    final mean = xs.reduce((a, b) => a + b) / n;
    double s = 0;
    for (final x in xs) {
      final d = x - mean;
      s += d * d;
    }
    final varPop = s / n;
    return varPop <= 0 ? 0 : _sqrt(varPop);
  }

  static double _linregSlope(List<double> xs) {
    final n = xs.length;
    if (n <= 1) return 0;
    final tMean = (n - 1) / 2.0;
    final xMean = xs.reduce((a, b) => a + b) / n;
    double cov = 0;
    double varT = 0;
    for (int i = 0; i < n; i++) {
      final t = i.toDouble();
      cov += (t - tMean) * (xs[i] - xMean);
      varT += (t - tMean) * (t - tMean);
    }
    if (varT.abs() < 1e-9) return 0;
    return cov / varT;
  }
}

// ─── Stats model ──────────────────────────────────────────────────────────────

class MetricStats {
  final int n;
  final double mean;
  final double sigma;     // volatility (std dev)
  final double beta;      // trend slope
  final double dwell;     // fraction above mean + 0.5σ
  final double persistence; // mean run length above mean
  final double min;
  final double max;

  const MetricStats({
    required this.n, required this.mean, required this.sigma,
    required this.beta, required this.dwell, required this.persistence,
    required this.min, required this.max,
  });

  factory MetricStats.empty() => const MetricStats(
    n: 0, mean: 0, sigma: 0, beta: 0, dwell: 0, persistence: 0, min: 0, max: 0);

  bool get hasData => n > 0;
}
