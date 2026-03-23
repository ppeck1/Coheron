// lib/models/models.dart
// v5.1 — taxonomy-based coherence model.
// Legacy area fields removed. MetricValue is the measurement primitive.
// overall_score  = mean(ROOT.I, ROOT.E, ROOT.O) — computed at save time.
// completion_pct = (metrics_saved / 39) * 100    — computed at save time.

// ─── Entry type ───────────────────────────────────────────────────────────────

enum EntryType { baseline, event, retro }

extension EntryTypeX on EntryType {
  String get value => name;
  static EntryType parse(String? s) =>
      EntryType.values.firstWhere((e) => e.name == (s ?? ''),
          orElse: () => EntryType.baseline);
}

// ─── Entry ────────────────────────────────────────────────────────────────────

class Entry {
  final int? id;
  final String date;
  final String timestamp;
  final EntryType entryType;
  final String? eventLabel;
  /// overall_score: mean of ROOT.I, ROOT.E, ROOT.O values (0-100).
  final double overallScore;
  /// completion_percent: (metric_count / 39) * 100.
  final double completionPercent;
  final int depthLevel; // 1=roots only, 2=any L2, 3=any leaf
  final int updatedAt; // unix ms
  final int? deletedAt;
  final bool isDeleted;

  Entry({
    this.id,
    required this.date,
    required this.timestamp,
    this.entryType = EntryType.baseline,
    this.eventLabel,
    required this.overallScore,
    required this.completionPercent,
    this.depthLevel = 1,
    int? updatedAt,
    this.deletedAt,
    this.isDeleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date':               date,
        'timestamp':          timestamp,
        'entry_type':         entryType.value,
        'event_label':        eventLabel,
        'overall_score':      overallScore,
        'completion_percent': completionPercent,
        'depth_level':        depthLevel,
        'is_deleted':         isDeleted ? 1 : 0,
        'deleted_at':         deletedAt,
        'updated_at':         updatedAt,
      };

  factory Entry.fromMap(Map<String, dynamic> m) => Entry(
        id:                m['id'] as int?,
        date:              m['date'] as String,
        timestamp:         m['timestamp'] as String,
        entryType:         EntryTypeX.parse(m['entry_type'] as String?),
        eventLabel:        m['event_label'] as String?,
        overallScore:      (m['overall_score'] as num?)?.toDouble() ?? 0,
        completionPercent: (m['completion_percent'] as num?)?.toDouble() ?? 0,
        depthLevel:        (m['depth_level'] as num?)?.toInt() ?? 1,
        updatedAt:         (m['updated_at'] as num?)?.toInt(),
        deletedAt:         (m['deleted_at'] as num?)?.toInt(),
        isDeleted:         ((m['is_deleted'] as num?)?.toInt() ?? 0) == 1,
      );

  Entry copyWith({int? id, int? depthLevel, int? updatedAt, int? deletedAt, bool? isDeleted}) => Entry(
        id:                id ?? this.id,
        date:              date,
        timestamp:         timestamp,
        entryType:         entryType,
        eventLabel:        eventLabel,
        overallScore:      overallScore,
        completionPercent: completionPercent,
        depthLevel:        depthLevel ?? this.depthLevel,
        updatedAt:         updatedAt ?? this.updatedAt,
        deletedAt:         deletedAt ?? this.deletedAt,
        isDeleted:         isDeleted ?? this.isDeleted,
      );
}

// ─── Frequency composition (measured; user-entered; sums to 100) ──────────────

class FrequencyComposition {
  final int sense;
  final int maintain;
  final int explore;
  final int enforce;
  final int updatedAt;

