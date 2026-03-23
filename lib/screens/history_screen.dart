// lib/screens/history_screen.dart
// v5: Shows entries from new MetricValue-based system.
// Tap to view detail. Swipe to delete (soft). No AreaRating.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../services/taxonomy_service.dart';
import '../services/app_events.dart';
import '../services/entry_service.dart';
import '../services/event_service.dart';
import 'input_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _query = '';
  final Set<EntryType> _types = {EntryType.baseline, EntryType.event, EntryType.retro};
  final Set<int> _depths = {1, 2, 3};

  // Phase 4B: event overlay counts per day.
  final Map<String, int> _eventCountByDate = {};

  void _setQuery(String s) {
    _query = s;
    setState(() {
      _rows = _applyFilters(_allRows);
    });
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((r) {
      // type filter
      final et = EntryTypeX.parse(r['entry_type'] as String?);
      if (!_types.contains(et)) return false;
      // depth filter
      final d = (r['depth_level'] as int?) ?? 1;
      if (!_depths.contains(d)) return false;
      // text filter (event label + tags)
      if (q.isEmpty) return true;
      final label = (r['event_label'] as String?)?.toLowerCase() ?? '';
      if (label.contains(q)) return true;
      final tags = (r['tags'] as List?)?.map((e)=>e.toString().toLowerCase()).toList() ?? const <String>[];
      return tags.any((t)=>t.contains(q));
    }).toList();
  }

  late final VoidCallback _entrySavedListener;

  @override
  void initState() {
    super.initState();
    _entrySavedListener = () => _load();
    AppEvents.entrySavedTick.addListener(_entrySavedListener);
    _load();
  }

  @override
  void dispose() {
    AppEvents.entrySavedTick.removeListener(_entrySavedListener);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getHistoryRows(limit: 120);
    // Phase 4B: overlay event counts by day for quick visual correlation.
    final dates = rows
        .map((r) => (r['date'] as String?) ?? '')
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    final counts = await EventService().countEventsByDates(dates);
    if (!mounted) return;
    setState(() {
      _allRows = rows;
      _rows = _applyFilters(rows);
      _eventCountByDate
        ..clear()
        ..addAll(counts);
      _loading = false;
    });
  }
  Future<void> _softDelete(int entryId) async {
    await DatabaseHelper.instance.softDeleteEntry(entryId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search + filter bar (was in AppBar.bottom)
        Container(
          color: AppTheme.background,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            children: [
              TextField(
                onChanged: _setQuery,
                decoration: InputDecoration(
                  hintText: 'Search event labels…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppTheme.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip(
                    label: 'Check-in',
                    selected: _types.contains(EntryType.baseline),
                    onTap: () {
                      setState(() {
                        _types.contains(EntryType.baseline)
                            ? _types.remove(EntryType.baseline)
                            : _types.add(EntryType.baseline);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                  _FilterChip(
                    label: 'Event',
                    selected: _types.contains(EntryType.event),
                    onTap: () {
                      setState(() {
                        _types.contains(EntryType.event)
                            ? _types.remove(EntryType.event)
                            : _types.add(EntryType.event);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                  _FilterChip(
                    label: 'Backfill',
                    selected: _types.contains(EntryType.retro),
                    onTap: () {
                      setState(() {
                        _types.contains(EntryType.retro)
                            ? _types.remove(EntryType.retro)
                            : _types.add(EntryType.retro);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'D1',
                    selected: _depths.contains(1),
                    onTap: () {
                      setState(() {
                        _depths.contains(1) ? _depths.remove(1) : _depths.add(1);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                  _FilterChip(
                    label: 'D2',
                    selected: _depths.contains(2),
                    onTap: () {
                      setState(() {
                        _depths.contains(2) ? _depths.remove(2) : _depths.add(2);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                  _FilterChip(
                    label: 'D3',
                    selected: _depths.contains(3),
                    onTap: () {
                      setState(() {
                        _depths.contains(3) ? _depths.remove(3) : _depths.add(3);
                        _rows = _applyFilters(_allRows);
                      });
                    },
                  ),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _rows.isEmpty
                  ? _EmptyHistory()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) => _EntryTile(
                          row: _rows[i],
                          eventCount: _eventCountByDate[(_rows[i]['date'] as String?) ?? ''] ?? 0,
                          onDelete: () => _softDelete(_rows[i]['id'] as int),
                          onTap: () async {
                            await Navigator.push(ctx,
                                MaterialPageRoute(builder: (_) => _EntryDetailScreen(
                                  entryId: _rows[i]['id'] as int,
                                  date: _rows[i]['date'] as String,
                                )));
                            _load();
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withOpacity(0.12) : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primary : AppTheme.textMed,
              )),
        ),
      ),
    );
  }
}


// ─── Entry tile ───────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final int eventCount;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _EntryTile({required this.row, required this.eventCount, required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date   = row['date'] as String;
    final type   = EntryTypeX.parse(row['entry_type'] as String?);
    final depth  = (row['depth_level'] as num?)?.toInt() ?? 1;
    final score  = (row['overall_score'] as num?)?.toDouble() ?? 0;
    final label  = row['event_label'] as String?;
    final tags   = (row['tags'] as List?)?.cast<String>() ?? [];

    final typeLabel = switch (type) {
      EntryType.baseline => 'Check-in',
      EntryType.event    => 'Event',
      EntryType.retro    => 'Backfill',
    };
    final typeColor = switch (type) {
      EntryType.baseline => AppTheme.primary,
      EntryType.event    => const Color(0xFFE8972D),
      EntryType.retro    => AppTheme.textLight,
    };

    final ts = DateTime.tryParse(row['timestamp'] as String? ?? '');
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts) : '';

    return Dismissible(
      key: ValueKey(row['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD94F3D).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFD94F3D)),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete entry?'),
            content: const Text('This will soft-delete the entry. Data is preserved.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD94F3D)),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: typeColor, width: 3),
            ),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4, offset: const Offset(0, 1),
            )],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(date, style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13,
                  color: AppTheme.textDark, fontFamily: 'monospace')),
              if (timeStr.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(timeStr, style: const TextStyle(
                    fontSize: 11, color: AppTheme.textLight,
                    fontFamily: 'monospace')),
              ],
              const Spacer(),
              if (eventCount > 0) ...[
                _Chip(label: '+$eventCount evt', color: const Color(0xFFE8972D)),
                const SizedBox(width: 6),
              ],
              _Chip(label: typeLabel, color: typeColor),
              const SizedBox(width: 6),
              _Chip(label: 'D$depth', color: AppTheme.textLight),
            ]),
            if (label != null) ...[
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(
                  fontSize: 12, color: AppTheme.textMed)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Text('Overall: ${score.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
              if (tags.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...tags.take(3).map((t) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _Chip(label: t, color: AppTheme.textLight),
                )),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 9, color: color,
            fontWeight: FontWeight.w500)),
  );
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined, size: 40,
            color: AppTheme.textLight),
        const SizedBox(height: 12),
        const Text('No entries yet.',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16,
                color: AppTheme.textDark)),
        const SizedBox(height: 6),
        const Text('Tap + to log your first check-in.',
            style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
      ]),
    ),
  );
}

// ─── Entry detail screen ──────────────────────────────────────────────────────

class _EntryDetailScreen extends StatefulWidget {
  final int entryId;
  final String date;
  const _EntryDetailScreen({required this.entryId, required this.date});

  @override
  State<_EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<_EntryDetailScreen> {
  Entry? _entry;
  Map<String, int> _values = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = DatabaseHelper.instance;
    final rows = await db.getHistoryRows(limit: 500);
    final row = rows.firstWhere(
        (r) => r['id'] == widget.entryId, orElse: () => {});
    if (row.isNotEmpty) {
      final entry = Entry.fromMap(row);
      final vals  = await db.getMetricValuesForEntry(widget.entryId);
      if (mounted) setState(() { _entry = entry; _values = vals; _loading = false; });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.date,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          if (_entry != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => InputScreen(editEntryId: widget.entryId)));
                await _load();

              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _entry == null
              ? const Center(child: Text('Entry not found.'))
              : _DetailBody(entry: _entry!, values: _values),
    );
  }
}

class _DetailBody extends StatefulWidget {
  final Entry entry;
  final Map<String, int> values;
  const _DetailBody({required this.entry, required this.values});

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  bool _tagsLoading = true;
  List<String> _tags = [];

  // Phase 4B: show events linked by day (overlay correlation).
  bool _eventsLoading = true;
  List<EventRecord> _events = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadEventsForDay();
  }

  Future<void> _loadEventsForDay() async {
    setState(() => _eventsLoading = true);
    final date = DateTime.tryParse(widget.entry.date);
    if (date == null) {
      if (!mounted) return;
      setState(() { _events = []; _eventsLoading = false; });
      return;
    }
    final start = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final ev = await EventService().listEvents(start: start, end: end);
    if (!mounted) return;
    setState(() { _events = ev; _eventsLoading = false; });
  }

  Future<void> _loadTags() async {
    setState(() => _tagsLoading = true);
    try {
      final tags = await EntryService.instance.getTagsForEntry(widget.entry.id!);
      if (mounted) setState(() => _tags = tags);
    } catch (_) {
      // ignore
    }
    if (mounted) setState(() => _tagsLoading = false);
  }

  Future<void> _editTags() async {
    final controller = TextEditingController(text: _tags.join(', '));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tags'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'comma-separated'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (res == null) return;
    final tags = res
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    if (widget.entry.id == null) return;
    await EntryService.instance.setTagsForEntry(widget.entry.id!, tags);
    await _loadTags();
    AppEvents.entrySavedTick.value++;
  }

  // ── Taxonomy helpers ────────────────────────────────────────────────────────

  static const _tax = TaxonomyService();

  /// Returns the canonical plane color for any metric ID.
  /// Plane → its own color. Field/Node → parent plane color.
  static Color _planeColorFor(String id) {
    final plane = getPlaneForId(id);
    return plane != null ? AppTheme.planeColor(plane) : AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;

    // Group using TaxonomyService.getTaxonomyLevelForId() — never raw string prefixes.
    final domainEntries    = <MapEntry<String, int>>[];
    final planeEntries     = <MapEntry<String, int>>[];
    final indicatorEntries = <MapEntry<String, int>>[];
    for (final e in values.entries) {
      switch (_tax.getTaxonomyLevelForId(e.key)) {
        case TaxonomyLevel.domain:    domainEntries.add(e);
        case TaxonomyLevel.plane:     planeEntries.add(e);
        case TaxonomyLevel.indicator: indicatorEntries.add(e);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // Meta card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.entry.entryType.name,
                  style: const TextStyle(fontWeight: FontWeight.w600,
                      fontSize: 13, color: AppTheme.textDark))),
              // Depth pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Text('D${widget.entry.depthLevel}  ·  ${values.length}m',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
              ),
            ]),
            if (widget.entry.eventLabel != null) ...[
              const SizedBox(height: 4),
              Text(widget.entry.eventLabel!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMed)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              const Text('Tags:', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tagsLoading ? '…' : (_tags.isEmpty ? '—' : _tags.join(', ')),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMed),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: _editTags, child: const Text('Edit')),
            ]),
          ]),
        ),
        const SizedBox(height: 14),

        // Events for this day
        _sectionHeader('EVENTS'),
        const SizedBox(height: 6),
        if (_eventsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading…', style: TextStyle(color: AppTheme.textLight)),
          )
        else if (_events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No events for this day.', style: TextStyle(color: AppTheme.textLight)),
          )
        else
          ..._events.map((e) => _EventCard(e: e)),

        const SizedBox(height: 14),

        // Domains — full-color bars
        if (domainEntries.isNotEmpty) ...[
          _sectionHeader('DOMAINS'),
          const SizedBox(height: 6),
          ...domainEntries.map((e) => _ValueRow(
            id: e.key, value: e.value,
            kind: TaxonomyLevel.domain,
            color: _planeColorFor(e.key),
          )),
          const SizedBox(height: 14),
        ],

        // Planes — tinted background (parent domain color @ 7%)
        if (planeEntries.isNotEmpty) ...[
          _sectionHeader('PLANES'),
          const SizedBox(height: 6),
          ...planeEntries.map((e) => _ValueRow(
            id: e.key, value: e.value,
            kind: TaxonomyLevel.plane,
            color: _planeColorFor(e.key),
          )),
          const SizedBox(height: 14),
        ],

        // Indicators — lighter tint
        if (indicatorEntries.isNotEmpty) ...[
          _sectionHeader('INDICATORS'),
          const SizedBox(height: 6),
          ...indicatorEntries.map((e) => _ValueRow(
            id: e.key, value: e.value,
            kind: TaxonomyLevel.indicator,
            color: _planeColorFor(e.key),
          )),
        ],

        if (values.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No metric values stored for this entry.',
                  style: TextStyle(color: AppTheme.textLight)),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String label) => Text(label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: AppTheme.textLight, letterSpacing: 0.8));
}

