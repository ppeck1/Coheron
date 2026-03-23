// lib/screens/reading_screen.dart
// Reading — Unified interpretation layer.
// Structure: Scaffold → Column → [section switcher | IndexedStack of views]
// Reading owns the AppBar. Subsections are views, not standalone screens.
//
// Sections: History | Patterns | Tags | Graphs

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'patterns_screen.dart';
import 'tag_explorer_screen.dart';
import 'system_views_screen.dart';

enum _ReadingSection { history, patterns, tags, graphs }

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  _ReadingSection _section = _ReadingSection.history;

  static const _labels = {
    _ReadingSection.history:  'History',
    _ReadingSection.patterns: 'Patterns',
    _ReadingSection.tags:     'Tags',
    _ReadingSection.graphs:   'Graphs',
  };

  static const _icons = {
    _ReadingSection.history:  Icons.calendar_month_rounded,
    _ReadingSection.patterns: Icons.waves_rounded,
    _ReadingSection.tags:     Icons.sell_outlined,
    _ReadingSection.graphs:   Icons.analytics_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'READING',
          style: CTypography.telemetryTitle.copyWith(
              color: AppTheme.textDark, letterSpacing: 3),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        titleSpacing: 16,
      ),
      body: Column(
        children: [
          _buildSectionBar(),
          Expanded(
            child: IndexedStack(
              index: _section.index,
              children: const [
                HistoryScreen(),
                PatternsScreen(),
                TagExplorerScreen(),
                SystemViewsScreen(isEmbedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBar() {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: _ReadingSection.values.map((s) {
          final selected = s == _section;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _section = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _icons[s],
                      size: 13,
                      color: selected ? AppTheme.primary : AppTheme.textLight,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _labels[s]!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? AppTheme.primary : AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
