// lib/screens/patterns_screen.dart
// System tab: Atomic (delta) and Stats (overlaid time-series) views.


import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/entry_service.dart';
import 'system_views_screen.dart';
import '../services/app_events.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../theme/app_theme.dart';
import '../widgets/phase2_charts.dart';

enum _PatternsMode { atomic, frequency }
enum _Level { domain, plane, indicator }

class PatternsScreen extends StatefulWidget {
  const PatternsScreen({super.key});
  @override
  State<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends State<PatternsScreen> {
  bool _loading = true;

  _PatternsMode _mode = _PatternsMode.atomic;
  _Level _level = _Level.domain;

  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 14)),
    end: DateTime.now(),
  );

  // Atomic
  Entry? _latest;
  Entry? _prev;
  Map<String, int> _latestVals = {};
  Map<String, int> _prevVals = {};

  // Atomic selection — which plane IDs to show in the overlay viz
  Set<String> _atomicSelected = {'ROOT.I', 'ROOT.E', 'ROOT.O'};

  // Frequency summaries
  final Map<String, _FreqSummary> _summaries = {};

  // Stats overlay selection — which series to display in the combined chart
  Set<String> _statsSelected = {};

  // Tag constraints
  bool _tagsLoading = true;
  final List<TagClause> _tagClauses = [];

  late final VoidCallback _entrySavedListener;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _entrySavedListener = () => _load();
    AppEvents.entrySavedTick.addListener(_entrySavedListener);
    _loadTags();
    _load();
  }

  @override
  void dispose() {
    AppEvents.entrySavedTick.removeListener(_entrySavedListener);
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadTags() async {
    setState(() => _tagsLoading = true);
    try {
      final tags = await EntryService.instance.getAllTags(limit: 200);
      _tagClauses
        ..clear()
        ..addAll(tags.map((t) => TagClause(tag: t)));
    } catch (_) {}
    if (mounted) setState(() => _tagsLoading = false);
  }

  List<String> get _includeTags =>
      _tagClauses.where((c) => c.state == Trinary.include).map((c) => c.tag).toList();
  List<String> get _excludeTags =>
      _tagClauses.where((c) => c.state == Trinary.exclude).map((c) => c.tag).toList();

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final svc = EntryService.instance;

    // Atomic
    final latest = await svc.getCurrentEntry();
    Entry? prev;
    Map<String, int> latestVals = {};
    Map<String, int> prevVals = {};
    if (latest?.id != null) {
      latestVals = await svc.getMetricValues(latest!.id!);
      prev = await svc.getPreviousEntry(latest.timestamp);
      if (prev?.id != null) prevVals = await svc.getMetricValues(prev!.id!);
    }

    // Frequency summaries with aligned date lists
    final hasClauses = _includeTags.isNotEmpty || _excludeTags.isNotEmpty;
    final entryIds = hasClauses
        ? await svc.getEntryIdsByTagClauses(includeTags: _includeTags, excludeTags: _excludeTags)
        : <int>[];
    final levelIds = _idsForLevel(_level);
    final freqOut = <String, _FreqSummary>{};
    for (final id in levelIds) {
      final series = (!hasClauses)
          ? await svc.getMetricSeries(id, _range.start, _range.end)
          : await svc.getMetricSeriesForEntryIds(id, _range.start, _range.end, entryIds);
      final stats = svc.computeStats(series);
      final lastVal = series.isEmpty ? null : (series.last['value'] as num).toInt();
      final values = series.map((r) => (r['value'] as num).toDouble()).toList();
      final dates = series.map((r) {
        final ds = (r['date'] as String?) ?? '';
        return ds.isEmpty ? _range.start : DateTime.tryParse(ds) ?? _range.start;
      }).toList();
      freqOut[id] = _FreqSummary(
        seriesCount: series.length,
        lastValue: lastVal,
        stats: stats,
        values: values,
        dates: dates,
      );
    }

    if (!mounted) return;
    setState(() {
      _latest = latest;
      _prev = prev;
      _latestVals = latestVals;
      _prevVals = prevVals;
      _summaries
        ..clear()
        ..addAll(freqOut);

      // Default stats selection: all IDs for current level
      if (_statsSelected.isEmpty || !_statsSelected.any((id) => freqOut.containsKey(id))) {
        _statsSelected = levelIds.toSet();
      }

      _loading = false;
    });
  }

  List<String> _idsForLevel(_Level level) {
    switch (level) {
      case _Level.domain:
        return getDomainIds();
      case _Level.plane:
        return getPlaneIds();
      case _Level.indicator:
        return getIndicatorIds();
    }
  }

  // ── Color helpers ─────────────────────────────────────────────────────────

  /// Canonical color for any taxonomy ID, derived from plane membership.
  Color _colorForId(String id) {
    if (id.startsWith('ROOT.I') || id.contains('.I.')) return AppTheme.seriesPalette[0];
    if (id.startsWith('ROOT.E') || id.contains('.E.')) return AppTheme.seriesPalette[1];
    if (id.startsWith('ROOT.O') || id.contains('.O.')) return AppTheme.seriesPalette[2];
    // Fall back by plane membership check via taxonomy
    final parentPlane = getPlaneForId(id);
    if (parentPlane != null) return AppTheme.planeColor(parentPlane);
    return AppTheme.primary;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _modeToggle(),
                const SizedBox(height: 12),
                if (_mode == _PatternsMode.atomic)
                  _atomicBody()
                else
                  _frequencyBody(),
              ],
            ),
          );
  }

  // ── Mode toggle ────────────────────────────────────────────────────────────

  Widget _modeToggle() {
    return Row(children: [
      Expanded(child: _segButton(
        label: 'Snapshot',
        sublabel: 'current state Δ',
        selected: _mode == _PatternsMode.atomic,
        onTap: () => setState(() => _mode = _PatternsMode.atomic),
      )),
      const SizedBox(width: 10),
      Expanded(child: _segButton(
        label: 'Trends',
        sublabel: 'series over time',
        selected: _mode == _PatternsMode.frequency,
        onTap: () => setState(() => _mode = _PatternsMode.frequency),
      )),
    ]);
  }

  Widget _segButton({required String label, required String sublabel, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.12) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.divider),
        ),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? AppTheme.primary : AppTheme.textMed,
          )),
          Text(sublabel, style: TextStyle(
            fontSize: 9,
            color: selected ? AppTheme.primary.withOpacity(0.7) : AppTheme.textLight,
          )),
        ])),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ATOMIC VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _atomicBody() {
    if (_latest == null) {
      return _infoCard('No entries yet.', 'Log at least one check-in to unlock atomic diffs.');
    }
    if (_prev == null) {
      return _infoCard('Need 2 entries.', 'Atomic view compares the latest entry to the previous one.');
    }

    final deltas = <_Delta>[];
    for (final kv in _latestVals.entries) {
      final prevV = _prevVals[kv.key];
      if (prevV == null) continue;
      final d = kv.value - prevV;
      if (d != 0) deltas.add(_Delta(id: kv.key, delta: d, value: kv.value, prev: prevV));
    }
    deltas.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _atomicHeader(),
      const SizedBox(height: 10),
      // Plane selector chips
      _atomicPlaneSelector(),
      const SizedBox(height: 10),
      // Single overlay bar chart for all selected planes
      _atomicOverlayViz(),
      const SizedBox(height: 10),
      // Unified delta list, color-coded by plane
      if (deltas.isEmpty)
        _infoCard('No movement.', 'Latest and previous entries are identical across recorded metrics.')
      else
        _unifiedDeltaList(deltas),
    ]);
  }

  Widget _atomicHeader() {
    String fmt(Entry e) {
      final dt = DateTime.tryParse(e.timestamp);
      return dt != null
          ? '${e.date}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : e.date;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Delta since previous entry',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: 10, height: 10, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF2E8B57), shape: BoxShape.circle))),
          const SizedBox(width: 6),
          Text('Latest: ${fmt(_latest!)}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
        ]),
        const SizedBox(height: 2),
        Row(children: [
          const SizedBox(width: 10, height: 10, child: DecoratedBox(decoration: BoxDecoration(color: AppTheme.textLight, shape: BoxShape.circle))),
          const SizedBox(width: 6),
          Text('Prev:   ${fmt(_prev!)}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
        ]),
      ]),
    );
  }

  Widget _atomicPlaneSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: getDomainIds().map((id) {
        final label = getLabel(id);
        final color = _colorForId(id);
        final selected = _atomicSelected.contains(id);
        return GestureDetector(
          onTap: () => setState(() {
            if (selected && _atomicSelected.length > 1) {
              _atomicSelected.remove(id);
            } else {
              _atomicSelected.add(id);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.12) : AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? color : AppTheme.divider, width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)] : [],
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppTheme.textLight,
              )),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _atomicOverlayViz() {
    final domainIds = getDomainIds().where((id) => _atomicSelected.contains(id)).toList();
    if (domainIds.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DOMAIN STATE', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppTheme.textLight, letterSpacing: 1.0,
        )),
        const SizedBox(height: 12),
        ...domainIds.map((id) {
          final curr = (_latestVals[id] ?? 0);
          final prev = (_prevVals[id] ?? curr);
          final color = _colorForId(id);
          final label = getLabel(id);
          return _atomicPlaneRow(label: label, current: curr, previous: prev, color: color);
        }),
        const SizedBox(height: 6),
        // Legend for current vs previous
        Row(children: [
          _legendDot(AppTheme.textLight, 'Previous'),
          const SizedBox(width: 14),
          _legendDot(null, 'Current (plane color)'),
        ]),
      ]),
    );
  }

  Widget _atomicPlaneRow({
    required String label,
    required int current,
    required int previous,
    required Color color,
  }) {
    final delta = current - previous;
    final sign = delta > 0 ? '+' : '';
    final deltaColor = delta > 0 ? const Color(0xFF2E8B57) : delta < 0 ? const Color(0xFFD94F3D) : AppTheme.textLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)])),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textDark))),
          Text('$sign$delta', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: deltaColor)),
          const SizedBox(width: 8),
          Text('$previous → $current', style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
        ]),
        const SizedBox(height: 5),
        Stack(
          children: [
            // Previous bar (grey background)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: previous / 100,
                minHeight: 10,
                backgroundColor: AppTheme.divider,
                valueColor: const AlwaysStoppedAnimation(AppTheme.chartGray),
              ),
            ),
            // Current bar (color, semi-transparent to let previous show through if current < previous)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: current / 100,
                minHeight: 10,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(color.withOpacity(0.85)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          Text('0',   style: TextStyle(fontSize: 8, color: AppTheme.textLight)),
          Text('50',  style: TextStyle(fontSize: 8, color: AppTheme.textLight)),
          Text('100', style: TextStyle(fontSize: 8, color: AppTheme.textLight)),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color? color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          color: color ?? AppTheme.primary,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textLight)),
    ]);
  }

  /// All deltas combined into one list, color-coded by plane.
  Widget _unifiedDeltaList(List<_Delta> deltas) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('ALL DELTAS', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppTheme.textLight, letterSpacing: 1.0,
          )),
          const Spacer(),
          Text('${deltas.length} changed', style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
        ]),
        const SizedBox(height: 10),
        ...deltas.map((d) => _deltaRow(d)),
      ]),
    );
  }

  Widget _deltaRow(_Delta d) {
    final label = getLabel(d.id);
    final sign = d.delta > 0 ? '+' : '';
    final color = _colorForId(d.id);
    final deltaColor = d.delta > 0 ? const Color(0xFF2E8B57) : const Color(0xFFD94F3D);
    final scopeLabel = d.id.startsWith('ROOT.') ? 'Domain'
        : d.id.startsWith('L2.')   ? 'Plane'
        : 'Indicator';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(children: [
        Container(width: 8, height: 8,
          margin: const EdgeInsets.only(right: 8, top: 2),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(scopeLabel, style: const TextStyle(fontSize: 9, color: AppTheme.textLight)),
          ]),
        ),
        // Mini bar showing prev → current
        SizedBox(
          width: 90,
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: d.prev / 100,
                minHeight: 6,
                backgroundColor: AppTheme.divider,
                valueColor: const AlwaysStoppedAnimation(AppTheme.chartGray),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: d.value / 100,
                minHeight: 6,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(color.withOpacity(0.8)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text('$sign${d.delta}',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: deltaColor)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATS / FREQUENCY VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _frequencyBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tagFilterPanel(),
      const SizedBox(height: 10),
      _rangeRow(),
      const SizedBox(height: 10),
      _levelPicker(),
      const SizedBox(height: 10),
      _statsOverlayChart(),
      const SizedBox(height: 10),
      _statsTable(),
    ]);
  }

  Widget _rangeRow() {
    String fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        const Icon(Icons.date_range, size: 16, color: AppTheme.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${fmt(_range.start)} – ${fmt(_range.end)}  (${_range.duration.inDays}d)',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMed),
          ),
        ),
        GestureDetector(
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              initialDateRange: _range,
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.primary),
                ),
                child: child!,
              ),
            );
            if (picked != null && mounted) {
              setState(() => _range = picked);
              _load();
            }
          },
          child: const Icon(Icons.edit_calendar_outlined, size: 18, color: AppTheme.primary),
        ),
      ]),
    );
  }

  Widget _levelPicker() {
    Widget chip(String label, _Level v) => ChoiceChip(
      label: Text(label),
      selected: _level == v,
      onSelected: (_) {
        setState(() {
          _level = v;
          _statsSelected = {}; // reset selection on level change
        });
        _load();
      },
      selectedColor: AppTheme.primary.withOpacity(0.12),
      labelStyle: TextStyle(
        color: _level == v ? AppTheme.primary : AppTheme.textMed,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: _level == v ? AppTheme.primary : AppTheme.divider),
      backgroundColor: AppTheme.surface,
      showCheckmark: false,
    );

    return Row(children: [
      chip('Domains', _Level.domain),
      const SizedBox(width: 8),
      chip('Planes', _Level.plane),
      const SizedBox(width: 8),
      chip('Indicators', _Level.indicator),
    ]);
  }

  // ── Stats overlay chart ───────────────────────────────────────────────────

  Widget _statsOverlayChart() {
    final ids = _idsForLevel(_level);
    final available = ids.where((id) => _summaries.containsKey(id)).toList();
    if (available.isEmpty) {
      return _infoCard('No data', 'No series found for the selected range and level.');
    }

    // Ensure selection is valid
    final selected = _statsSelected.isEmpty
        ? available.toSet()
        : _statsSelected.intersection(available.toSet());

    // Build aligned date list spanning the full range
    final totalDays = _range.duration.inDays + 1;
    final alignedDates = List<DateTime>.generate(
      totalDays,
      (i) => DateTime(_range.start.year, _range.start.month, _range.start.day).add(Duration(days: i)),
    );
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // Build aligned series maps (NaN for missing days)
    final seriesById = <String, List<double>>{};
    final labelsById = <String, String>{};
    final colorById  = <String, Color>{};

    for (final id in selected) {
      final s = _summaries[id];
      if (s == null) continue;
      labelsById[id] = getLabel(id);
      colorById[id]  = _colorForId(id);

      // Build day → value lookup from the summary's own date list
      final lookup = <String, double>{};
      for (int i = 0; i < s.values.length && i < s.dates.length; i++) {
        lookup[ymd(s.dates[i])] = s.values[i];
      }
      seriesById[id] = alignedDates.map((d) => lookup[ymd(d)] ?? double.nan).toList();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Series selector chips
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('TRENDS', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppTheme.textLight, letterSpacing: 1.0,
            )),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _statsSelected = available.toSet()),
              child: const Text('All', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _statsSelected = {available.first}),
              child: const Text('Reset', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: available.map((id) {
              final color = _colorForId(id);
              final isOn  = selected.contains(id);
              return GestureDetector(
                onTap: () => setState(() {
                  final next = Set<String>.from(selected);
                  if (isOn && next.length > 1) next.remove(id);
                  else next.add(id);
                  _statsSelected = next;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOn ? color.withOpacity(0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isOn ? color : AppTheme.divider, width: 1.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 9, height: 9,
                      decoration: BoxDecoration(
                        color: isOn ? color : color.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      getLabel(id),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOn ? color : AppTheme.textLight,
                      ),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ]),
      ),
      // The chart itself
      Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          border: Border(
            left: BorderSide(color: AppTheme.divider),
            right: BorderSide(color: AppTheme.divider),
            bottom: BorderSide(color: AppTheme.divider),
          ),
        ),
        child: seriesById.isEmpty
            ? const SizedBox(
                height: 100,
                child: Center(child: Text('Select at least one series above.',
                    style: TextStyle(color: AppTheme.textLight, fontSize: 12))),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: MultiLineChart(
                  seriesById: seriesById,
                  dates: alignedDates,
                  labelsById: labelsById,
                  colorById: colorById,
                  minY: 0,
                  maxY: 100,
                  // No legend tap here — colors are locked to taxonomy identity
                  onLegendTap: null,
                ),
              ),
      ),
    ]);
  }

  // ── Stats table ────────────────────────────────────────────────────────────

  Widget _statsTable() {
    final ids = _idsForLevel(_level);
    final available = ids.where((id) => _summaries.containsKey(id)).toList();
    final selected = _statsSelected.isEmpty
        ? available.toSet()
        : _statsSelected.intersection(available.toSet());
    final rows = available.where((id) => selected.contains(id)).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    String f1(double v) => v.toStringAsFixed(1);
    String f2(double v) => v.toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: const [
            SizedBox(width: 14),
            Expanded(child: Text('Series', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textLight, letterSpacing: 0.8))),
            _StatHeader('n'),
            _StatHeader('Last'),
            _StatHeader('Mean'),
            _StatHeader('σ'),
            _StatHeader('β'),
          ]),
        ),
        const Divider(height: 1),
        ...rows.map((id) {
          final s = _summaries[id]!;
          final color = _colorForId(id);
          final gated = _level == _Level.indicator && s.seriesCount < 7;
          return _statsTableRow(
            id: id,
            label: getLabel(id),
            color: color,
            s: s,
            gated: gated,
            f1: f1,
            f2: f2,
          );
        }),
      ]),
    );
  }

  Widget _statsTableRow({
    required String id,
    required String label,
    required Color color,
    required _FreqSummary s,
    required bool gated,
    required String Function(double) f1,
    required String Function(double) f2,
  }) {
    final betaColor = s.stats.beta > 0.5
        ? const Color(0xFF2E8B57)
        : s.stats.beta < -0.5
            ? const Color(0xFFD94F3D)
            : AppTheme.textMed;

    return InkWell(
      onTap: () {
        // Tap row → jump to System Graphs for this series
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SystemViewsScreen(initialSelected: {id}),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Container(width: 8, height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 3)])),
          Expanded(child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis)),
          _StatCell(s.seriesCount.toString()),
          _StatCell(s.lastValue?.toString() ?? '—'),
          _StatCell(gated ? '—' : f1(s.stats.mean)),
          _StatCell(gated ? '—' : f1(s.stats.sigma)),
          _StatCell(gated ? '—' : f2(s.stats.beta), color: betaColor),
        ]),
      ),
    );
  }

  // ── Tag filter ─────────────────────────────────────────────────────────────

  Widget _tagFilterPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('TAG FILTER', style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, color: AppTheme.textLight, letterSpacing: 0.8)),
          const Spacer(),
          Text('+${_includeTags.length} / −${_excludeTags.length}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
        ]),
        const SizedBox(height: 6),
        if (_tagsLoading)
          const Center(child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)))
        else if (_tagClauses.isEmpty)
          const Text('No tags yet.', style: TextStyle(fontSize: 12, color: AppTheme.textMed))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _tagClauses.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () { setState(() => c.state = c.state.next()); _load(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.state == Trinary.neutral ? AppTheme.surfaceAlt : AppTheme.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.state == Trinary.neutral ? AppTheme.divider : AppTheme.primary),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(c.state.glyph, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(c.tag, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              )).toList(),
            ),
          ),
      ]),
    );
  }

  Widget _infoCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: AppTheme.textLight)),
      ]),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _Delta {
  final String id;
  final int delta;
  final int value;
  final int prev;
  const _Delta({required this.id, required this.delta, required this.value, required this.prev});
}

class _FreqSummary {
  final int seriesCount;
  final int? lastValue;
  final MetricStats stats;
  final List<double> values;
  final List<DateTime> dates;
  const _FreqSummary({
    required this.seriesCount,
    required this.lastValue,
    required this.stats,
    required this.values,
    required this.dates,
  });
}

// ── Table helpers ──────────────────────────────────────────────────────────────

class _StatHeader extends StatelessWidget {
  final String text;
  const _StatHeader(this.text);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(text,
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: AppTheme.textLight, letterSpacing: 0.5)),
  );
}

class _StatCell extends StatelessWidget {
  final String text;
  final Color? color;
  const _StatCell(this.text, {this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(text,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 12, color: color ?? AppTheme.textMed,
          fontWeight: color != null ? FontWeight.w700 : FontWeight.normal,
          fontFamily: 'monospace')),
  );
}
