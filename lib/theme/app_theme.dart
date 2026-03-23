import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1A8A8A);
  static const Color primaryLight = Color(0xFF4DB8B8);
  static const Color primaryDark = Color(0xFF0D6060);
  static const Color accent = Color(0xFFFF4500);
  static const Color accentLight = Color(0xFFFF6B35);
  static const Color background = Color(0xFFF5F3F0);
  static const Color surface = Color(0xFFFFFFFF);
  // Slightly tinted surface used for neutral chips/cards.
  static const Color surfaceAlt = Color(0xFFF1EFEC);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textMed = Color(0xFF48484A);
  static const Color textLight = Color(0xFF636366);
  static const Color divider = Color(0xFFE5E3E0);
  static const Color cardShadow = Color(0x12000000);
  static const Color chartGray = Color(0xFF8E8E93);
  static const Color chartOrange = Color(0x40FF4500);

  // ── Series palette — 10 perceptually-distinct colors for graph lines ────────
  // Index 0–2 are the canonical plane colors (Internal / External / Output).
  // Remaining colors are assigned sequentially to fields, nodes, vitals, etc.
  static const List<Color> seriesPalette = [
    Color(0xFF2D6EBB), // 0  blue        → Internal (ROOT.I)
    Color(0xFF1A8A8A), // 1  teal        → External (ROOT.E)
    Color(0xFFE05C2A), // 2  orange      → Output   (ROOT.O)
    Color(0xFF7B44C0), // 3  purple
    Color(0xFF2FAF70), // 4  green
    Color(0xFFD4A017), // 5  amber
    Color(0xFFD1427A), // 6  pink/rose
    Color(0xFF3EAAA0), // 7  cyan-green
    Color(0xFF8B5E3C), // 8  brown
    Color(0xFF5C7A2D), // 9  olive
  ];

  /// Canonical palette index for a plane ID (for consistent cross-screen color).
  static int planeColorIndex(String planeId) {
    return switch (planeId) {
      'ROOT.I' => 0,
      'ROOT.E' => 1,
      'ROOT.O' => 2,
      _ => 1,
    };
  }

  /// Convenience: direct Color for a plane ID.
  static Color planeColor(String planeId) =>
      seriesPalette[planeColorIndex(planeId)];

  static ThemeData get theme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF111214) : const Color(0xFFF5F3F0);
    final surf    = isDark ? const Color(0xFF1A1C1F) : const Color(0xFFFFFFFF);
    final txtDark = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1C1C1E);
    final txtMed  = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF48484A);
    final txtLt   = isDark ? const Color(0xFF6B7280) : const Color(0xFF636366);
    final div     = isDark ? const Color(0xFF2A2D31) : const Color(0xFFE5E3E0);
    final prim    = isDark ? const Color(0xFF4DB8B8) : const Color(0xFF1A8A8A);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: prim,
        brightness: brightness,
        background: bg,
        surface: surf,
        primary: prim,
        secondary: const Color(0xFFFF4500),
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: txtDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: txtDark,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surf,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: div, width: 1),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: prim,
        thumbColor: prim,
        inactiveTrackColor: prim.withOpacity(0.2),
        overlayColor: prim.withOpacity(0.1),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        trackHeight: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surf,
        selectedColor: prim.withOpacity(0.15),
        labelStyle: TextStyle(fontSize: 13, color: txtDark),
        secondaryLabelStyle: TextStyle(fontSize: 13, color: prim, fontWeight: FontWeight.w600),
        side: BorderSide(color: div),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: true,
        checkmarkColor: prim,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surf,
        selectedItemColor: prim,
        unselectedItemColor: txtLt,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: div, thickness: 1, space: 1),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: txtDark, fontSize: 28, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(color: txtDark, fontSize: 22, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: txtDark, fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: txtDark, fontSize: 15, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: txtMed, fontSize: 15),
        bodyMedium: TextStyle(color: txtMed, fontSize: 13),
        labelSmall: TextStyle(color: txtLt, fontSize: 11),
      ),
    );
  }
}

// ─── Drift Map color tokens — resolve from current brightness ────────────────
// Usage: DriftColors.of(context).bg, .accent, etc.

class DriftColors {
  final Color bg;
  final Color card;
  final Color border;
  final Color accent;
  final Color accentDim;
  final Color textPrimary;
  final Color textSecondary;
  final Color gridLine;
  final Color ring7;

  const DriftColors._({
    required this.bg,
    required this.card,
    required this.border,
    required this.accent,
    required this.accentDim,
    required this.textPrimary,
    required this.textSecondary,
    required this.gridLine,
    required this.ring7,
  });

  static const _light = DriftColors._(
    bg:            Color(0xFFF7F7F9),
    card:          Color(0xFFFFFFFF),
    border:        Color(0xFFE5E7EB),
    accent:        Color(0xFFB89B5E),
    accentDim:     Color(0xFFAB9057),
    textPrimary:   Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    gridLine:      Color(0xFFE5E7EB),
    ring7:         Color(0xFFD1D5DB),
  );

  static const _dark = DriftColors._(
    bg:            Color(0xFF111214),
    card:          Color(0xFF1A1C1F),
    border:        Color(0xFF2A2D31),
    accent:        Color(0xFFC7A96B),
    accentDim:     Color(0xFF8A7449),
    textPrimary:   Color(0xFFF3F4F6),
    textSecondary: Color(0xFF9CA3AF),
    gridLine:      Color(0xFF2A2D31),
    ring7:         Color(0xFF3A3F46),
  );

  static DriftColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }
}

// ─── Typography tokens — use these everywhere, never hardcode ────────────────
// Usage: CTypography.telemetry, .caption, .sectionLabel, etc.

class CTypography {
  // H1: page title (AppBar)
  static const pageTitle = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3,
  );

  // H2: section headers inside cards
  static const sectionTitle = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600,
  );

  // Body text
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);

  // Caption / secondary labels
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400);
  static const captionBold = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  // Monospace — telemetry, formulas, data readouts
  // fontFamily null = system default monospace via fontFeatures
  static const telemetry = TextStyle(
    fontFamily: 'monospace', fontSize: 12, letterSpacing: 0.2,
  );
  static const telemetrySmall = TextStyle(
    fontFamily: 'monospace', fontSize: 11, letterSpacing: 0.1,
  );
  static const telemetryLabel = TextStyle(
    fontFamily: 'monospace', fontSize: 9, letterSpacing: 1.8,
    fontWeight: FontWeight.w500,
  );
  static const telemetryTitle = TextStyle(
    fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600,
    letterSpacing: 2.5,
  );

  // Spacing constants (use as SizedBox(height: CSpacing.md))
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;

  // Padding constants
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 16);
}