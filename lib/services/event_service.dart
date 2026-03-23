
// lib/services/event_service.dart
// Phase 3B: Event log + tags + scopes.
//
// This layer is descriptive. No prediction.
// Provenance is mandatory (source + optional calc_rule_id/calc_inputs_json).

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/models.dart';

class EventService {
  EventService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;
  final DatabaseHelper _db;

  Future<int> createEvent({
    required EventType type,
    required DateTime when,
    required String title,
    String? notes,
    List<String> tags = const [],
    List<String> domainIds = const [],
    List<String> planeIds = const [],
    List<String> indicatorIds = const [],
    String source = 'user',
    String? calcRuleId,
    String? calcInputsJson,
    String? metadataJson,
  }) async {
    final db = await _db.database;
    final ts = when.millisecondsSinceEpoch;
    final eventId = await db.insert('EventLog', {
      'event_type': type.value,
      'timestamp_ms': ts,
      'title': title,
      'notes': notes,
      'metadata_json': metadataJson,
      'source': source,
      'calc_rule_id': calcRuleId,
      'calc_inputs_json': calcInputsJson,
    });

    // tags
    for (final t in tags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final tagId = await _ensureTagId(db, t);
      await db.insert('EventTagJoin', {'event_id': eventId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // scopes
    Future<void> addScopes(String scopeType, List<String> ids) async {
      for (final id in ids.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        await db.insert('EventScope', {
          'event_id': eventId,
          'scope_type': scopeType,
          'scope_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    await addScopes('domain', domainIds);
    await addScopes('plane', planeIds);
    await addScopes('indicator', indicatorIds);

    return eventId;
  }

  Future<int> _ensureTagId(Database db, String tag) async {
    final rows = await db.query('EventTags', where: 'tag = ?', whereArgs: [tag], limit: 1);
    if (rows.isNotEmpty) return (rows.first['tag_id'] as int);
    return await db.insert('EventTags', {'tag': tag});
  }

  Future<List<EventRecord>> listEvents({
    DateTime? start,
    DateTime? end,
    EventType? type,
    String? tag,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (start != null) { where.add('timestamp_ms >= ?'); args.add(start.millisecondsSinceEpoch); }
    if (end != null) { where.add('timestamp_ms <= ?'); args.add(end.millisecondsSinceEpoch); }
    if (type != null) { where.add('event_type = ?'); args.add(type.value); }

    String sql = 'SELECT e.* FROM EventLog e';
    if (tag != null && tag.trim().isNotEmpty) {
      sql += '''
        JOIN EventTagJoin j ON j.event_id = e.event_id
        JOIN EventTags t ON t.tag_id = j.tag_id
      ''';
      where.add('t.tag = ?');
      args.add(tag.trim());
    }
    if (where.isNotEmpty) {
      sql += ' WHERE ' + where.join(' AND ');
    }
    sql += ' ORDER BY e.timestamp_ms DESC';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => EventRecord.fromMap(r)).toList();
  }

  Future<List<TagSummary>> listTags({String? prefix, int limit = 100}) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (prefix != null && prefix.trim().isNotEmpty) {
      where.add('t.tag LIKE ?');
      args.add('${prefix.trim()}%');
    }
    final sql = '''
      SELECT t.tag as tag, COUNT(j.event_id) as cnt
      FROM EventTags t
      LEFT JOIN EventTagJoin j ON j.tag_id = t.tag_id
      ${where.isNotEmpty ? 'WHERE ' + where.join(' AND ') : ''}
      GROUP BY t.tag
      ORDER BY cnt DESC, t.tag ASC
      LIMIT $limit
    ''';
    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => TagSummary(tag: (r['tag'] as String), count: (r['cnt'] as int?) ?? 0)).toList();
  }

  Future<List<String>> listScopesForEvent(int eventId) async {
    final db = await _db.database;
    final rows = await db.query('EventScope', where: 'event_id = ?', whereArgs: [eventId]);
    return rows.map((r) => '${r['scope_type']}:${r['scope_id']}').toList();
  }

  /// Returns YYYY-MM-DD -> event count for those dates.
  ///
  /// Uses localtime to match UI grouping.
  Future<Map<String, int>> countEventsByDates(List<String> dates) async {
    if (dates.isEmpty) return {};
    final db = await _db.database;
    final placeholders = List.filled(dates.length, '?').join(',');
    const expr = "substr(datetime(timestamp_ms/1000,'unixepoch','localtime'),1,10)";
    final rows = await db.rawQuery(
      'SELECT $expr as d, COUNT(*) as c '
      'FROM EventLog '
      'WHERE $expr IN ($placeholders) '
      'GROUP BY d',
      dates,
    );
    final out = <String, int>{};
    for (final r in rows) {
      final d = (r['d'] as String?) ?? '';
      final c = (r['c'] as int?) ?? 0;
      if (d.isNotEmpty) out[d] = c;
    }
    return out;
  }
}
