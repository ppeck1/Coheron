// lib/screens/create_event_screen.dart
// Phase 4B.1: Full "Create Event" UI.
//
// Goals:
// - Single canonical event creation flow (type, tags, scopes, notes).
// - Provenance fields are present (calc_rule_id, calc_inputs_json) but hidden by default.
// - Uses locked taxonomy IDs for scope selection (domain/plane/indicator).

import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/event_service.dart';
import '../taxonomy/taxonomy_locked.dart';
import '../theme/app_theme.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, this.initialType, this.initialWhen});

  final EventType? initialType;
  final DateTime? initialWhen;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _svc = EventService();
  final _titleCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _tagCtl = TextEditingController();
  final _calcRuleCtl = TextEditingController();
  final _calcInputsCtl = TextEditingController(text: '{}');

  EventType _type = EventType.qualifying;
  DateTime _when = DateTime.now();
  bool _advanced = false;
  String _source = 'user';

  final List<String> _tags = [];
  final Set<String> _domainIds = {};
  final Set<String> _planeIds = {};
  final Set<String> _indicatorIds = {};

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? EventType.qualifying;
    _when = widget.initialWhen ?? DateTime.now();
    _titleCtl.text = _defaultTitle(_type);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _notesCtl.dispose();
    _tagCtl.dispose();
    _calcRuleCtl.dispose();
    _calcInputsCtl.dispose();
    super.dispose();
  }

  String _defaultTitle(EventType t) {
    return switch (t) {
      EventType.qualifying => 'Qualifying event',
      EventType.refresh => 'Refresh',
      EventType.collapse => 'Collapse',
      EventType.note => 'Note',
    };
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute);
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t == null) return;
    setState(() {
      _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute);
    });
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) return;
    setState(() => _tags.add(tag));
    _tagCtl.clear();
  }

  Future<void> _pickScopes(String scopeType) async {
    // scopeType: domain|plane|indicator
    final ids = switch (scopeType) {
      'domain' => getDomainIds(),
      'plane' => getPlaneIds(),
      'indicator' => getIndicatorIds(),
      _ => <String>[],
    };
    final selected = switch (scopeType) {
      'domain' => _domainIds,
      'plane' => _planeIds,
      'indicator' => _indicatorIds,
      _ => <String>{},
    };

    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final tmp = {...selected};
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx2, setSt) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select ${scopeType}s',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx2, tmp),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: ids.length,
                        itemBuilder: (_, i) {
                          final id = ids[i];
                          final node = kTaxonomy[id];
                          final label = node?.label ?? id;
                          final sub = node?.description ?? '';
                          final checked = tmp.contains(id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) => setSt(() {
                              if (v == true) tmp.add(id); else tmp.remove(id);
                            }),
                            title: Text(label),
                            subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (res == null) return;
    setState(() {
      selected
        ..clear()
        ..addAll(res);
    });
  }

  Future<void> _save() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) return;

    String? ruleId;
    String? inputsJson;
    if (_source != 'user') {
      ruleId = _calcRuleCtl.text.trim().isEmpty ? null : _calcRuleCtl.text.trim();
      final raw = _calcInputsCtl.text.trim().isEmpty ? '{}' : _calcInputsCtl.text.trim();
      // validate JSON
      try {
        jsonDecode(raw);
        inputsJson = raw;
      } catch (_) {
        // force valid JSON
        inputsJson = '{}';
      }
    }

    await _svc.createEvent(
      type: _type,
      when: _when,
      title: title,
      notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
      tags: List<String>.from(_tags),
      domainIds: _domainIds.toList(),
      planeIds: _planeIds.toList(),
      indicatorIds: _indicatorIds.toList(),
      source: _source,
      calcRuleId: ruleId,
      calcInputsJson: inputsJson,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ts = '${_when.year}-${_when.month.toString().padLeft(2, '0')}-${_when.day.toString().padLeft(2, '0')} '
        '${_when.hour.toString().padLeft(2, '0')}:${_when.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Create Event'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Type', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<EventType>(
                  value: _type,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: EventType.qualifying, child: Text('Qualifying')),
                    DropdownMenuItem(value: EventType.refresh, child: Text('Refresh')),
                    DropdownMenuItem(value: EventType.collapse, child: Text('Collapse')),
                    DropdownMenuItem(value: EventType.note, child: Text('Note')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _type = v;
                      // keep user-edited titles, otherwise update the default
                      final cur = _titleCtl.text.trim();
                      final defaults = {
                        _defaultTitle(EventType.qualifying),
                        _defaultTitle(EventType.refresh),
                        _defaultTitle(EventType.collapse),
                        _defaultTitle(EventType.note),
                      };
                      if (cur.isEmpty || defaults.contains(cur)) {
                        _titleCtl.text = _defaultTitle(v);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                const Text('When', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(ts, style: const TextStyle(fontFamily: 'monospace'))),
                    TextButton(onPressed: _pickDate, child: const Text('Date')),
                    TextButton(onPressed: _pickTime, child: const Text('Time')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Title', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleCtl,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtl,
                  maxLines: 4,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tags', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagCtl,
                        decoration: const InputDecoration(
                          hintText: 'Add tag…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _addTag(_tagCtl.text),
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags
                      .map((t) => InputChip(
                            label: Text(t),
                            onDeleted: () => setState(() => _tags.remove(t)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Scopes', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _scopeRow('Domains', _domainIds.length, () => _pickScopes('domain')),
                const SizedBox(height: 8),
                _scopeRow('Planes', _planeIds.length, () => _pickScopes('plane')),
                const SizedBox(height: 8),
                _scopeRow('Indicators', _indicatorIds.length, () => _pickScopes('indicator')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Provenance', style: TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => setState(() => _advanced = !_advanced),
                      child: Text(_advanced ? 'Hide advanced' : 'Show advanced'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _source,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('user')),
                    DropdownMenuItem(value: 'system', child: Text('system')),
                    DropdownMenuItem(value: 'import', child: Text('import')),
                  ],
                  onChanged: (v) => setState(() => _source = v ?? 'user'),
                ),
                if (_advanced && _source != 'user') ...[
                  const SizedBox(height: 10),
                  const Text('calc_rule_id', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _calcRuleCtl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  const Text('calc_inputs_json', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _calcInputsCtl,
                    maxLines: 4,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save Event'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }

  Widget _scopeRow(String label, int count, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(child: Text('$label ($count)')),
        TextButton(onPressed: onTap, child: const Text('Select')),
      ],
    );
  }
}
