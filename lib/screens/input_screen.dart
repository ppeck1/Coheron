// lib/screens/input_screen.dart
// Coheron v2.3 — Input Architecture
//
// Interaction model:   3 → 3×3 → 3×3×3
//   3 Domains (primary radar, required)
//   3 Planes per Domain (optional expansion)
//   3 Indicators per Plane (optional expansion)
//
// Domain-only submission is valid (depth 1).
// Plane and Indicator layers are optional.
// Input = capture surface. No analysis widgets at top.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/entry_service.dart';
import '../services/app_events.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../theme/app_theme.dart';
import '../widgets/frequency_edit_dialog.dart';
import '../widgets/nested_radar_input.dart';
import '../widgets/phase2_charts.dart';

class InputScreen extends StatefulWidget {
  final DateTime? retroDate;
  final bool isEvent;
  final int? editEntryId;

  const InputScreen({
    super.key,
    this.retroDate,
    this.isEvent = false,
    this.editEntryId,
  });

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  // ── Values: metric_id → 0-100 ───────────────────────────────────────────────
  final Map<String, int> _values = {};

  // ── Entry metadata ──────────────────────────────────────────────────────────
  DateTime _entryDate = DateTime.now();
  final _labelCtrl = TextEditingController();
  final _noteCtrl  = TextEditingController();
  bool _saving         = false;
  bool _loadingEdit    = false;
  EntryType? _editType;

  FrequencyComposition _freq = FrequencyComposition(
      sense: 25, maintain: 25, explore: 25, enforce: 25);
  TemperamentComposition _temperament = const TemperamentComposition(
      choleric: 25, sanguine: 25, melancholic: 25, pragmatic: 25);

  // ── Optional: show/hide the frequency composition card ──────────────────────
  bool _showFrequency = false;

  @override
  void initState() {
    super.initState();
    if (widget.retroDate != null) _entryDate = widget.retroDate!;

    // Seed domain values (domain-only entry is valid at depth 1)
    for (final domainId in getDomainIds()) {
      _values[domainId] = 50;
    }

    if (widget.editEntryId != null) {
      _loadingEdit = true;
      _loadForEdit(widget.editEntryId!);
    } else {
      _loadFrequencyForNewEntry();
    }
  }

  Future<void> _loadFrequencyForNewEntry() async {
    try {
      final last = await EntryService.instance.getLastKnownFrequencyComposition();
      if (last != null && mounted) setState(() => _freq = last.normalized());
    } catch (_) {}
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadForEdit(int entryId) async {
    final db = DatabaseHelper.instance;
    final entry = await db.getEntryById(entryId, includeDeleted: true);
    if (entry == null) {
      if (mounted) setState(() => _loadingEdit = false);
      return;
    }
    final vals = await db.getMetricValuesForEntry(entryId);
    DateTime date = DateTime.tryParse(entry.timestamp) ?? DateTime.now();
    if (date.year == 1970) {
      date = DateTime.tryParse('${entry.date}T12:00:00') ?? DateTime.now();
    }
    final fc = await EntryService.instance.getFrequencyComposition(entryId);

    if (!mounted) return;
    setState(() {
      _editType = entry.entryType;
      _entryDate = date;
      _labelCtrl.text = entry.eventLabel ?? '';
      _values
        ..clear()
        ..addAll(vals.map((k, v) => MapEntry(k, v)));
      // Ensure domain values exist
      for (final domainId in getDomainIds()) {
        _values.putIfAbsent(domainId, () => 50);
      }
      if (fc != null) _freq = fc.normalized();
      _loadingEdit = false;
    });
  }

  EntryType get _effectiveType {
    if (_editType != null) return _editType!;
    return widget.isEvent
        ? EntryType.event
        : widget.retroDate != null
            ? EntryType.retro
            : EntryType.baseline;
  }

  bool get _showEventLabel => _effectiveType == EntryType.event;
  bool get _showDatePicker => _effectiveType != EntryType.baseline;

  // ── Depth: 1=domains only, 2=any plane, 3=any indicator ─────────────────────
  int get _depthLevel {
    final ids = _values.keys.toSet();
    if (ids.any((id) => id.startsWith('LEAF.'))) return 3;
    if (ids.any((id) => id.startsWith('L2.'))) return 2;
    return 1;
  }

  // ── Plane expansion helpers ──────────────────────────────────────────────────




  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final tsDate = DateFormat('yyyy-MM-dd').format(_entryDate);
      final ts = (_entryDate.year == now.year &&
              _entryDate.month == now.month &&
              _entryDate.day == now.day)
          ? now.toIso8601String()
          : _entryDate.copyWith(hour: 12).toIso8601String();

      // Ensure domain values are present
      for (final domainId in getDomainIds()) {
        _values.putIfAbsent(domainId, () => 50);
      }

      final domainVals = getDomainIds()
          .where(_values.containsKey)
          .map((id) => _values[id]!.toDouble())
          .toList();
      final overall = domainVals.isEmpty
          ? 50.0
          : domainVals.reduce((a, b) => a + b) / domainVals.length;

      final entry = Entry(
        date:              tsDate,
        timestamp:         ts,
        entryType:         _effectiveType,
        eventLabel:        _showEventLabel
            ? (_labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim())
            : null,
        overallScore:      overall,
        completionPercent: (_values.length / 39 * 100).clamp(0, 100),
        depthLevel:        _depthLevel,
      );

      if (widget.editEntryId == null) {
        await EntryService.instance.saveEntryWithMetrics(
          entry:        entry,
          metricValues: Map<String, int>.from(_values),
          frequency:    _freq,
          temperament:  _temperament,
          depthLevel:   _depthLevel,
        );
      } else {
        await EntryService.instance.updateEntryWithMetrics(
          entryId:     widget.editEntryId!,
          entry:       entry,
          metricValues: Map<String, int>.from(_values),
          frequency:   _freq,
          temperament: _temperament,
        );
      }

      if (mounted) {
        AppEvents.notifyEntrySaved();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entry saved.'),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 2),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.editEntryId != null
              ? 'Edit Entry'
              : _effectiveType == EntryType.event
                  ? 'Log Event'
                  : _effectiveType == EntryType.retro
                      ? 'Backfill Entry'
                      : 'Check-In',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'How to rate',
            icon: const Icon(Icons.help_outline, color: AppTheme.textLight),
            onPressed: _showRatingHelp,
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary),
              ),
            )
          else
            TextButton(
              onPressed: _submit,
              child: const Text('Save',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
        ],
      ),
      body: _loadingEdit
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // ── Date picker (event / retro only) ──────────────────────────
                if (_showDatePicker) ...[
                  _DateRow(
                    date: _entryDate,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _entryDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _entryDate = picked);
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Event label ────────────────────────────────────────────────
                if (_showEventLabel) ...[
                  _LabelField(ctrl: _labelCtrl),
                  const SizedBox(height: 10),
                ],

                // ── PRIMARY: Recursive radar input ────────────────────────────
                //   Domain radar → tap → Plane radar → tap → Indicator radar
                //   All depth levels use the same radial grammar.
                NestedRadarInput(
                  values: _values,
                  onValuesChanged: (updated) => setState(() {
                    _values
                      ..clear()
                      ..addAll(updated);
                  }),
                ),
                const SizedBox(height: 8),
                _DepthIndicator(depth: _depthLevel, valueCount: _values.length),
                const SizedBox(height: 16),

                // ── Frequency (optional, collapsed by default) ─────────────────
                _FrequencyToggleCard(
                  freq: _freq,
                  visible: _showFrequency,
                  onToggle: () => setState(() => _showFrequency = !_showFrequency),
                  onEdit: () async {
                    final res = await showDialog<FrequencyComposition>(
                      context: context,
                      builder: (_) => FrequencyEditDialog(initial: _freq),
                    );
                    if (res != null && mounted) {
                      setState(() => _freq = res.normalized());
                    }
                  },
                ),
                const SizedBox(height: 10),

                // ── Optional note ──────────────────────────────────────────────
                _NoteField(ctrl: _noteCtrl),
              ],
            ),
    );
  }

  void _showRatingHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Center(
              child: Text('How to rate',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            SizedBox(height: 12),
            Text('• 0 = worst plausible state for you; 100 = best.',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark)),
            SizedBox(height: 6),
            Text('• Domains are the required minimum. Planes and Indicators are optional detail.',
                style: TextStyle(fontSize: 13, color: AppTheme.textDark)),
            SizedBox(height: 10),
            Text('DOMAINS', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppTheme.textLight, letterSpacing: 0.8)),
            SizedBox(height: 4),
            Text('Internal = Body/Attention/Affect.  External = Safety/Support/Demands.  Output = Follow-through/Activity/Recovery.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMed)),
          ],
        ),
      ),
    );
  }
}

