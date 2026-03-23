// PATCH: Safe frequency table detection + graceful fallback
// Replace your existing getFrequencyByDay method with this version.

Future<Map<String, List<int>>> getFrequencyByDay({
  required DateTime start,
  required DateTime end,
}) async {
  final db = await database;

  // Detect table existence
  final tableCheck = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%frequency%'",
  );

  if (tableCheck.isEmpty) {
    return {}; // No frequency table present
  }

  final possibleTables = [
    'frequency_composition',
    'FrequencyComposition',
    'frequencyComposition',
  ];

  String? tableName;
  for (final row in tableCheck) {
    final name = row['name']?.toString();
    if (possibleTables.contains(name)) {
      tableName = name;
      break;
    }
  }

  if (tableName == null) {
    return {}; // Unknown naming — fail soft
  }

  String ymd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  try {
    final rows = await db.rawQuery('''
      SELECT date, sense, maintain, explore, enforce
      FROM $tableName
      WHERE date BETWEEN ? AND ?
      ORDER BY date ASC
    ''', [ymd(start), ymd(end)]);

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
  } catch (_) {
    return {}; // Column mismatch — fail soft
  }
}
