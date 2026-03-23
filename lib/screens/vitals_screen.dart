// lib/screens/vitals_screen.dart
// Self-contained vitals log — no provider dependency.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';

class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key});

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  List<Vital> _vitals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final v = await DatabaseHelper.instance.getRecentVitals(limit: 60);
    if (mounted) setState(() { _vitals = v; _loading = false; });
  }

  Future<void> _delete(String id) async {
    await DatabaseHelper.instance.deleteVital(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Vitals',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _LogVitalScreen()));
              _load();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Log'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _vitals.isEmpty
              ? _EmptyState(onAdd: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const _LogVitalScreen()));
                  _load();
                })
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: _vitals.length,
                    itemBuilder: (_, i) => _VitalTile(
                      vital: _vitals[i],
                      onDelete: () => _delete(_vitals[i].id),
                    ),
                  ),
                ),
    );
  }
}

class _VitalTile extends StatelessWidget {
  final Vital vital;
  final VoidCallback onDelete;
  const _VitalTile({required this.vital, required this.onDelete});

  String get _displayValue {
    if (vital.type == VitalType.bp) {
      return '${vital.value1?.round()}/${vital.value2?.round()} ${vital.unit ?? 'mmHg'}';
    }
    return '${vital.value1} ${vital.unit ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final ts = DateTime.tryParse(vital.timestamp);
    final timeStr = ts != null ? DateFormat('MMM d  HH:mm').format(ts) : vital.date;

    return Dismissible(
      key: ValueKey(vital.id),
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
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(vital.label ?? vital.type.label,
                  style: const TextStyle(fontWeight: FontWeight.w600,
                      fontSize: 13, color: AppTheme.textDark)),
              const SizedBox(height: 2),
              Text(timeStr,
                  style: const TextStyle(fontSize: 11,
                      color: AppTheme.textLight, fontFamily: 'monospace')),
              if (vital.note != null) ...[
                const SizedBox(height: 2),
                Text(vital.note!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
              ],
            ]),
          ),
          Text(_displayValue,
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 16, color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.monitor_heart_outlined,
            size: 40, color: AppTheme.textLight),
        const SizedBox(height: 12),
        const Text('No vitals logged.',
            style: TextStyle(fontWeight: FontWeight.w600,
                fontSize: 16, color: AppTheme.textDark)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onAdd,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Log first vital'),
        ),
      ]),
    ),
  );
}

// ─── Log vital screen ─────────────────────────────────────────────────────────

class _LogVitalScreen extends StatefulWidget {
  const _LogVitalScreen();

  @override
  State<_LogVitalScreen> createState() => _LogVitalScreenState();
}

class _LogVitalScreenState extends State<_LogVitalScreen> {
  VitalType _type = VitalType.bp;
  final _v1 = TextEditingController();
  final _v2 = TextEditingController();
  final _note = TextEditingController();
  final _label = TextEditingController();
  bool _saving = false;

  static const _units = {
    VitalType.bp:      'mmHg',
    VitalType.hr:      'bpm',
    VitalType.temp:    '°C',
    VitalType.weight:  'kg',
    VitalType.glucose: 'mg/dL',
    VitalType.sleep:   'h',
    VitalType.custom:  '',
  };

  @override
  void dispose() {
    _v1.dispose(); _v2.dispose(); _note.dispose(); _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final v1 = double.tryParse(_v1.text.trim());
    if (v1 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid value.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final vital = Vital(
        id:        const Uuid().v4(),
        date:      DateFormat('yyyy-MM-dd').format(now),
        timestamp: now.toIso8601String(),
        type:      _type,
        label:     _label.text.trim().isEmpty ? null : _label.text.trim(),
        value1:    v1,
        value2:    _type == VitalType.bp ? double.tryParse(_v2.text.trim()) : null,
        unit:      _units[_type],
        note:      _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      await DatabaseHelper.instance.saveVital(vital);
      AppEvents.notifyVitalSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Log Vital'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary)))
              : TextButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(color: AppTheme.primary,
                          fontWeight: FontWeight.w700))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Type selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            child: DropdownButton<VitalType>(
              value: _type,
              isExpanded: true,
              underline: const SizedBox(),
              items: VitalType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.label,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textDark)),
              )).toList(),
              onChanged: (t) => setState(() => _type = t!),
            ),
          ),
          const SizedBox(height: 12),

          // Custom label
          if (_type == VitalType.custom) ...[
            _field(_label, 'Label'),
            const SizedBox(height: 10),
          ],

          // Value fields
          if (_type == VitalType.bp)
            Row(children: [
              Expanded(child: _field(_v1, 'Systolic')),
              const SizedBox(width: 10),
              Expanded(child: _field(_v2, 'Diastolic')),
            ])
          else
            _field(_v1, 'Value (${_units[_type]})'),

          const SizedBox(height: 10),
          _field(_note, 'Note (optional)', maxLines: 2),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: maxLines == 1
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textLight, fontSize: 13),
          filled: true, fillColor: AppTheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.divider)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}