// ─── Frequency toggle card ────────────────────────────────────────────────────

class _FrequencyToggleCard extends StatelessWidget {
  final FrequencyComposition freq;
  final bool visible;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _FrequencyToggleCard({
    required this.freq,
    required this.visible,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Text('Frequency modes',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textDark)),
              const Spacer(),
              Text(
                  'S${freq.sense} M${freq.maintain} E${freq.explore} F${freq.enforce}',
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textLight)),
              const SizedBox(width: 6),
              Icon(
                visible
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppTheme.textLight,
              ),
            ]),
          ),
        ),
        if (visible) ...[
          Divider(height: 1, color: AppTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: [
              FrequencyRadar(
                sense: freq.sense,
                maintain: freq.maintain,
                explore: freq.explore,
                enforce: freq.enforce,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onEdit, child: const Text('Edit')),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─── Support widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label, subtitle;
  const _SectionHeader({required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: AppTheme.textLight,
              letterSpacing: 1.0)),
      const SizedBox(height: 2),
      Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
    ],
  );
}

class _DateRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  const _DateRow({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEE, MMMM d yyyy').format(date);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 15, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.edit_outlined, size: 13, color: AppTheme.textLight),
        ]),
      ),
    );
  }
}

class _LabelField extends StatelessWidget {
  final TextEditingController ctrl;
  const _LabelField({required this.ctrl});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLength: 120,
    decoration: InputDecoration(
      hintText: 'Event label (optional)',
      hintStyle: const TextStyle(color: AppTheme.textLight, fontSize: 13),
      counterText: '',
      filled: true, fillColor: AppTheme.surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.divider)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}

class _NoteField extends StatelessWidget {
  final TextEditingController ctrl;
  const _NoteField({required this.ctrl});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: 2,
    maxLength: 240,
    decoration: InputDecoration(
      hintText: 'Optional note',
      hintStyle: const TextStyle(color: AppTheme.textLight, fontSize: 12),
      counterText: '',
      filled: true, fillColor: AppTheme.surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.divider)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    ),
  );
}

class _DepthIndicator extends StatelessWidget {
  final int depth;
  final int valueCount;
  const _DepthIndicator({required this.depth, required this.valueCount});

  @override
  Widget build(BuildContext context) {
    final label = depth == 1
        ? 'D1 — Domains'
        : depth == 2
            ? 'D2 — Domains + Planes'
            : 'D3 — Domains + Planes + Indicators';
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
        ),
        child: Text(
          '$label  ·  $valueCount values',
          style: const TextStyle(fontSize: 10, color: AppTheme.primary),
        ),
      ),
    ]);
  }
}
