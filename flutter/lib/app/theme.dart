import 'package:flutter/material.dart';

/// Home HD design tokens — the brief's two-column (dark/light) token set.
///
/// Every screen reads colours from [HdTokens] (via `Theme.of(context).extension`)
/// rather than literal colours, so light and dark both render correctly with no
/// per-screen branching. See docs/flutter-ui-brief.md "Colour tokens".
@immutable
class HdTokens extends ThemeExtension<HdTokens> {
  const HdTokens({
    required this.bg,
    required this.panel,
    required this.accent,
    required this.accentOn,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.good,
    required this.warning,
    required this.danger,
    required this.vital,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.surfaceContainer,
  });

  final Color bg; // screen background
  final Color panel; // cards, list rows, input fields
  final Color accent; // primary buttons, active states, links
  final Color accentOn; // text/icon on top of an accent fill
  final Color border; // outlines, dividers
  final Color textPrimary; // values, headings
  final Color textSecondary; // labels
  final Color textMuted; // hints, timestamps

  // Status colours — shade chosen per mode so flags stay legible on that bg.
  final Color good; // emerald — in-range / saved
  final Color warning; // amber — warning / stale
  final Color danger; // red — error / out-of-range / critical
  final Color vital; // rose — blood-pressure & heart metrics

  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color surfaceContainer;

  static const dark = HdTokens(
    bg: Color(0xFF0F172A),
    panel: Color(0xFF1E293B),
    accent: Color(0xFF22D3EE),
    accentOn: Color(0xFF0F172A),
    border: Color(0xFF334155),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    good: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    vital: Color(0xFFFB7185),
    primaryContainer: Color(0xFF004F58),
    onPrimaryContainer: Color(0xFF97F0FF),
    surfaceContainer: Color(0xFF162022),
  );

  static const light = HdTokens(
    bg: Color(0xFFFAFDFE),
    panel: Color(0xFFFFFFFF),
    accent: Color(0xFF006874),
    accentOn: Color(0xFFFFFFFF),
    border: Color(0xFFDBE4E6),
    textPrimary: Color(0xFF191C1D),
    textSecondary: Color(0xFF3F484A),
    textMuted: Color(0xFF6F797A),
    good: Color(0xFF2E7D32),
    warning: Color(0xFFE65100),
    danger: Color(0xFFB71C1C),
    vital: Color(0xFFE11D48),
    primaryContainer: Color(0xFF97F0FF),
    onPrimaryContainer: Color(0xFF001F24),
    surfaceContainer: Color(0xFFE8F7F9),
  );

  @override
  HdTokens copyWith({
    Color? bg,
    Color? panel,
    Color? accent,
    Color? accentOn,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? good,
    Color? warning,
    Color? danger,
    Color? vital,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? surfaceContainer,
  }) {
    return HdTokens(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      accent: accent ?? this.accent,
      accentOn: accentOn ?? this.accentOn,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      good: good ?? this.good,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      vital: vital ?? this.vital,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    );
  }

  @override
  HdTokens lerp(ThemeExtension<HdTokens>? other, double t) {
    if (other is! HdTokens) return this;
    return HdTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentOn: Color.lerp(accentOn, other.accentOn, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      vital: Color.lerp(vital, other.vital, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
    );
  }
}

/// Convenience accessor: `context.hd.accent`.
extension HdTokensContext on BuildContext {
  HdTokens get hd => Theme.of(this).extension<HdTokens>()!;
}

const _mono = 'monospace';

ThemeData _build(HdTokens t, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: brightness,
  ).copyWith(
    surface: t.panel,
    onSurface: t.textPrimary,
    error: t.danger,
  );

  // Every button is a full pill (StadiumBorder); ~52px comfortable height.
  final pill = WidgetStateProperty.all<OutlinedBorder>(const StadiumBorder());

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
    fontFamily: null,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: t.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        backgroundColor: WidgetStateProperty.all(t.accent),
        foregroundColor: WidgetStateProperty.all(t.accentOn),
        minimumSize: WidgetStateProperty.all(const Size(0, 52)),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        foregroundColor: WidgetStateProperty.all(t.accent),
        side: WidgetStateProperty.all(BorderSide(color: t.accent)),
        minimumSize: WidgetStateProperty.all(const Size(0, 48)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        foregroundColor: WidgetStateProperty.all(t.accent),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.accent,
      foregroundColor: t.accentOn,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.panel,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.accent, width: 2),
      ),
    ),
    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(bodyColor: t.textPrimary, displayColor: t.textPrimary),
  );
}

ThemeData hdLightTheme() => _build(HdTokens.light, Brightness.light);
ThemeData hdDarkTheme() => _build(HdTokens.dark, Brightness.dark);

/// Monospace text style for timers, session IDs, reading values.
const TextStyle hdMono = TextStyle(fontFamily: _mono, fontFeatures: [
  FontFeature.tabularFigures(),
]);
