// lib/screens/system_views_screen.dart
// System Graphs — selection-first, color-coded, persistent.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../services/series_registry.dart';
import '../services/taxonomy_service.dart';
import '../theme/app_theme.dart';
import '../widgets/phase2_charts.dart';
import '../widgets/series_picker.dart';

class SystemViewsScreen extends StatefulWidget {
  /// Optional pre-selection — overrides the persisted selection on first open.
  final Set<String>? initialSelected;

  /// When true, omits the outer Scaffold/AppBar so this widget can be
  /// embedded inside another Scaffold (e.g. Reading screen).
  final bool isEmbedded;

  const SystemViewsScreen({super.key, this.initialSelected, this.isEmbedded = false});

  @override
  State<SystemViewsScreen> createState() => _SystemViewsScreenState();
}

class _SystemViewsScreenState extends State<SystemViewsScreen> {
  static const _prefsKey      = 'system_graphs_v1';
  static const _colorPrefsKey = 'system_graphs_colors_v1';

  final _db = DatabaseHelper.instance;
  late final TaxonomyService _taxonomy;
  late final SeriesRegistry _registry;

  // Selection-first
  Set<String> _selected = const {'ROOT.I', 'ROOT.E', 'ROOT.O'};

  // Per-series color (palette index, 0–9)
  // Default: planes get their canonical index; others get sequential.
  Map<String, int> _colorIndexById = {};

  // Range
  int _days = 30;
  DateTime _end = DateTime.now();

  // Display controls
  bool _band = false;
  bool _normalize01 = false;

  // Cache
  String _cacheKey = '';
  _GraphData? _cache;

  // Reload token so FutureBuilder triggers on state change
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _taxonomy = const TaxonomyService();
    _registry = SeriesRegistry(taxonomy: _taxonomy, db: _db);

