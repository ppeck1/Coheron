
// lib/screens/tag_explorer_screen.dart
// Phase 3B: Tag Explorer.

import 'package:flutter/material.dart';
import '../services/event_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class TagExplorerScreen extends StatefulWidget {
  const TagExplorerScreen({super.key});

  @override
  State<TagExplorerScreen> createState() => _TagExplorerScreenState();
}

class _TagExplorerScreenState extends State<TagExplorerScreen> {
  final _svc = EventService();
  String _prefix = '';
  List<TagSummary> _tags = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.listTags(prefix: _prefix.isEmpty ? null : _prefix);
    setState(() => _tags = list);
  }

  Future<void> _openTag(String tag) async {
    final events = await _svc.listEvents(tag: tag);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _TagDetailScreen(tag: tag, events: events)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Prefix filter (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) { _prefix = v.trim(); _load(); },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20),
                color: AppTheme.textLight,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _tags.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = _tags[i];
              return ListTile(
                title: Text(t.tag),
                trailing: Text('${t.count}', style: const TextStyle(color: AppTheme.textLight)),
                onTap: () => _openTag(t.tag),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TagDetailScreen extends StatelessWidget {
  const _TagDetailScreen({required this.tag, required this.events});
  final String tag;
  final List<EventRecord> events;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tag)),
      body: ListView.separated(
        itemCount: events.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = events[i];
          final dt = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
          final ts = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
          return ListTile(
            title: Text(e.title),
            subtitle: Text('$ts • ${e.type.value} • ${e.source}'),
          );
        },
      ),
    );
  }
}
