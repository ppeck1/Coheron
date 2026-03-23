// lib/main.dart
// Atlas v2.0 — 3-tab navigation: Input / Atlas / Reading

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/input_screen.dart';
import 'screens/atlas_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/vitals_screen.dart';
import 'services/entry_service.dart';
import 'services/app_events.dart';
import 'taxonomy/taxonomy_locked.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const CoheronApp());
}

class CoheronApp extends StatelessWidget {
  const CoheronApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coheron',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const _Shell(),
    );
  }
}

// ─── Shell ────────────────────────────────────────────────────────────────────

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 1; // Atlas is the default home

  static const _tabs = [
    _TabItem(icon: Icons.edit_note_rounded,    label: 'Input'),
    _TabItem(icon: Icons.grid_view_rounded,    label: 'Atlas'),
    _TabItem(icon: Icons.auto_stories_rounded, label: 'Reading'),
  ];

  final List<Widget> _screens = const [
    _InputTab(),
    AtlasScreen(),
    ReadingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: _buildFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildFab(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      onPressed: () => _showAddMenu(context),
      child: const Icon(Icons.add, size: 26),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEntrySheet(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab      = _tabs[i];
              final selected = i == _index;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _index = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(tab.icon, size: 22,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textLight),
                      ),
                      const SizedBox(height: 2),
                      Text(tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: selected ? AppTheme.primary : AppTheme.textLight,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─── Add entry sheet ──────────────────────────────────────────────────────────

class _AddEntrySheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
        ),
        const Text('Add Entry',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 20),
        _option(context,
          icon: Icons.edit_note_rounded,
          title: 'Check-In',
          subtitle: 'Capture current state across all domains',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const InputScreen()));
          },
        ),
        const SizedBox(height: 10),
        _option(context,
          icon: Icons.flash_on_rounded,
          title: 'Log Event',
          subtitle: 'Mark a specific event and rate affected domains',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const InputScreen(isEvent: true)));
          },
        ),
        const SizedBox(height: 10),
        _option(context,
          icon: Icons.history_rounded,
          title: 'Backfill',
          subtitle: 'Add an entry for a past date',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => InputScreen(
                    retroDate: DateTime.now()
                        .subtract(const Duration(days: 1)))));
          },
        ),
        const SizedBox(height: 10),
        _option(context,
          icon: Icons.monitor_heart_outlined,
          title: 'Log Vital',
          subtitle: 'BP, HR, temperature, weight, glucose',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VitalsScreen()));
          },
        ),
      ]),
    );
  }

  Widget _option(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
              Text(subtitle, style: const TextStyle(
                  color: AppTheme.textLight, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textLight, size: 20),
        ]),
      ),
    );
  }
}

// ─── Input tab — simplified capture surface, no graphs ───────────────────────

class _InputTab extends StatefulWidget {
  const _InputTab();

  @override
  State<_InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<_InputTab> {
  bool _loading = true;
  bool _hasEntry = false;
  DateTime? _lastTs;
  double _coverage = 0;

  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () => _load();
    AppEvents.entrySavedTick.addListener(_listener);
    _load();
  }

  @override
  void dispose() {
    AppEvents.entrySavedTick.removeListener(_listener);
    super.dispose();
  }

  Future<void> _load() async {
    final entry = await EntryService.instance.getCurrentEntry();
    if (mounted) {
      setState(() {
        _loading = false;
        _hasEntry = entry != null;
        _lastTs = entry != null ? DateTime.tryParse(entry.timestamp) : null;
        _coverage = entry?.completionPercent ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INPUT',
              style: CTypography.telemetryTitle.copyWith(
                  color: AppTheme.textDark, letterSpacing: 3)),
          const SizedBox(height: 4),
          Text(
            'Triadic radar capture · Domains → Planes → Indicators',
            style: CTypography.caption.copyWith(color: AppTheme.textLight),
          ),
          const SizedBox(height: 32),

          if (_hasEntry && _lastTs != null) ...[
            _statusCard(context),
            const SizedBox(height: 20),
          ],

          // Primary CTA
          _inputButton(
            context,
            icon: Icons.edit_note_rounded,
            label: _hasEntry ? 'Update Check-In' : 'Start Check-In',
            subtitle: 'Capture current state — domains, planes, indicators',
            primary: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const InputScreen())),
          ),
          const SizedBox(height: 12),
          _inputButton(
            context,
            icon: Icons.flash_on_rounded,
            label: 'Log Event',
            subtitle: 'Mark a specific event and rate affected domains',
            primary: false,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const InputScreen(isEvent: true))),
          ),
          const SizedBox(height: 12),
          _inputButton(
            context,
            icon: Icons.history_rounded,
            label: 'Backfill Entry',
            subtitle: 'Add an entry for a past date',
            primary: false,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => InputScreen(
                    retroDate: DateTime.now().subtract(const Duration(days: 1))))),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final ts = _lastTs!;
    final label =
        '${ts.month}/${ts.day}/${ts.year}  ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
              color: AppTheme.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Last entry',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.textLight, letterSpacing: 0.5)),
            Text(label,
                style: CTypography.telemetry
                    .copyWith(fontSize: 12, color: AppTheme.textDark)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_coverage.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _coverage > 60
                      ? AppTheme.primary
                      : _coverage > 30
                          ? const Color(0xFFD4A017)
                          : AppTheme.accent)),
          const Text('coverage',
              style: TextStyle(fontSize: 9, color: AppTheme.textLight)),
        ]),
      ]),
    );
  }

  Widget _inputButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final color = primary ? AppTheme.primary : AppTheme.textMed;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? AppTheme.primary.withOpacity(0.06) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primary
                ? AppTheme.primary.withOpacity(0.4)
                : AppTheme.divider,
            width: primary ? 1.5 : 1.0,
          ),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: primary ? AppTheme.primary : AppTheme.textDark)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textLight)),
                ]),
          ),
          Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 20),
        ]),
      ),
    );
  }
}

// ─── Tab item ─────────────────────────────────────────────────────────────────

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}