    // If caller supplied an initial selection, use it instead of prefs.
    if (widget.initialSelected != null && widget.initialSelected!.isNotEmpty) {
      _selected = widget.initialSelected!;
      _applyDefaultColors(_selected);
      _loadPrefs(skipSelection: true); // still load range/band prefs
    } else {
      _loadPrefs();
    }
  }

  DateTime get _start => _end.subtract(Duration(days: _days - 1));

  /// True when the selected set differs from the default three-plane view.
  bool get _isFiltered {
    const def = {'ROOT.I', 'ROOT.E', 'ROOT.O'};
    return _selected.length != def.length || !_selected.containsAll(def);
  }

  // ── Default color assignment ────────────────────────────────────────────────

  /// Assigns palette indices to any series that don't already have one.
  void _applyDefaultColors(Set<String> ids) {
    int nextFree = 3; // 0–2 reserved for planes
    for (final id in ids) {
      if (_colorIndexById.containsKey(id)) continue;
      if (id.startsWith('ROOT.')) {
        _colorIndexById[id] = AppTheme.planeColorIndex(id);
      } else {
        // Inherit plane-family color with an offset, or just sequential.
        _colorIndexById[id] = nextFree % AppTheme.seriesPalette.length;
        nextFree++;
      }
    }
  }

  Color _colorFor(String id) {
    final idx = _colorIndexById[id] ?? 0;
    return AppTheme.seriesPalette[idx.clamp(0, AppTheme.seriesPalette.length - 1)];
  }

  // ── Preferences ─────────────────────────────────────────────────────────────

  Future<void> _loadPrefs({bool skipSelection = false}) async {
    final p = await SharedPreferences.getInstance();

    // Colors
    final colorRaw = p.getString(_colorPrefsKey);
    if (colorRaw != null) {
      try {
        final m = jsonDecode(colorRaw) as Map<String, dynamic>;
        _colorIndexById = m.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }

    // Graph settings
    final raw = p.getString(_prefsKey);
    if (raw == null) {
      _applyDefaultColors(_selected);
      if (mounted) setState(() {});
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final sel = (m['selected'] as List?)?.map((e) => e.toString()).toSet();
      final days = (m['days'] as num?)?.toInt();
      final band = m['band'] == true;
      final norm = m['norm'] == true;
      if (!mounted) return;
      setState(() {
        if (!skipSelection && sel != null && sel.isNotEmpty) _selected = sel;
        if (days != null && days > 0) _days = days;
        _band = band;
        _normalize01 = norm;
        _applyDefaultColors(_selected);
      });
    } catch (_) {
      _applyDefaultColors(_selected);
      if (mounted) setState(() {});
    }
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode({
      'selected': _selected.toList(),
      'days': _days,
      'band': _band,
      'norm': _normalize01,
    }));
    await p.setString(_colorPrefsKey, jsonEncode(_colorIndexById));
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<_GraphData> _loadGraphData() async {
    final ids = _selected.toList()..sort();
    final key = '${_start.toIso8601String()}|${_end.toIso8601String()}|${ids.join(",")}|band=$_band|norm=$_normalize01';
    if (_cacheKey == key && _cache != null) return _cache!;

    final dates = List<DateTime>.generate(
      _days,
      (i) => DateTime(_start.year, _start.month, _start.day).add(Duration(days: i)),
    );
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final freqByDay = (_band || ids.any((id) => id.startsWith('FREQ.')))
        ? await _db.getFrequencyByDay(start: _start, end: _end)
        : <String, List<int>>{};
    final bandVectors = _band ? dates.map((d) => freqByDay[ymd(d)]).toList() : null;

    final seriesById = <String, List<double>>{};
    final labelsById = <String, String>{};
    final failedSeries = <String>[];

    for (final id in ids) {
      labelsById[id] = _labelForSeries(id);

      try {
        if (id.startsWith('FREQ.')) {
          final axis = id.substring('FREQ.'.length).toLowerCase();
          final vals = <double>[];
          for (final d in dates) {
            final v = freqByDay[ymd(d)];
            if (v == null) {
              vals.add(double.nan);
            } else {
              final idx = {'sense': 0, 'maintain': 1, 'explore': 2, 'enforce': 3}[axis] ?? 0;
              vals.add(v[idx].toDouble());
            }
          }
          seriesById[id] = _normalize01 ? _normalize(vals) : vals;
          continue;
        }

        if (id.startsWith('VITAL.')) {
          final keyOnly = id.substring('VITAL.'.length);
          final byDay = await _db.getVitalSeriesByDay(vitalKey: keyOnly, start: _start, end: _end);
          final vals = dates.map((d) => byDay[ymd(d)] ?? double.nan).toList();
          seriesById[id] = _normalize01 ? _normalize(vals) : vals;
          continue;
        }

        // Taxonomy metric
        final byDay = await _db.getMetricSeriesByDay(metricId: id, start: _start, end: _end);
        final vals = dates.map((d) => byDay[ymd(d)] ?? double.nan).toList();
        seriesById[id] = _normalize01 ? _normalize(vals) : vals;

      } catch (e, st) {
        debugPrint('[SystemGraphs] Series "$id" failed: $e\n$st');
        failedSeries.add(id);
      }
    }

    final out = _GraphData(
      dates: dates,
      seriesById: seriesById,
      labelsById: labelsById,
      bandVectors: bandVectors,
      failedSeries: failedSeries,
    );
    _cacheKey = key;
    _cache = out;
    return out;
  }

  // ── Labels ───────────────────────────────────────────────────────────────────

  static const _vitalLabels = <String, String>{
    'VITAL.hr':      'Heart rate',
    'VITAL.bp_sys':  'BP systolic',
    'VITAL.bp_dia':  'BP diastolic',
    'VITAL.temp':    'Temperature',
    'VITAL.spo2':    'SpO₂',
    'VITAL.glucose': 'Glucose',
  };

  String _labelForSeries(String id) {
    if (id.startsWith('FREQ.')) {
      final t = id.substring('FREQ.'.length).toLowerCase();
      return t.isEmpty ? 'Frequency' : (t[0].toUpperCase() + t.substring(1));
    }
    if (id.startsWith('VITAL.')) {
      return _vitalLabels[id] ?? _prettifyKey(id.substring('VITAL.'.length));
    }
    return _taxonomy.labelFor(id);
  }

  static String _prettifyKey(String key) {
    if (key.isEmpty) return 'Vital';
    final s = key.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  List<double> _normalize(List<double> v) {
    final xs = v.where((e) => e.isFinite).toList();
    if (xs.isEmpty) return v;
    final mn = xs.reduce((a, b) => a < b ? a : b);
    final mx = xs.reduce((a, b) => a > b ? a : b);
    final span = (mx - mn).abs() < 1e-9 ? 1.0 : (mx - mn);
    return v.map((e) => e.isFinite ? ((e - mn) / span) : double.nan).toList();
  }

  void _bustCacheAndReload() {
    setState(() {
      _cacheKey = '';
      _cache = null;
      _reloadToken++;
    });
  }

  // ── Color management ─────────────────────────────────────────────────────────

  /// Opens the color picker sheet for [id] and applies the chosen color.
  Future<void> _pickColorFor(String id) async {
    final current = _colorFor(id);
    final chosen = await showColorPickerSheet(context, currentColor: current);
    if (chosen == null || !mounted) return;
    final idx = AppTheme.seriesPalette.indexOf(chosen);
    if (idx < 0) return;
    setState(() => _colorIndexById[id] = idx);
    _savePrefs();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      // Embedded in Reading — no Scaffold/AppBar, just the content.
      return _buildContent(context);
    }

    final appBarBottom = _isFiltered
        ? PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppTheme.primary,
                  Color(0xFF2D6EBB),
                  Color(0xFFE05C2A),
                ]),
              ),
            ),
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Graphs'),
        bottom: appBarBottom,
        actions: [
          if (_isFiltered)
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 10, bottom: 10),
              child: GestureDetector(
                onTap: _openSeriesPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.layers_outlined, size: 13, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${_selected.length} series',
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Select series',
            icon: Icon(Icons.tune, color: _isFiltered ? AppTheme.primary : null),
            onPressed: _openSeriesPicker,
          ),
        ],
      ),
      body: SafeArea(child: _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final minY = 0.0;
    final maxY = _normalize01 ? 1.0 : 100.0;

    return Column(
      children: [
        // When embedded, show the series-picker action inline.
        if (widget.isEmbedded)
          _embeddedToolbar(),
        _controls(),
        Expanded(
          child: FutureBuilder<_GraphData>(
            key: ValueKey(_reloadToken),
            future: _loadGraphData(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _errorView(snap.error.toString());
              }
              if (!snap.hasData) {
                return const Center(child: Text('No data'));
              }

              final data = snap.data!;
              final colorById = {
                for (final id in data.seriesById.keys) id: _colorFor(id),
              };

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.failedSeries.isNotEmpty)
                      _failureBanner(data),
                    MultiLineChart(
                      seriesById: data.seriesById,
                      dates: data.dates,
                      labelsById: data.labelsById,
                      colorById: colorById,
                      minY: minY,
                      maxY: maxY,
                      bandVectors: _band ? data.bandVectors : null,
                      onLegendTap: _pickColorFor,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _embeddedToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Workspace', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark,
            )),
            Text(
              _isFiltered ? '${_selected.length} series selected' : 'Tap ⊞ to select series',
              style: const TextStyle(fontSize: 10, color: AppTheme.textLight),
            ),
          ]),
          const Spacer(),
          if (_isFiltered)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Text(
                '${_selected.length} series',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
            ),
          IconButton(
            tooltip: 'Select series',
            icon: Icon(Icons.tune, size: 20, color: _isFiltered ? AppTheme.primary : AppTheme.textLight),
            onPressed: _openSeriesPicker,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────────

  Widget _controls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.6))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Range chips
            const Text('Range ', style: TextStyle(fontSize: 12, color: AppTheme.textLight, fontWeight: FontWeight.w600)),
            ...([14, 30, 60, 90].map((d) {
              final sel = _days == d;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    if (_days == d) return;
                    setState(() => _days = d);
                    _savePrefs();
                    _bustCacheAndReload();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? AppTheme.primary : AppTheme.divider),
                    ),
                    child: Text(
                      '${d}d',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppTheme.textMed,
                      ),
                    ),
                  ),
                ),
              );
            })),
            const SizedBox(width: 8),
            const VerticalDivider(width: 1, thickness: 1),
            const SizedBox(width: 8),
            // Band toggle
            _toggle('Band', _band, (v) {
              setState(() => _band = v);
              _savePrefs();
              _bustCacheAndReload();
            }),
            const SizedBox(width: 12),
            // Normalize toggle
            _toggle('0–1', _normalize01, (v) {
              setState(() => _normalize01 = v);
              _savePrefs();
              _bustCacheAndReload();
            }),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMed)),
          const SizedBox(width: 4),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _failureBanner(_GraphData data) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            '${data.failedSeries.length} series skipped: '
            '${data.failedSeries.map((id) => data.labelsById[id] ?? id).join(', ')}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView(String msg) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Graphs failed to load.', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _bustCacheAndReload,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSeriesPicker() async {
    final next = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return Material(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: SeriesPicker(
                      registry: _registry,
                      taxonomy: _taxonomy,
                      selected: _selected,
                      colorById: {for (final id in _selected) id: _colorFor(id)},
                      onChanged: (s) => Navigator.of(ctx).pop(s),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (next != null && mounted) {
      setState(() {
        _selected = next.isEmpty ? const {'ROOT.I', 'ROOT.E', 'ROOT.O'} : next;
        _applyDefaultColors(_selected);
      });
      _savePrefs();
      _bustCacheAndReload();
    }
  }
}

// ── Data holder ──────────────────────────────────────────────────────────────

class _GraphData {
  final List<DateTime> dates;
  final Map<String, List<double>> seriesById;
  final Map<String, String> labelsById;
  final List<List<int>?>? bandVectors;
  final List<String> failedSeries;

  _GraphData({
    required this.dates,
    required this.seriesById,
    required this.labelsById,
    required this.bandVectors,
    this.failedSeries = const [],
  });
}
