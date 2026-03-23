
// lib/screens/events_timeline_screen.dart
// Phase 3B: Events timeline (descriptive).

import 'package:flutter/material.dart';
import '../services/event_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'create_event_screen.dart';

class EventsTimelineScreen extends StatefulWidget {
  const EventsTimelineScreen({super.key});

  @override
  State<EventsTimelineScreen> createState() => _EventsTimelineScreenState();
}

class _EventsTimelineScreenState extends State<EventsTimelineScreen> {
  final _svc = EventService();
  DateTime _end = DateTime.now();
  int _days = 30;
  EventType? _type;
  String? _tag;
  List<EventRecord> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final start = DateTime(_end.year, _end.month, _end.day).subtract(Duration(days: _days));
    final list = await _svc.listEvents(start: start, end: _end, type: _type, tag: _tag);
    setState(() => _events = list);
  }

  Future<void> _openCreateEvent() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CreateEventScreen()));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _openCreateEvent, icon: const Icon(Icons.add)),
        ],
      ),
      body: Column(
        children: [
          _filters(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _tile(_events[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DropdownButton<EventType?>(
            value: _type,
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: EventType.qualifying, child: Text('Qualifying')),
              DropdownMenuItem(value: EventType.refresh, child: Text('Refresh')),
              DropdownMenuItem(value: EventType.collapse, child: Text('Collapse')),
              DropdownMenuItem(value: EventType.note, child: Text('Note')),
            ],
            onChanged: (v) { setState(() => _type = v); _load(); },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by exact tag (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) { setState(() => _tag = v.trim().isEmpty ? null : v.trim()); _load(); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(EventRecord e) {
    final dt = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
    final ts = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    final badgeColor = switch (e.type) {
      EventType.collapse => Colors.redAccent,
      EventType.refresh => Colors.teal,
      EventType.qualifying => AppTheme.accent,
      _ => Colors.grey,
    };
    return ListTile(
      title: Text(e.title),
      subtitle: Text('$ts • ${e.type.value} • ${e.source}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.12),
          border: Border.all(color: badgeColor.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(e.type.value, style: TextStyle(color: badgeColor)),
      ),
    );
  }
}
