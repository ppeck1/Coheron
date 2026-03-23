// lib/widgets/series_picker.dart
// Multi-select series picker — Domain → Plane → Indicator hierarchy.

import 'package:flutter/material.dart';
import '../models/series_spec.dart';
import '../services/series_registry.dart';
import '../services/taxonomy_service.dart';
import '../theme/app_theme.dart';

class SeriesPicker extends StatefulWidget {
  final SeriesRegistry registry;
  final TaxonomyService taxonomy;
  final Set<String> selected;
  final Map<String, Color> colorById;
  final void Function(Set<String>) onChanged;

  const SeriesPicker({
    super.key,
    required this.registry,
    required this.taxonomy,
    required this.selected,
    required this.colorById,
    required this.onChanged,
  });

  @override
  State<SeriesPicker> createState() => _SeriesPickerState();
}

class _SeriesPickerState extends State<SeriesPicker> {
  String _q = '';
  String? _openDomain;
  String? _openPlane;
  List<SeriesSpec> _vitals = const [];
  bool _loadingVitals = true;

  @override
  void initState() {
    super.initState();
    _loadVitals();
  }

  Future<void> _loadVitals() async {
    final v = await widget.registry.vitals();
    if (!mounted) return;
    setState(() { _vitals = v; _loadingVitals = false; });
  }

  void _toggle(String id) {
    final next = {...widget.selected};
    if (next.contains(id)) next.remove(id); else next.add(id);
    widget.onChanged(next);
  }

  bool _match(String label) {
    if (_q.trim().isEmpty) return true;
    return label.toLowerCase().contains(_q.trim().toLowerCase());
  }

  Widget _sectionTitle(String title, {Widget? trailing}) => Row(children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    const Spacer(),
    if (trailing != null) trailing,
  ]);

  Widget _specRow(SeriesSpec s) {
    if (!_match(s.label)) return const SizedBox.shrink();
    final isSelected = widget.selected.contains(s.id);
    final color = widget.colorById[s.id];
    return CheckboxListTile(
      dense: true,
      value: isSelected,
      onChanged: (_) => _toggle(s.id),
      title: Row(children: [
        if (color != null && isSelected) ...[
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 3)],
            ),
          ),
        ],
        Expanded(child: Text(s.label)),
      ]),
      subtitle: s.unit == null || s.unit!.isEmpty ? null : Text(s.unit!),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    // domains() returns 3 domain-level SeriesSpecs.
    final domainSpecs = widget.registry.domains();
    final freq = widget.registry.frequencyAxes();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search series…',
        ),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 10),

      _sectionTitle(
        'Selected (${widget.selected.length})',
        trailing: TextButton(
          onPressed: widget.selected.isEmpty ? null : () => widget.onChanged(<String>{}),
          child: const Text('Clear all'),
        ),
      ),
      const SizedBox(height: 6),
      if (widget.selected.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('None selected', style: TextStyle(color: AppTheme.textLight, fontSize: 12)),
        )
      else
        Wrap(
          spacing: 8, runSpacing: 8,
          children: widget.selected.map((id) {
            final label = widget.taxonomy.labelFor(id);
            final color = widget.colorById[id];
            return InputChip(
              avatar: color != null
                  ? Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    )
                  : null,
              label: Text(label),
              onDeleted: () => _toggle(id),
            );
          }).toList(),
        ),
      const Divider(height: 24),

      // Domain → Plane → Indicator tree
      _sectionTitle('Taxonomy'),
      const SizedBox(height: 6),
      ExpansionPanelList(
        expandedHeaderPadding: EdgeInsets.zero,
        expansionCallback: (idx, isOpen) {
          setState(() {
            _openDomain = isOpen ? null : domainSpecs[idx].id;
            _openPlane = null;
          });
        },
        children: domainSpecs.map((domain) {
          final isDomainOpen = _openDomain == domain.id;
          final planeSpecs = widget.registry.planesForDomain(domain.id);
          final domainColor = AppTheme.seriesPalette[AppTheme.planeColorIndex(domain.id)];
          return ExpansionPanel(
            isExpanded: isDomainOpen,
            headerBuilder: (_, __) => ListTile(
              leading: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: domainColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: widget.selected.contains(domain.id),
                  onChanged: (_) => _toggle(domain.id),
                  activeColor: domainColor,
                ),
              ]),
              title: Text(domain.label),
              subtitle: const Text('Domain',
                  style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
            ),
            body: Column(
              children: planeSpecs.map((plane) {
                final isPlaneOpen = _openPlane == plane.id;
                final indicatorSpecs = widget.registry.indicatorsForPlane(plane.id);
                return ExpansionTile(
                  key: ValueKey('plane_${plane.id}_$isPlaneOpen'),
                  initiallyExpanded: isPlaneOpen,
                  onExpansionChanged: (v) =>
                      setState(() => _openPlane = v ? plane.id : null),
                  title: Row(children: [
                    Checkbox(
                      value: widget.selected.contains(plane.id),
                      onChanged: (_) => _toggle(plane.id),
                      activeColor: domainColor,
                    ),
                    Expanded(child: Text(plane.label)),
                  ]),
                  subtitle: const Text('Plane',
                      style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                  children: indicatorSpecs.map((ind) {
                    if (!_match(ind.label)) return const SizedBox.shrink();
                    return CheckboxListTile(
                      dense: true,
                      value: widget.selected.contains(ind.id),
                      onChanged: (_) => _toggle(ind.id),
                      title: Text(ind.label),
                      subtitle: const Text('Indicator',
                          style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: domainColor,
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),

      const Divider(height: 24),
      _sectionTitle('Reflection'),
      const SizedBox(height: 4),
      ...freq.map(_specRow),

      const Divider(height: 24),
      _sectionTitle('Vitals'),
      const SizedBox(height: 4),
      if (_loadingVitals)
        const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
      else
        ..._vitals.map(_specRow),
      const SizedBox(height: 12),
    ]);
  }
}