  FrequencyComposition({
    required this.sense,
    required this.maintain,
    required this.explore,
    required this.enforce,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  int get total => sense + maintain + explore + enforce;

  FrequencyComposition normalized() {
    final t = total;
    if (t == 100) return this;
    if (t <= 0) {
      return FrequencyComposition(sense: 25, maintain: 25, explore: 25, enforce: 25);
    }
    // Scale to 100 and distribute rounding error deterministically.
    final s = (sense * 100 / t).floor();
    final m = (maintain * 100 / t).floor();
    final e = (explore * 100 / t).floor();
    var f = (enforce * 100 / t).floor();
    var sum = s + m + e + f;
    // Add remainder to enforce (last axis) to keep deterministic.
    f += (100 - sum);
    return FrequencyComposition(sense: s, maintain: m, explore: e, enforce: f, updatedAt: updatedAt);
  }

  Map<String, Object?> toMap(int entryId) => {
        'entry_id': entryId,
        'sense': sense,
        'maintain': maintain,
        'explore': explore,
        'enforce': enforce,
        'updated_at': updatedAt,
      };

  factory FrequencyComposition.fromMap(Map<String, Object?> m) => FrequencyComposition(
        sense: (m['sense'] as int?) ?? 0,
        maintain: (m['maintain'] as int?) ?? 0,
        explore: (m['explore'] as int?) ?? 0,
        enforce: (m['enforce'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as int?),
      );
}

/// 4-way temperament composition. Reflection-layer input: sums to 100.
/// Stored per entry.
class TemperamentComposition {
  final int choleric;
  final int sanguine;
  final int melancholic;
  final int pragmatic;

  const TemperamentComposition({
    required this.choleric,
    required this.sanguine,
    required this.melancholic,
    required this.pragmatic,
  });

  int get sum => choleric + sanguine + melancholic + pragmatic;

  TemperamentComposition normalized() {
    final s = sum;
    if (s == 0) return const TemperamentComposition(choleric: 25, sanguine: 25, melancholic: 25, pragmatic: 25);
    int scale(int v) => ((v / s) * 100).round();
    var c = scale(choleric);
    var sa = scale(sanguine);
    var m = scale(melancholic);
    var p = 100 - c - sa - m;
    return TemperamentComposition(choleric: c, sanguine: sa, melancholic: m, pragmatic: p);
  }

  Map<String, dynamic> toMap(int entryId) => {
        'entry_id': entryId,
        'choleric': choleric,
        'sanguine': sanguine,
        'melancholic': melancholic,
        'pragmatic': pragmatic,
        'updated_at': DateTime.now().toIso8601String(),
      };

  static TemperamentComposition fromRow(Map<String, Object?> row) {
    return TemperamentComposition(
      choleric: (row['choleric'] as int?) ?? 25,
      sanguine: (row['sanguine'] as int?) ?? 25,
      melancholic: (row['melancholic'] as int?) ?? 25,
      pragmatic: (row['pragmatic'] as int?) ?? 25,
    ).normalized();
  }
}

/// A single dated FrequencyComposition point for charting.
///
/// Note: `day` is normalized to local midnight when produced by the DB layer.
class FrequencyPoint {
  final DateTime day;
  final int entryId;
  final int sense;
  final int maintain;
  final int explore;
  final int enforce;

  const FrequencyPoint({
    required this.day,
    required this.entryId,
    required this.sense,
    required this.maintain,
    required this.explore,
    required this.enforce,
  });
}

// ─── Plane aux (optional measured fields for roots-as-planes) ─────────────────

class PlaneAux {
  final String planeId;
  final double? room0_10;
  final double? qFacts0_10;
  final double? qMeaning0_10;

  const PlaneAux({
    required this.planeId,
    this.room0_10,
    this.qFacts0_10,
    this.qMeaning0_10,
  });

  double? get qc {
    final qf = qFacts0_10;
    final qm = qMeaning0_10;
    if (qf == null || qm == null) return null;
    return (qf.clamp(0, 10) / 10.0) * (qm.clamp(0, 10) / 10.0); // 0..1
  }

  Map<String, Object?> toMap(int entryId) => {
        'entry_id': entryId,
        'plane_id': planeId,
        'room_0_10': room0_10,
        'q_facts_0_10': qFacts0_10,
        'q_meaning_0_10': qMeaning0_10,
      };

  factory PlaneAux.fromMap(Map<String, Object?> m) => PlaneAux(
        planeId: (m['plane_id'] as String?) ?? '',
        room0_10: (m['room_0_10'] as num?)?.toDouble(),
        qFacts0_10: (m['q_facts_0_10'] as num?)?.toDouble(),
        qMeaning0_10: (m['q_meaning_0_10'] as num?)?.toDouble(),
      );
}

// ─── Derived daily plane metrics (cached; derived only) ───────────────────────

class DerivedDailyPlaneMetrics {
  final String date; // YYYY-MM-DD
  final String planeId;
  final int windowDays;
  final int nPointsUsed;
  final double? dwellHiRatio;
  final int? dwellHiDays;
  final double? volRawStddev;
  final double? volScore0_10;
  final double? steadinessScore0_10;
  final double? trendRawSlopePerDay;
  final double? trendScore; // -10..+10
  final double? trendAbs;
  final double? persistenceRatio;
  final double? persistenceScore;
  final bool hasMinPoints;
  final bool isEstimate;

  const DerivedDailyPlaneMetrics({
    required this.date,
    required this.planeId,
    required this.windowDays,
    required this.nPointsUsed,
    required this.dwellHiRatio,
    required this.dwellHiDays,
    required this.volRawStddev,
    required this.volScore0_10,
    required this.steadinessScore0_10,
    required this.trendRawSlopePerDay,
    required this.trendScore,
    required this.trendAbs,
    required this.persistenceRatio,
    required this.persistenceScore,
    required this.hasMinPoints,
    required this.isEstimate,
  });

  Map<String, Object?> toMap() => {
        'date_yyyy_mm_dd': date,
        'plane_id': planeId,
        'window_days': windowDays,
        'n_points_used': nPointsUsed,
        'dwell_hi_ratio': dwellHiRatio,
        'dwell_hi_days': dwellHiDays,
        'vol_raw_stddev': volRawStddev,
        'vol_score_0_10': volScore0_10,
        'steadiness_score_0_10': steadinessScore0_10,
        'trend_raw_slope_per_day': trendRawSlopePerDay,
        'trend_score': trendScore,
        'trend_abs': trendAbs,
        'persistence_ratio': persistenceRatio,
        'persistence_score': persistenceScore,
        'has_min_points': hasMinPoints ? 1 : 0,
        'is_estimate': isEstimate ? 1 : 0,
      };

  factory DerivedDailyPlaneMetrics.fromMap(Map<String, Object?> m) => DerivedDailyPlaneMetrics(
        date: (m['date_yyyy_mm_dd'] as String?) ?? '',
        planeId: (m['plane_id'] as String?) ?? '',
        windowDays: (m['window_days'] as int?) ?? 14,
        nPointsUsed: (m['n_points_used'] as int?) ?? 0,
        dwellHiRatio: (m['dwell_hi_ratio'] as num?)?.toDouble(),
        dwellHiDays: (m['dwell_hi_days'] as int?),
        volRawStddev: (m['vol_raw_stddev'] as num?)?.toDouble(),
        volScore0_10: (m['vol_score_0_10'] as num?)?.toDouble(),
        steadinessScore0_10: (m['steadiness_score_0_10'] as num?)?.toDouble(),
        trendRawSlopePerDay: (m['trend_raw_slope_per_day'] as num?)?.toDouble(),
        trendScore: (m['trend_score'] as num?)?.toDouble(),
        trendAbs: (m['trend_abs'] as num?)?.toDouble(),
        persistenceRatio: (m['persistence_ratio'] as num?)?.toDouble(),
        persistenceScore: (m['persistence_score'] as num?)?.toDouble(),
        hasMinPoints: ((m['has_min_points'] as int?) ?? 0) == 1,
        isEstimate: ((m['is_estimate'] as int?) ?? 0) == 1,
      );
}

// ─── Tag ──────────────────────────────────────────────────────────────────────

class Tag {
  final int? id;
  final int entryId;
  final String tagName;

  const Tag({this.id, required this.entryId, required this.tagName});

  factory Tag.fromMap(Map<String, dynamic> m) => Tag(
        id:      m['id'] as int?,
        entryId: m['entry_id'] as int,
        tagName: m['tag_name'] as String,
      );
}

// ─── Planar math primitives (proof-of-concept) ───────────────────────────────
//
// These are intentionally small and deterministic. They enable tri-state
// constraint composition (include / exclude / neutral) without turning tags into
// "meaning".

enum Trinary { exclude, neutral, include }

extension TrinaryX on Trinary {
  int get d => switch (this) {
        Trinary.exclude => -1,
        Trinary.neutral => 0,
        Trinary.include => 1,
      };

  Trinary next() => switch (this) {
        Trinary.neutral => Trinary.include,
        Trinary.include => Trinary.exclude,
        Trinary.exclude => Trinary.neutral,
      };

  String get glyph => switch (this) {
        Trinary.exclude => '−',
        Trinary.neutral => '·',
        Trinary.include => '+',
      };
}

/// A single constraint clause for filtering.
class TagClause {
  final String tag;
  Trinary state;
  TagClause({required this.tag, this.state = Trinary.neutral});
}

// ─── Vital ────────────────────────────────────────────────────────────────────

enum VitalType { bp, hr, temp, weight, glucose, sleep, custom }

extension VitalTypeX on VitalType {
  String get label => switch (this) {
        VitalType.bp      => 'Blood Pressure',
        VitalType.hr      => 'Heart Rate',
        VitalType.temp    => 'Temperature',
        VitalType.weight  => 'Weight',
        VitalType.glucose => 'Glucose',
        VitalType.sleep   => 'Sleep',
        VitalType.custom  => 'Custom',
      };
  static VitalType parse(String? s) =>
      VitalType.values.firstWhere((e) => e.name == (s ?? ''),
          orElse: () => VitalType.custom);
}

class Vital {
  final String id;
  final int? entryId;
  final String date;
  final String timestamp;
  final VitalType type;
  final String? label;
  final double? value1, value2, value3;
  final String? unit, note, source;

  const Vital({
    required this.id,
    this.entryId,
    required this.date,
    required this.timestamp,
    required this.type,
    this.label,
    this.value1,
    this.value2,
    this.value3,
    this.unit,
    this.note,
    this.source = 'manual',
  });

  Map<String, dynamic> toMap() => {
        'id':        id,
        'entry_id':  entryId,
        'date':      date,
        'timestamp': timestamp,
        'type':      type.name,
        'label':     label,
        'value1':    value1,
        'value2':    value2,
        'value3':    value3,
        'unit':      unit,
        'note':      note,
        'source':    source ?? 'manual',
      };

  factory Vital.fromMap(Map<String, dynamic> m) => Vital(
        id:        m['id'] as String,
        entryId:   m['entry_id'] as int?,
        date:      m['date'] as String,
        timestamp: m['timestamp'] as String,
        type:      VitalTypeX.parse(m['type'] as String?),
        label:     m['label'] as String?,
        value1:    (m['value1'] as num?)?.toDouble(),
        value2:    (m['value2'] as num?)?.toDouble(),
        value3:    (m['value3'] as num?)?.toDouble(),
        unit:      m['unit'] as String?,
        note:      m['note'] as String?,
        source:    m['source'] as String?,
      );
}

// ─── Signal (Patterns — Phase 2) ─────────────────────────────────────────────

enum SignalSeverity { info, watch, warn }

class Signal {
  final String title;
  final String body;
  final SignalSeverity severity;
  final String? metricId;
  final int? entryId;
  // Optional fields used by some UI components for explanatory detail.
  // These remain purely descriptive and are safe to omit.
  final String triggerReason;
  final List<String> contributingFactors;

  const Signal({
    required this.title,
    required this.body,
    this.severity = SignalSeverity.info,
    this.metricId,
    this.entryId,
    this.triggerReason = '',
    this.contributingFactors = const <String>[],
  });
}


// ─── Events (Phase 3B) ─────────────────────────────────────────────────────


enum EventType { qualifying, refresh, collapse, note }

extension EventTypeX on EventType {
  String get value => name;
  static EventType parse(String? s) =>
      EventType.values.firstWhere((e) => e.name == (s ?? ''),
          orElse: () => EventType.note);
}

class EventRecord {
  final int? id;
  final EventType type;
  final int timestampMs;
  final String title;
  final String? notes;
  final String source; // user|system|import
  final String? calcRuleId;
  final String? calcInputsJson;

  const EventRecord({
    this.id,
    required this.type,
    required this.timestampMs,
    required this.title,
    this.notes,
    this.source = 'user',
    this.calcRuleId,
    this.calcInputsJson,
  });

  String get dateYyyyMmDd {
    final d = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'event_id': id,
    'event_type': type.value,
    'timestamp_ms': timestampMs,
    'title': title,
    'notes': notes,
    'source': source,
    'calc_rule_id': calcRuleId,
    'calc_inputs_json': calcInputsJson,
  };

  factory EventRecord.fromMap(Map<String, Object?> m) => EventRecord(
    id: (m['event_id'] as int?),
    type: EventTypeX.parse(m['event_type'] as String?),
    timestampMs: (m['timestamp_ms'] as int?) ?? 0,
    title: (m['title'] as String?) ?? '',
    notes: (m['notes'] as String?),
    source: (m['source'] as String?) ?? 'user',
    calcRuleId: (m['calc_rule_id'] as String?),
    calcInputsJson: (m['calc_inputs_json'] as String?),
  );
}

class TagSummary {
  final String tag;
  final int count;
  const TagSummary({required this.tag, required this.count});
}

// ─── System daily metrics (Phase 4) ───────────────────────────────────────

class SystemDailyMetrics {
  final String date; // YYYY-MM-DD
  final double? covEntry;
  final double? wMean;
  final int? overriddenCells;
  final double? lambdaSub;
  final double? kSub;
  final double? vVis;
  final double? vVerif;
  final int? refreshCount;
  final int? collapseCount;
  final String ruleId;
  final String? calcInputsJson;
  final int updatedAtMs;

  const SystemDailyMetrics({
    required this.date,
    required this.covEntry,
    required this.wMean,
    required this.overriddenCells,
    required this.lambdaSub,
    required this.kSub,
    required this.vVis,
    required this.vVerif,
    required this.refreshCount,
    required this.collapseCount,
    this.ruleId = 'system_metrics_v1',
    this.calcInputsJson,
    required this.updatedAtMs,
  });

  Map<String, Object?> toMap() => {
    'date_yyyy_mm_dd': date,
    'cov_entry': covEntry,
    'w_mean': wMean,
    'overridden_cells': overriddenCells,
    'lambda_sub': lambdaSub,
    'k_sub': kSub,
    'v_vis': vVis,
    'v_verif': vVerif,
    'refresh_count': refreshCount,
    'collapse_count': collapseCount,
    'calc_rule_id': ruleId,
    'calc_inputs_json': calcInputsJson,
    'updated_at_ms': updatedAtMs,
  };

  factory SystemDailyMetrics.fromMap(Map<String, Object?> m) => SystemDailyMetrics(
    date: (m['date_yyyy_mm_dd'] as String?) ?? '',
    covEntry: (m['cov_entry'] as num?)?.toDouble(),
    wMean: (m['w_mean'] as num?)?.toDouble(),
    overriddenCells: (m['overridden_cells'] as int?),
    lambdaSub: (m['lambda_sub'] as num?)?.toDouble(),
    kSub: (m['k_sub'] as num?)?.toDouble(),
    vVis: (m['v_vis'] as num?)?.toDouble(),
    vVerif: (m['v_verif'] as num?)?.toDouble(),
    refreshCount: (m['refresh_count'] as int?),
    collapseCount: (m['collapse_count'] as int?),
    ruleId: (m['calc_rule_id'] as String?) ?? 'system_metrics_v1',
    calcInputsJson: (m['calc_inputs_json'] as String?),
    updatedAtMs: (m['updated_at_ms'] as int?) ?? 0,
  );
}