class _EventCard extends StatelessWidget {
  final EventRecord e;
  const _EventCard({required this.e});

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
    final ts = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    // EventRecord already stores a typed enum.
    final type = e.type;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(ts,
                style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textLight)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text(type.name,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                if ((e.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.notes!.trim(), style: const TextStyle(fontSize: 12, color: AppTheme.textMed)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String id;
  final int value;
  final TaxonomyLevel kind;
  final Color color;

  const _ValueRow({
    required this.id,
    required this.value,
    required this.kind,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // P0.1: Always use taxonomy label — never expose raw IDs.
    final label = getLabel(id);

    // P0.2: Visual weight scales with hierarchy depth.
    final double barHeight;
    final double fontSize;
    final Color bgColor;
    final double bgOpacity;

    switch (kind) {
      case TaxonomyLevel.domain:
        barHeight  = 10;
        fontSize   = 13;
        bgColor    = color;
        bgOpacity  = 0.0; // no tinted background — border provides identity
      case TaxonomyLevel.plane:
        barHeight  = 7;
        fontSize   = 12;
        bgColor    = color;
        bgOpacity  = 0.07;
      case TaxonomyLevel.indicator:
        barHeight  = 5;
        fontSize   = 11;
        bgColor    = color;
        bgOpacity  = 0.04;
    }

    final bool hasBackground = bgOpacity > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: hasBackground
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
          : EdgeInsets.zero,
      decoration: hasBackground
          ? BoxDecoration(
              color: bgColor.withOpacity(bgOpacity),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: color.withOpacity(0.4), width: 2.5),
              ),
            )
          : null,
      child: Row(children: [
        // Color dot for planes (replaces background for cleanliness)
        if (kind == TaxonomyLevel.domain) ...[
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 4)],
            ),
          ),
        ],
        Expanded(
          flex: 4,
          child: Text(label, style: TextStyle(
            fontSize: fontSize,
            fontWeight: kind == TaxonomyLevel.domain ? FontWeight.w700 : FontWeight.w500,
            color: AppTheme.textDark,
          )),
        ),
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: barHeight,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(
                color.withOpacity(kind == TaxonomyLevel.domain ? 0.9 : 0.65),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ),
      ]),
    );
  }
}