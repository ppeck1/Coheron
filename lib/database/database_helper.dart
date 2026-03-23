// lib/database/database_helper.dart
// v5.1: Minimal schema for Phase 0/1.
// Tables: Entry, MetricValue, Tag, Vital only.
// Legacy tables (pre-v5) are dropped on upgrade. See _onUpgrade.
// overall_score computed deterministically from ROOT values at save time.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import '../models/series_spec.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;
  static const _dbVersion = 12; // v12: TemperamentComposition (per-entry) + input UX hardening

  Future<Database> get database async => _db ??= await _initDb();

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'coheron.db');
    // IMPORTANT: onOpen calls _createAllTables to prevent "missing table" errors
    // when a prior build shipped without some IF NOT EXISTS tables.
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // Defensive, idempotent schema healing.
        // Rationale: older builds may have shipped without some tables/columns.
        // We must not block writes when evolving the substrate.
        await _createAllTables(db);
        await _ensureSubstrateSchema(db);
      },
    );
  }

  Future<void> _onCreate(Database db, int v) async {
    await _createAllTables(db);
    await _ensureSubstrateSchema(db);
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Always safe: create any missing tables, add any missing columns
    await _createAllTables(db);
    await _ensureSubstrateSchema(db);

    // Add depth_level if upgrading from pre-v5
    try {
      await db.execute(
          'ALTER TABLE Entry ADD COLUMN depth_level INTEGER DEFAULT 1');
    } catch (_) {}

    // Add is_deleted if upgrading from pre-v5
    try {
      await db.execute(
          'ALTER TABLE Entry ADD COLUMN is_deleted INTEGER DEFAULT 0');
    } catch (_) {}

    // Add deleted_at / updated_at (Phase 2)
    try {
      await db.execute('ALTER TABLE Entry ADD COLUMN deleted_at INTEGER');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE Entry ADD COLUMN updated_at INTEGER');
      // Backfill updated_at from timestamp if possible
      try {
        await db.execute("UPDATE Entry SET updated_at = CAST(strftime('%s', timestamp) AS INTEGER) * 1000 WHERE updated_at IS NULL OR updated_at = 0");
      } catch (_) {}
    } catch (_) {}

    // Create MetricValue if upgrading from pre-v5
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_metric_entry ON MetricValue(entry_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_metric_metric ON MetricValue(metric_id)');
    } catch (_) {}

    // Drop tables removed in v6 (safe — data not needed)
    if (oldV < 6) {
      // Drop legacy tables from pre-v5 schema (safe; no data migration needed)
      for (final legacy in [
        'ReflectionPrompt', 'ConstraintEntry', 'EventConstraintTag',
        'ObjectiveMetric', 'DerivedSystemMetrics', 'DailyStat', 'CustomTag',
      ]) {
        try { await db.execute('DROP TABLE IF EXISTS $legacy'); } catch (_) {}
      }
    }

    // v8: Tag join-table + migration from legacy Tag table.
    if (oldV < 8) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS TagDef (
            id    INTEGER PRIMARY KEY AUTOINCREMENT,
            name  TEXT NOT NULL UNIQUE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS EntryTag (
            entry_id INTEGER NOT NULL,
            tag_id   INTEGER NOT NULL,
            PRIMARY KEY (entry_id, tag_id),
            FOREIGN KEY (entry_id) REFERENCES Entry(id),
            FOREIGN KEY (tag_id) REFERENCES TagDef(id)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entrytag_entry ON EntryTag(entry_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entrytag_tag ON EntryTag(tag_id)');
      } catch (_) {}

      // Migrate Tag(entry_id, tag_name) → TagDef + EntryTag
      try {
        final legacyTags = await db.query('Tag');
        for (final r in legacyTags) {
          final entryId = r['entry_id'] as int?;
          final name = (r['tag_name'] as String?)?.trim();
          if (entryId == null || name == null || name.isEmpty) continue;
          // Upsert TagDef
          await db.insert('TagDef', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
          final tagDef = await db.query('TagDef', where: 'name = ?', whereArgs: [name], limit: 1);
          if (tagDef.isEmpty) continue;
          final tagId = tagDef.first['id'] as int;
          await db.insert(
            'EntryTag',
            {'entry_id': entryId, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      } catch (_) {}
    }

    // v9: FrequencyComposition + PlaneAux + DerivedDailyPlaneMetrics
    if (oldV < 9) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS FrequencyComposition (
            entry_id   INTEGER PRIMARY KEY,
            sense      INTEGER NOT NULL,
            maintain   INTEGER NOT NULL,
            explore    INTEGER NOT NULL,
            enforce    INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(entry_id) REFERENCES Entry(id)
          )
        ''');
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS PlaneAux (
            entry_id      INTEGER NOT NULL,
            plane_id      TEXT NOT NULL,
            room_0_10     REAL,
            q_facts_0_10  REAL,
            q_meaning_0_10 REAL,
            PRIMARY KEY(entry_id, plane_id),
            FOREIGN KEY(entry_id) REFERENCES Entry(id)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_planeaux_entry ON PlaneAux(entry_id)');
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS DerivedDailyPlaneMetrics (
            date_yyyy_mm_dd      TEXT NOT NULL,
            plane_id             TEXT NOT NULL,
            window_days          INTEGER NOT NULL,
            n_points_used        INTEGER NOT NULL,
            dwell_hi_ratio       REAL,
            dwell_hi_days        INTEGER,
            vol_raw_stddev       REAL,
            vol_score_0_10       REAL,
            steadiness_score_0_10 REAL,
            trend_raw_slope_per_day REAL,
            trend_score          REAL,
            trend_abs            REAL,
            persistence_ratio    REAL,
            persistence_score    REAL,
            has_min_points       INTEGER NOT NULL,
            is_estimate          INTEGER NOT NULL,
            PRIMARY KEY(date_yyyy_mm_dd, plane_id)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ddpm_date ON DerivedDailyPlaneMetrics(date_yyyy_mm_dd)');
      } catch (_) {}
    }
  }

  /// Idempotent schema healing for evolving substrate tables.
  /// This prevents "missing column" failures on installs that upgraded across
  /// intermediate builds with partial schemas.
  Future<void> _ensureSubstrateSchema(Database db) async {
    // RolePlaneEpistemics: ensure the canonical timestamp column exists.
    await _ensureColumnExists(db,
        table: 'RolePlaneEpistemics',
        column: 'updated_at_ms',
        columnDef: 'INTEGER NOT NULL DEFAULT 0');

    // Some early builds used `updated_at` instead of `updated_at_ms`.
    // Keep compatibility by leaving the old column if present; we now write
    // only to updated_at_ms.

    // Ensure provenance columns exist.
    await _ensureColumnExists(db,
        table: 'RolePlaneEpistemics',
        column: 'q_source',
        columnDef: "TEXT NOT NULL DEFAULT 'calc'");
    await _ensureColumnExists(db,
        table: 'RolePlaneEpistemics',
        column: 'c_source',
        columnDef: "TEXT NOT NULL DEFAULT 'calc'");

    // InputCoverageDaily: ensure calc_inputs_json exists.
    await _ensureColumnExists(db,
        table: 'InputCoverageDaily',
        column: 'calc_inputs_json',
        columnDef: 'TEXT');


// FrequencyComposition table name healing.
// Some builds used a snake_case table name. We canonicalize to FrequencyComposition.
await _ensureFrequencyCompositionCanonical(db);
  }

  Future<void> _ensureColumnExists(
    Database db, {
    required String table,
    required String column,
    required String columnDef,
  }) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final exists = info.any((row) => row['name'] == column);
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $columnDef');
      }
    } catch (_) {
      // If table doesn't exist yet, _createAllTables will handle it.
    }
  }



/// Ensures the frequency composition table exists under the canonical name.
/// Older builds may have used `frequency_composition` (snake_case).
/// This is a safe, best-effort migration performed on open.
Future<void> _ensureFrequencyCompositionCanonical(Database db) async {
  try {
    final names = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND lower(name) IN ('frequencycomposition','frequency_composition')",
    );

    final hasCanonical = names.any((r) => (r['name'] ?? '').toString() == 'FrequencyComposition');
    final legacyName = names
        .map((r) => (r['name'] ?? '').toString())
        .firstWhere((n) => n.toLowerCase() == 'frequency_composition', orElse: () => '');

    if (!hasCanonical && legacyName.isNotEmpty) {
      await db.execute('ALTER TABLE $legacyName RENAME TO FrequencyComposition');
    }

    final chk = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='FrequencyComposition'",
    );
    if (chk.isEmpty) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS FrequencyComposition (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_id INTEGER NOT NULL UNIQUE,
          sense INTEGER NOT NULL DEFAULT 25,
          maintain INTEGER NOT NULL DEFAULT 25,
          explore INTEGER NOT NULL DEFAULT 25,
          enforce INTEGER NOT NULL DEFAULT 25,
          updated_at INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(entry_id) REFERENCES Entry(id) ON DELETE CASCADE
        )
      ''');
    }
  } catch (_) {
    // Fail-soft
  }
}

  // ─── Schema ───────────────────────────────────────────────────────────────────

  Future<void> _createAllTables(Database db) async {
    // Entry: core row per session
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Entry (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        date               TEXT NOT NULL,
        timestamp          TEXT NOT NULL,
        entry_type         TEXT NOT NULL DEFAULT 'baseline',
        event_label        TEXT,
        overall_score      REAL NOT NULL DEFAULT 0,
        completion_percent REAL NOT NULL DEFAULT 0,
        depth_level        INTEGER NOT NULL DEFAULT 1,
        is_deleted         INTEGER NOT NULL DEFAULT 0,
        deleted_at         INTEGER,
        updated_at         INTEGER NOT NULL
      )
    ''');

    // MetricValue: normalized 0-100 values per metric per entry
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MetricValue (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id   INTEGER NOT NULL,
        metric_id  TEXT NOT NULL,
        value      INTEGER NOT NULL CHECK(value BETWEEN 0 AND 100),
        FOREIGN KEY (entry_id) REFERENCES Entry(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_metric_entry ON MetricValue(entry_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_metric_metric ON MetricValue(metric_id)');

    // Tag: freeform labels attached to entries
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Tag (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id   INTEGER NOT NULL,
        tag_name   TEXT NOT NULL,
        FOREIGN KEY (entry_id) REFERENCES Entry(id)
      )
    ''');

    // v8: TagDef + EntryTag (preferred going forward)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS TagDef (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS EntryTag (
        entry_id INTEGER NOT NULL,
        tag_id   INTEGER NOT NULL,
        PRIMARY KEY (entry_id, tag_id),
        FOREIGN KEY (entry_id) REFERENCES Entry(id),
        FOREIGN KEY (tag_id) REFERENCES TagDef(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_entrytag_entry ON EntryTag(entry_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_entrytag_tag ON EntryTag(tag_id)');

    // Vital: physiological measurements (separate stream)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Vital (
        id           TEXT PRIMARY KEY,
        entry_id     INTEGER,
        date         TEXT NOT NULL,
        timestamp    TEXT NOT NULL,
        type         TEXT NOT NULL,
        label        TEXT,
        value1       REAL,
        value2       REAL,
        value3       REAL,
        unit         TEXT,
        note         TEXT,
        source       TEXT NOT NULL DEFAULT 'manual'
      )
    ''');

    // v9: Frequency composition (measured, user-entered)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS FrequencyComposition (
        entry_id   INTEGER PRIMARY KEY,
        sense      INTEGER NOT NULL,
        maintain   INTEGER NOT NULL,
        explore    INTEGER NOT NULL,
        enforce    INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(entry_id) REFERENCES Entry(id)
      )
    ''');

    // v12: Temperament composition (4-way), stored per entry
    await db.execute('''
      CREATE TABLE IF NOT EXISTS TemperamentComposition (
        entry_id     INTEGER PRIMARY KEY,
        choleric     INTEGER NOT NULL,
        sanguine     INTEGER NOT NULL,
        melancholic  INTEGER NOT NULL,
        pragmatic    INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        FOREIGN KEY(entry_id) REFERENCES Entry(id)
      )
    ''');

    // v9: PlaneAux (optional measured shells for atomic view; roots-as-planes)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS PlaneAux (
        entry_id       INTEGER NOT NULL,
        plane_id       TEXT NOT NULL,
        room_0_10      REAL,
        q_facts_0_10   REAL,
        q_meaning_0_10 REAL,
        PRIMARY KEY(entry_id, plane_id),
        FOREIGN KEY(entry_id) REFERENCES Entry(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_planeaux_entry ON PlaneAux(entry_id)');

    // v9: Derived metrics cache per day per plane (roots-as-planes)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS DerivedDailyPlaneMetrics (
        date_yyyy_mm_dd      TEXT NOT NULL,
        plane_id             TEXT NOT NULL,
        window_days          INTEGER NOT NULL,
        n_points_used        INTEGER NOT NULL,
        dwell_hi_ratio       REAL,
        dwell_hi_days        INTEGER,
        vol_raw_stddev       REAL,
        vol_score_0_10       REAL,
        steadiness_score_0_10 REAL,
        trend_raw_slope_per_day REAL,
        trend_score          REAL,
        trend_abs            REAL,
        persistence_ratio    REAL,
        persistence_score    REAL,
        has_min_points       INTEGER NOT NULL,
        is_estimate          INTEGER NOT NULL,
        PRIMARY KEY(date_yyyy_mm_dd, plane_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ddpm_date ON DerivedDailyPlaneMetrics(date_yyyy_mm_dd)');

    // v11+: Coverage cache per-day (CR-COV-v1)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS InputCoverageDaily (
        date_yyyy_mm_dd TEXT PRIMARY KEY,
        cov_in          REAL NOT NULL,
        cov_out         REAL NOT NULL,
        cov_beh         REAL NOT NULL,
        cov_entry       REAL NOT NULL,
        calc_rule_id    TEXT NOT NULL,
        calc_inputs_json TEXT
      )
    ''');

    // v11+: Default epistemics (q/c) per Role×Plane per-day.
    // This is a substrate cache. If the user explicitly overrides q/c later,
    // those values must be stored with q_source/c_source='user'.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS RolePlaneEpistemics (
        date_yyyy_mm_dd TEXT NOT NULL,
        role_id         TEXT NOT NULL,
        plane_id        TEXT NOT NULL,
        q_0_1           REAL NOT NULL,
        c_0_1           REAL NOT NULL,
        q_source        TEXT NOT NULL DEFAULT 'calc',
        c_source        TEXT NOT NULL DEFAULT 'calc',
        rule_id         TEXT NOT NULL,
        updated_at_ms   INTEGER NOT NULL,
        PRIMARY KEY(date_yyyy_mm_dd, role_id, plane_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rpe_date ON RolePlaneEpistemics(date_yyyy_mm_dd)');


// ─── Event log (Phase 3B) ────────────────────────────────────────────────
await db.execute('''
  CREATE TABLE IF NOT EXISTS EventLog (
    event_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type      TEXT NOT NULL,
    timestamp_ms    INTEGER NOT NULL,
    title           TEXT NOT NULL,
    notes           TEXT,
    metadata_json   TEXT,
    source          TEXT NOT NULL DEFAULT 'user',
    calc_rule_id    TEXT,
    calc_inputs_json TEXT
  )
''');
await db.execute('CREATE INDEX IF NOT EXISTS idx_eventlog_ts ON EventLog(timestamp_ms)');
await db.execute('CREATE INDEX IF NOT EXISTS idx_eventlog_type ON EventLog(event_type)');

await db.execute('''
  CREATE TABLE IF NOT EXISTS EventTags (
    tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
    tag    TEXT NOT NULL UNIQUE
  )
''');

await db.execute('''
  CREATE TABLE IF NOT EXISTS EventTagJoin (
    event_id INTEGER NOT NULL,
    tag_id   INTEGER NOT NULL,
    PRIMARY KEY (event_id, tag_id),
    FOREIGN KEY (event_id) REFERENCES EventLog(event_id),
    FOREIGN KEY (tag_id)   REFERENCES EventTags(tag_id)
  )
''');
await db.execute('CREATE INDEX IF NOT EXISTS idx_eventtagjoin_event ON EventTagJoin(event_id)');
await db.execute('CREATE INDEX IF NOT EXISTS idx_eventtagjoin_tag ON EventTagJoin(tag_id)');

await db.execute('''
  CREATE TABLE IF NOT EXISTS EventScope (
    event_id   INTEGER NOT NULL,
    scope_type TEXT NOT NULL,
    scope_id   TEXT NOT NULL,
    PRIMARY KEY (event_id, scope_type, scope_id),
    FOREIGN KEY (event_id) REFERENCES EventLog(event_id)
  )
''');
await db.execute('CREATE INDEX IF NOT EXISTS idx_eventscope_event ON EventScope(event_id)');

// ─── System daily metrics (Phase 4) ───────────────────────────────────────
await db.execute('''
  CREATE TABLE IF NOT EXISTS SystemDailyMetrics (
    date_yyyy_mm_dd   TEXT PRIMARY KEY,
    cov_entry         REAL,
    w_mean            REAL,
    overridden_cells  INTEGER,
    lambda_sub        REAL,
    k_sub             REAL,
    v_vis             REAL,
    v_verif           REAL,
    refresh_count     INTEGER,
    collapse_count    INTEGER,
    calc_rule_id      TEXT NOT NULL,
    calc_inputs_json  TEXT,
    updated_at_ms     INTEGER NOT NULL
  )
''');
  }

  // ─── Frequency composition DAO ─────────────────────────────────────────────

  Future<void> upsertFrequencyComposition(int entryId, FrequencyComposition fc) async {
    final db = await database;
    await db.insert('FrequencyComposition', fc.toMap(entryId),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<FrequencyComposition?> getFrequencyComposition(int entryId) async {
    final db = await database;
    final rows = await db.query('FrequencyComposition', where: 'entry_id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) return null;
    return FrequencyComposition.fromMap(rows.first);
  }

  // ─── Temperament composition DAO ──────────────────────────────────────────

  Future<void> upsertTemperamentComposition(int entryId, TemperamentComposition tc) async {
    final db = await database;
    await db.insert('TemperamentComposition', tc.toMap(entryId),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TemperamentComposition?> getTemperamentComposition(int entryId) async {
    final db = await database;
    final rows = await db.query('TemperamentComposition', where: 'entry_id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) return null;
    return TemperamentComposition.fromRow(rows.first);
  }

  /// Returns frequency composition points in the given time range.
  ///
  /// If [clauses] is provided, the returned points are filtered to entries
  /// matching the include/exclude semantics of [TagClause].
  Future<List<FrequencyPoint>> getFrequencySeries({
    required DateTime start,
    required DateTime end,
    List<TagClause>? clauses,
  }) async {
    final db = await database;
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    List<int>? allowedEntryIds;
    if (clauses != null && clauses.isNotEmpty) {
      allowedEntryIds = await getEntryIdsByTagClauses(
        includeTags: clauses
            .where((c) => c.state == Trinary.include)
            .map((c) => c.tag)
            .toList(),
        excludeTags: clauses
            .where((c) => c.state == Trinary.exclude)
            .map((c) => c.tag)
            .toList(),
      );
      if (allowedEntryIds!.isEmpty) return <FrequencyPoint>[];
    }

    final where = <String>[
      'e.timestamp_ms >= ?',
      'e.timestamp_ms < ?',
      "e.entry_type IN ('baseline','event','retro')",
    ];
    final args = <Object?>[startMs, endMs];
    if (allowedEntryIds != null) {
      // Safe because IDs are integers from our DB.
      where.add('e.id IN (${List.filled(allowedEntryIds.length, '?').join(',')})');
      args.addAll(allowedEntryIds);
    }

    final rows = await db.rawQuery(
      '''
      SELECT e.id AS entry_id, e.timestamp_ms AS ts, 
             fc.sense AS sense, fc.maintain AS maintain, fc.explore AS explore, fc.enforce AS enforce
      FROM entry e
      JOIN frequency_composition fc ON fc.entry_id = e.id
      WHERE ${where.join(' AND ')}
      ORDER BY e.timestamp_ms ASC
      ''',
      args,
    );

    DateTime normalizeDay(int ms) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime(dt.year, dt.month, dt.day);
    }

    return rows
        .map(
          (r) => FrequencyPoint(
            day: normalizeDay((r['ts'] as int?) ?? 0),
            entryId: (r['entry_id'] as int?) ?? 0,
            sense: (r['sense'] as int?) ?? 0,
            maintain: (r['maintain'] as int?) ?? 0,
            explore: (r['explore'] as int?) ?? 0,
            enforce: (r['enforce'] as int?) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  // ─── Plane aux DAO ─────────────────────────────────────────────────────────

  Future<void> upsertPlaneAux(int entryId, PlaneAux aux) async {
    final db = await database;
    await db.insert('PlaneAux', aux.toMap(entryId), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<PlaneAux?> getPlaneAux(int entryId, String planeId) async {
    final db = await database;
    final rows = await db.query('PlaneAux', where: 'entry_id = ? AND plane_id = ?', whereArgs: [entryId, planeId], limit: 1);
    if (rows.isEmpty) return null;
    return PlaneAux.fromMap(rows.first);
  }

  // ─── Derived metrics DAO ───────────────────────────────────────────────────

  Future<DerivedDailyPlaneMetrics?> getDerivedDailyPlaneMetrics(String date, String planeId) async {
    final db = await database;
    final rows = await db.query('DerivedDailyPlaneMetrics',
        where: 'date_yyyy_mm_dd = ? AND plane_id = ?', whereArgs: [date, planeId], limit: 1);
    if (rows.isEmpty) return null;
    return DerivedDailyPlaneMetrics.fromMap(rows.first);
  }

  Future<void> upsertDerivedDailyPlaneMetrics(DerivedDailyPlaneMetrics m) async {
    final db = await database;
    await db.insert('DerivedDailyPlaneMetrics', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── Entry DAO ────────────────────────────────────────────────────────────────

  /// Save a new entry. Returns the assigned row id.
  Future<int> saveEntry(Entry entry) async {
    final db = await database;
    final m = entry.toMap();
    m.remove('id');
    return db.insert('Entry', m);
  }

  /// Save an entry + metric values as a single transaction.
  ///
  /// This avoids rare "entry saved but metrics missing" outcomes due to partial
  /// failure or racing writes.
  Future<int> saveEntryWithMetricsAtomic(Entry entry, Map<String, int> values) async {
    final db = await database;
    final metricMap = Map<String, int>.from(values);
    return db.transaction((txn) async {
      final m = entry.toMap();
      m.remove('id');
      final entryId = await txn.insert('Entry', m);
      // Replace existing values (should be none, but keeps function usable later).
      await txn.delete('MetricValue', where: 'entry_id = ?', whereArgs: [entryId]);
      for (final kv in metricMap.entries) {
        await txn.insert('MetricValue', {
          'entry_id': entryId,
          'metric_id': kv.key,
          'value': kv.value.clamp(0, 100),
        });
      }
      return entryId;
    });
  }

  // ─── Tags (v8 join-table) ──────────────────────────────────────────────────

  Future<void> setTagsForEntry(int entryId, List<String> tags) async {
    final db = await database;
    final cleaned = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList();
    await db.transaction((txn) async {
      // Clear existing join rows
      await txn.delete('EntryTag', where: 'entry_id = ?', whereArgs: [entryId]);
      for (final name in cleaned) {
        await txn.insert('TagDef', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
        final rows = await txn.query('TagDef', where: 'name = ?', whereArgs: [name], limit: 1);
        if (rows.isEmpty) continue;
        final tagId = rows.first['id'] as int;
        await txn.insert('EntryTag', {'entry_id': entryId, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<List<String>> getTagsForEntry(int entryId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT td.name AS name
      FROM EntryTag et
      JOIN TagDef td ON td.id = et.tag_id
      WHERE et.entry_id = ?
      ORDER BY td.name COLLATE NOCASE ASC
    ''', [entryId]);
    return rows.map((r) => (r['name'] as String)).toList();
  }

  Future<List<String>> getAllTags({int limit = 200}) async {
    final db = await database;
    final rows = await db.query('TagDef', orderBy: 'name COLLATE NOCASE ASC', limit: limit);
    return rows.map((r) => (r['name'] as String)).toList();
  }

  /// Returns entry IDs that match include/exclude tag constraints.
  /// includeTags: entry must contain ALL
  /// excludeTags: entry must contain NONE
  Future<List<int>> getEntryIdsByTagClauses({
    List<String> includeTags = const [],
    List<String> excludeTags = const [],
  }) async {
    final db = await database;
    final inc = includeTags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final exc = excludeTags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    Future<List<int>> _resolve(List<String> names) async {
      if (names.isEmpty) return <int>[];
      final qs = List.filled(names.length, '?').join(',');
      final rows = await db.rawQuery('SELECT id FROM TagDef WHERE name IN ($qs)', names);
      return rows.map((r) => r['id'] as int).toList();
    }

    final incIds = await _resolve(inc);
    final excIds = await _resolve(exc);

    if (inc.isNotEmpty && incIds.isEmpty) return <int>[];

    final whereParts = <String>[];
    final args = <Object?>[];

    String base = 'SELECT DISTINCT e.id AS id FROM Entry e';

    if (incIds.isNotEmpty) {
      base = '''
        SELECT e.id AS id
        FROM Entry e
        JOIN EntryTag et ON et.entry_id = e.id
        WHERE e.is_deleted = 0 AND et.tag_id IN (${List.filled(incIds.length, '?').join(',')})
        GROUP BY e.id
        HAVING COUNT(DISTINCT et.tag_id) = ${incIds.length}
      ''';
      args.addAll(incIds);
    } else {
      whereParts.add('e.is_deleted = 0');
    }

    if (excIds.isNotEmpty) {
      final qs = List.filled(excIds.length, '?').join(',');
      whereParts.add('NOT EXISTS (SELECT 1 FROM EntryTag et2 WHERE et2.entry_id = e.id AND et2.tag_id IN ($qs))');
      args.addAll(excIds);
    }

    final sql = incIds.isNotEmpty
        ? base + (whereParts.isEmpty ? '' : ' AND ' + whereParts.join(' AND '))
        : base + (whereParts.isEmpty ? '' : ' WHERE ' + whereParts.join(' AND '));

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => r['id'] as int).toList();
  }


  /// Update an existing entry + metric values as a single transaction.
  ///
  /// Semantics: overwrite metric values completely (delete+insert), update Entry row.
  Future<void> updateEntryWithMetricsAtomic({
    required int entryId,
    required Entry entry,
    required Map<String, int> values,
  }) async {
    final db = await database;
    final metricMap = Map<String, int>.from(values);
    await db.transaction((txn) async {
      final m = entry.toMap();
      m.remove('id');
      // Ensure updated_at is refreshed
      m['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      await txn.update('Entry', m, where: 'id = ?', whereArgs: [entryId]);
      await txn.delete('MetricValue', where: 'entry_id = ?', whereArgs: [entryId]);
      for (final kv in metricMap.entries) {
        await txn.insert('MetricValue', {
          'entry_id': entryId,
          'metric_id': kv.key,
          'value': kv.value.clamp(0, 100),
        });
      }
    });
  }

  /// Load a single entry by id (including deleted if present).
  Future<Entry?> getEntryById(int entryId, {bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.query(
      'Entry',
      where: includeDeleted ? 'id = ?' : 'id = ? AND is_deleted = 0',
      whereArgs: [entryId],
      limit: 1,
    );
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  /// The previous non-deleted entry before [timestamp] (any type).
  Future<Entry?> getPreviousEntryByTimestamp(String timestamp) async {
    final db = await database;
    final rows = await db.query(
      'Entry',
      where: 'is_deleted = 0 AND timestamp < ?',
      whereArgs: [timestamp],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  /// Search/filter entries (for History v2).
  Future<List<Entry>> searchEntries({
    DateTime? start,
    DateTime? end,
    List<EntryType>? types,
    List<int>? depths,
    String? text,
    int limit = 200,
  }) async {
    final db = await database;
    final where = <String>['is_deleted = 0'];
    final args = <dynamic>[];

    if (start != null) {
      where.add('date >= ?');
      args.add(start.toIso8601String().substring(0, 10));
    }
    if (end != null) {
      where.add('date <= ?');
      args.add(end.toIso8601String().substring(0, 10));
    }
    if (types != null && types.isNotEmpty) {
      where.add('entry_type IN (${List.filled(types.length, '?').join(',')})');
      args.addAll(types.map((t) => t.name));
    }
    if (depths != null && depths.isNotEmpty) {
      where.add('depth_level IN (${List.filled(depths.length, '?').join(',')})');
      args.addAll(depths);
    }
    if (text != null && text.trim().isNotEmpty) {
      where.add('(event_label LIKE ?)');
      args.add('%${text.trim()}%');
    }

    final rows = await db.query(
      'Entry',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// Soft-delete an entry (is_deleted = 1). Data preserved.
  Future<void> softDeleteEntry(int entryId) async {
    final db = await database;
    await db.update('Entry', {'is_deleted': 1, 'deleted_at': DateTime.now().millisecondsSinceEpoch, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [entryId]);
  }

  /// Most recent non-deleted entry by timestamp.
  /// If [within] is provided, only entries from within that window.
  Future<Entry?> getCurrentEntry({Duration? within}) async {
    final db = await database;
    String where = 'is_deleted = 0';
    final args = <dynamic>[];
    if (within != null) {
      where += ' AND timestamp >= ?';
      args.add(DateTime.now().subtract(within).toIso8601String());
    }
    final rows = await db.query('Entry',
        where: where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'timestamp DESC',
        limit: 1);
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  /// All non-deleted entries for a calendar date.
  Future<List<Entry>> getEntriesForDateTyped(DateTime date) async {
    final db = await database;
    final d = date.toIso8601String().substring(0, 10);
    final rows = await db.query('Entry',
        where: 'date = ? AND is_deleted = 0',
        whereArgs: [d],
        orderBy: 'timestamp ASC');
    return rows.map(Entry.fromMap).toList();
  }

  /// All non-deleted entries in an inclusive date range.
  Future<List<Entry>> getEntriesInRange(DateTime start, DateTime end) async {
    final db = await database;
    final s = start.toIso8601String().substring(0, 10);
    final e = end.toIso8601String().substring(0, 10);
    final rows = await db.query('Entry',
        where: 'date >= ? AND date <= ? AND is_deleted = 0',
        whereArgs: [s, e],
        orderBy: 'date ASC, timestamp ASC');
    return rows.map(Entry.fromMap).toList();
  }

  /// Recent N non-deleted entries, newest first.
  Future<List<Entry>> getRecentEntries({int limit = 50}) async {
    final db = await database;
    final rows = await db.query('Entry',
        where: 'is_deleted = 0',
        orderBy: 'timestamp DESC',
        limit: limit);
    return rows.map(Entry.fromMap).toList();
  }

  /// History rows with tag lists for HistoryScreen.
  Future<List<Map<String, dynamic>>> getHistoryRows({int limit = 180}) async {
    final db = await database;
    final entries = await db.query('Entry',
        where: 'is_deleted = 0',
        orderBy: 'date DESC, timestamp DESC',
        limit: limit);
    final result = <Map<String, dynamic>>[];
    for (final e in entries) {
      final id   = e['id'] as int;
      // Prefer v8 join-table; fall back to legacy Tag if empty (for fresh installs).
      List<String> tagNames = <String>[];
      try {
        tagNames = await getTagsForEntry(id);
      } catch (_) {}
      if (tagNames.isEmpty) {
        try {
          final tags = await db.query('Tag', where: 'entry_id = ?', whereArgs: [id]);
          tagNames = tags.map((t) => t['tag_name'] as String).toList();
        } catch (_) {}
      }
      result.add({
        ...e,
        'tags': tagNames,
      });
    }
    return result;
  }

  // ─── MetricValue DAO ──────────────────────────────────────────────────────────

  /// Save metric values for an entry (replaces existing).
  Future<void> saveMetricValues(int entryId, Map<String, int> values) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('MetricValue',
          where: 'entry_id = ?', whereArgs: [entryId]);
      for (final kv in values.entries) {
        await txn.insert('MetricValue', {
          'entry_id':  entryId,
          'metric_id': kv.key,
          'value':     kv.value.clamp(0, 100),
        });
      }
    });
  }

  /// Returns metric_id → value (0-100) for a given entry.
  Future<Map<String, int>> getMetricValuesForEntry(int entryId) async {
    final db = await database;
    final rows = await db.query('MetricValue',
        where: 'entry_id = ?', whereArgs: [entryId]);
    return {
      for (final r in rows)
        r['metric_id'] as String: (r['value'] as num).toInt()
    };
  }

  /// Time-series for one metric between two dates, ascending.
  Future<List<Map<String, dynamic>>> getMetricSeries(
      String metricId, DateTime startDate, DateTime endDate) async {
    final db = await database;
    final start = startDate.toIso8601String().substring(0, 10);
    final end   = endDate.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT e.date, e.timestamp, mv.value
      FROM MetricValue mv
      JOIN Entry e ON e.id = mv.entry_id
      WHERE mv.metric_id = ?
        AND e.date >= ?
        AND e.date <= ?
        AND e.is_deleted = 0
      ORDER BY e.date ASC, e.timestamp ASC
    ''', [metricId, start, end]);
  }

  /// Time-series for one metric between two dates, restricted to specific entries.
  /// Used for tag-filtered projections.
  Future<List<Map<String, dynamic>>> getMetricSeriesForEntryIds(
      String metricId, DateTime startDate, DateTime endDate, List<int> entryIds) async {
    if (entryIds.isEmpty) return <Map<String, dynamic>>[];
    final db = await database;
    final start = startDate.toIso8601String().substring(0, 10);
    final end   = endDate.toIso8601String().substring(0, 10);
    final qs = List.filled(entryIds.length, '?').join(',');
    return db.rawQuery('''
      SELECT e.date, e.timestamp, mv.value
      FROM MetricValue mv
      JOIN Entry e ON e.id = mv.entry_id
      WHERE mv.metric_id = ?
        AND e.date >= ?
        AND e.date <= ?
        AND e.is_deleted = 0
        AND mv.entry_id IN ($qs)
      ORDER BY e.date ASC, e.timestamp ASC
    ''', [metricId, start, end, ...entryIds]);
  }

  /// All distinct metric IDs that have ever been recorded.
  Future<List<String>> getDistinctMetricIds() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT metric_id FROM MetricValue ORDER BY metric_id ASC');
    return rows.map((r) => r['metric_id'] as String).toList();
  }

  // ─── Vital DAO ────────────────────────────────────────────────────────────────

  Future<void> saveVital(Vital v) async {
    final db = await database;
    await db.insert('Vital', v.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVital(String id) async {
    final db = await database;
    await db.delete('Vital', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Vital>> getRecentVitals({int limit = 50}) async {
    final db = await database;
    final rows = await db.query('Vital',
        orderBy: 'timestamp DESC', limit: limit);
    return rows.map(Vital.fromMap).toList();
  }

  Future<List<Vital>> getVitalsByType(VitalType type, int days) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final rows = await db.query('Vital',
        where: 'type = ? AND date >= ?',
        whereArgs: [type.name, since],
        orderBy: 'date ASC');
    return rows.map(Vital.fromMap).toList();
  }


  // ─── Coverage helpers (CR-COV-v1) ──────────────────────────────────────────

  Future<List<String>> getMetricIdsForEntry(int entryId) async {
    final db = await database;
    final rows = await db.query('MetricValue',
        columns: ['metric_id'], where: 'entry_id = ?', whereArgs: [entryId]);
    return rows.map((r) => (r['metric_id'] as String)).toList();
  }

  Future<void> upsertCoverageDaily({
    required String date,
    required double covI,
    required double covE,
    required double covO,
    required double covEntry,
    required String calcRuleId,
    String? calcInputsJson,
  }) async {
    final db = await database;
    await db.insert(
      'InputCoverageDaily',
      {
        'date_yyyy_mm_dd': date,
        'cov_in': covI,
        'cov_out': covE,
        'cov_beh': covO,
        'cov_entry': covEntry,
        'calc_rule_id': calcRuleId,
        'calc_inputs_json': calcInputsJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getCoverageDaily(String date) async {
    final db = await database;
    final rows = await db.query(
      'InputCoverageDaily',
      where: 'date_yyyy_mm_dd = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }



  // ─── Epistemics helpers (q/c defaults) ──────────────────────────────────────
  // Only writes defaults when user has not overridden q/c.

  Future<void> upsertRolePlaneEpistemicsDefault({
    required String date,
    required String roleId,
    required String planeId,
    required double qDefault,
    required double cDefault,
    required String ruleId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // If an existing row has user overrides, do not clobber.
    final existing = await db.query(
      'RolePlaneEpistemics',
      where: 'date_yyyy_mm_dd=? AND role_id=? AND plane_id=?',
      whereArgs: [date, roleId, planeId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final qSource = (row['q_source'] as String?) ?? 'calc';
      final cSource = (row['c_source'] as String?) ?? 'calc';

      final updates = <String, Object?>{
        'rule_id': ruleId,
        'updated_at_ms': now,
      };

      if (qSource != 'user') {
        updates['q_0_1'] = qDefault;
        updates['q_source'] = 'calc';
      }
      if (cSource != 'user') {
        updates['c_0_1'] = cDefault;
        updates['c_source'] = 'calc';
      }

      await db.update(
        'RolePlaneEpistemics',
        updates,
        where: 'date_yyyy_mm_dd=? AND role_id=? AND plane_id=?',
        whereArgs: [date, roleId, planeId],
      );
      return;
    }

    await db.insert(
      'RolePlaneEpistemics',
      {
        'date_yyyy_mm_dd': date,
        'role_id': roleId,
        'plane_id': planeId,
        'q_0_1': qDefault,
        'c_0_1': cDefault,
        'q_source': 'calc',
        'c_source': 'calc',
        'rule_id': ruleId,
        'updated_at_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  
Future<void> upsertRolePlaneEpistemicsOverride({
  required String date,
  required String roleId,
  required String planeId,
  required double q,
  required double c,
  required String ruleId,
}) async {
  final db = await database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert(
    'RolePlaneEpistemics',
    {
      'date_yyyy_mm_dd': date,
      'role_id': roleId,
      'plane_id': planeId,
      'q_0_1': q,
      'c_0_1': c,
      'q_source': 'user',
      'c_source': 'user',
      'rule_id': ruleId,
      'updated_at_ms': now,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> clearRolePlaneEpistemicsOverride({
  required String date,
  required String roleId,
  required String planeId,
}) async {
  final db = await database;
  // Do not delete the row; just mark sources non-user so defaults can be written.
  await db.update(
    'RolePlaneEpistemics',
    {
      'q_source': 'calc',
      'c_source': 'calc',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'date_yyyy_mm_dd=? AND role_id=? AND plane_id=?',
    whereArgs: [date, roleId, planeId],
  );
}

Future<List<Map<String, Object?>>> listRolePlaneEpistemics(String date) async {
    final db = await database;
    return db.query(
      'RolePlaneEpistemics',
      where: 'date_yyyy_mm_dd = ?',
      whereArgs: [date],
      orderBy: 'role_id ASC, plane_id ASC',
    );
  }



// --------------------------------------------------------------------------
// Graph-series helpers (selection-first graphs). Descriptive only.
// These MUST align to the canonical v5+ schema:
//   Entry(date, is_deleted)
//   MetricValue(entry_id, metric_id, value)
//   FrequencyComposition(entry_id, sense, maintain, explore, enforce)
//   Vital(date, type, label, value1, value2, unit)
// --------------------------------------------------------------------------

String _ymd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

// Range read: taxonomy metric (planes/fields/nodes) by day.
// Returns map date(yyyy-mm-dd) -> value (0..100).
Future<Map<String, double>> getMetricSeriesByDay({
  required String metricId,
  required DateTime start,
  required DateTime end,
}) async {
  final db = await database;

  final rows = await db.rawQuery('''
    SELECT e.date AS date, mv.value AS value
    FROM Entry e
    JOIN MetricValue mv ON mv.entry_id = e.id
    WHERE mv.metric_id = ?
      AND e.is_deleted = 0
      AND e.date BETWEEN ? AND ?
    ORDER BY e.date ASC
  ''', [metricId, _ymd(start), _ymd(end)]);

  final out = <String, double>{};
  for (final r in rows) {
    final d = (r['date'] ?? '').toString();
    final v = (r['value'] as num?)?.toDouble();
    if (d.isNotEmpty && v != null) out[d] = v;
  }
  return out;
}

// Range read: frequency composition by day (joined to Entry for date).
// Returns map date(yyyy-mm-dd) -> [sense, maintain, explore, enforce]
Future<Map<String, List<int>>> getFrequencyByDay({
  required DateTime start,
  required DateTime end,
}) async {
  final db = await database;

  // Table is FrequencyComposition(entry_id...) in v9+; date comes from Entry.
  // Fail-soft if table is missing.
  final tableCheck = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='FrequencyComposition'",
  );
  if (tableCheck.isEmpty) return {};

  final rows = await db.rawQuery('''
    SELECT e.date AS date, fc.sense, fc.maintain, fc.explore, fc.enforce
    FROM Entry e
    JOIN FrequencyComposition fc ON fc.entry_id = e.id
    WHERE e.is_deleted = 0
      AND e.date BETWEEN ? AND ?
    ORDER BY e.date ASC
  ''', [_ymd(start), _ymd(end)]);

  final out = <String, List<int>>{};
  for (final r in rows) {
    final d = (r['date'] ?? '').toString();
    if (d.isEmpty) continue;
    out[d] = [
      (r['sense'] as num?)?.toInt() ?? 0,
      (r['maintain'] as num?)?.toInt() ?? 0,
      (r['explore'] as num?)?.toInt() ?? 0,
      (r['enforce'] as num?)?.toInt() ?? 0,
    ];
  }
  return out;
}

// --------------------------------------------------------------------------
// Vitals: known + custom discovery for SeriesRegistry.
// Schema: Vital(type, label?, value1/value2, unit?, date)
// --------------------------------------------------------------------------

// Discover custom vitals (type=custom) that have labels.
// Returns SeriesSpec(id: VITAL.custom:<label>)
Future<List<SeriesSpec>> getCustomVitalSpecs() async {
  final db = await database;

  // Fail-soft if table missing.
  final tableCheck = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='Vital'",
  );
  if (tableCheck.isEmpty) return [];

  final rows = await db.rawQuery('''
    SELECT
      COALESCE(label, '') AS label,
      COALESCE(MAX(unit), '') AS unit
    FROM Vital
    WHERE type = 'custom' AND label IS NOT NULL AND TRIM(label) != ''
    GROUP BY label
    ORDER BY label COLLATE NOCASE
  ''');

  return rows.map((r) {
    final label = (r['label'] ?? '').toString().trim();
    final unit = (r['unit'] ?? '').toString();
    final key = 'custom:$label';
    return SeriesSpec(
      id: 'VITAL.$key',
      label: label,
      type: SeriesType.vitals,
      scope: SeriesScope.vital,
      unit: unit.isEmpty ? null : unit,
    );
  }).toList();
}

// Range read: vitals by day for a given key.
// Supported keys:
//   hr/temp/weight/glucose/sleep/spo2 (best-effort)
//   bp_sys / bp_dia (maps to type='bp' value1/value2)
//   custom:<label> (maps to type='custom' AND label=<label>)
Future<Map<String, double>> getVitalSeriesByDay({
  required String vitalKey,
  required DateTime start,
  required DateTime end,
}) async {
  final db = await database;

  // Fail-soft if table missing.
  final tableCheck = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='Vital'",
  );
  if (tableCheck.isEmpty) return {};

  String where;
  List<Object?> whereArgs;

  bool isBpSys = vitalKey == 'bp_sys';
  bool isBpDia = vitalKey == 'bp_dia';
  bool isCustom = vitalKey.startsWith('custom:');

  if (isBpSys || isBpDia) {
    where = "type = 'bp' AND date BETWEEN ? AND ?";
    whereArgs = [_ymd(start), _ymd(end)];
  } else if (isCustom) {
    final label = vitalKey.substring('custom:'.length);
    where = "type = 'custom' AND label = ? AND date BETWEEN ? AND ?";
    whereArgs = [label, _ymd(start), _ymd(end)];
  } else {
    // Best-effort: match Vital.type to vitalKey
    where = "type = ? AND date BETWEEN ? AND ?";
    whereArgs = [vitalKey, _ymd(start), _ymd(end)];
  }

  final rows = await db.query(
    'Vital',
    columns: ['date', 'value1', 'value2'],
    where: where,
    whereArgs: whereArgs,
    orderBy: 'date ASC, timestamp ASC',
  );

  final out = <String, double>{};
  for (final r in rows) {
    final d = (r['date'] ?? '').toString();
    if (d.isEmpty) continue;

    double? v;
    if (isBpDia) {
      v = (r['value2'] as num?)?.toDouble();
    } else {
      // bp_sys or any scalar vital uses value1
      v = (r['value1'] as num?)?.toDouble();
    }
    if (v != null) out[d] = v; // last value wins per day
  }
  return out;
}

// ─── Dev diagnostics (debug-only) ────────────────────────────────────────────

/// Logs all table names and their row counts to debugPrint.
/// Call from main() or a debug screen to verify schema health.
/// No-op in release builds (assert removed by dart2js/flutter in release mode).
Future<void> logTablesAndCounts() async {
  assert(() {
    // Runs only in debug builds.
    () async {
      try {
        final db = await database;
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        );
        debugPrint('─── Coheron DB Schema Probe ───');
        for (final t in tables) {
          final name = t['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          try {
            final cnt = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM "$name"'),
            );
            debugPrint('  $name: ${cnt ?? 0} rows');
          } catch (e) {
            debugPrint('  $name: ERROR ($e)');
          }
        }
        debugPrint('────────────────────────────────');
      } catch (e) {
        debugPrint('logTablesAndCounts failed: $e');
      }
    }();
    return true;
  }());
}
}
