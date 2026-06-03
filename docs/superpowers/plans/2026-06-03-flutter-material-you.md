# Flutter Material You Light Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply Material You light mode to the Flutter app: updated M3 colour tokens, scale-fade page transitions, M3 NavigationDrawer with active pill, PressableScale button animation, and an outline icon pass.

**Architecture:** All colour changes flow through `HdTokens` (a `ThemeExtension`) in `theme.dart` — screens read `context.hd` so updating the token values there changes every screen at once. `PressableScale` is a thin stateful wrapper added around primary CTAs. Navigation drawer switches to Flutter's built-in `NavigationDrawer` widget which renders the M3 active indicator pill automatically.

**Tech Stack:** Flutter, Dart, flutter_riverpod, go_router, flutter_test/flutter_test

**Spec:** `docs/superpowers/2026-06-03-flutter-material-you.md`

**Working directory for all commands:** `flutter/`

---

## Task 1: HdTokens — new fields, updated light values, fromSeed, pageTransitionsTheme

**Files:**
- Modify: `flutter/lib/app/theme.dart`

The `HdTokens` class needs three new fields (`primaryContainer`, `onPrimaryContainer`, `surfaceContainer`). Every constructor call, `copyWith`, and `lerp` must be updated. The `_build()` function switches to `ColorScheme.fromSeed` and adds `pageTransitionsTheme`.

- [ ] **Replace `flutter/lib/app/theme.dart` with the updated version**

```dart
import 'package:flutter/material.dart';

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

  final Color bg;
  final Color panel;
  final Color accent;
  final Color accentOn;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color good;
  final Color warning;
  final Color danger;
  final Color vital;
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

const TextStyle hdMono = TextStyle(fontFamily: _mono, fontFeatures: [
  FontFeature.tabularFigures(),
]);
```

- [ ] **Run tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass. The new `primaryContainer` / `onPrimaryContainer` / `surfaceContainer` fields have values in both `dark` and `light` constants, so no null crashes.

- [ ] **Commit**

```bash
git add flutter/lib/app/theme.dart
git commit -m "feat(flutter): M3 colour tokens, fromSeed ColorScheme, ZoomPageTransitions"
```

---

## Task 2: NavigationDrawer

**Files:**
- Modify: `flutter/lib/app/shell.dart`

Replace the `_HdDrawer` class (which uses `ListTile`) with a new implementation that wraps Flutter's `NavigationDrawer` widget. The active destination gets an M3 indicator pill automatically via `colorScheme.secondaryContainer` (which `ColorScheme.fromSeed` generates from our teal seed). `HdScaffold` and `AppShell` are unchanged — they still reference `_HdDrawer`.

- [ ] **Replace the `_HdDrawer`, `_DrawerItem`, and `_Dest` definitions in `flutter/lib/app/shell.dart`**

Remove the existing `_Dest` struct, `_destinations` list, `_HdDrawer`, and `_DrawerItem` classes. Replace them with:

```dart
// ── Drawer destinations ──────────────────────────────────────────────────────

const _destPaths = [
  '/treatment',
  '/blood-tests',
  '/inventory',
  '/fitness',
  '/kb',
];

int _drawerIndex(String location) {
  for (var i = 0; i < _destPaths.length; i++) {
    if (location.startsWith(_destPaths[i])) return i;
  }
  return -1; // Settings or unknown — no highlight
}

class _HdDrawer extends StatelessWidget {
  const _HdDrawer();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _drawerIndex(location);

    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        Navigator.of(context).pop(); // close drawer
        if (index < _destPaths.length) {
          context.go(_destPaths[index]);
        } else if (index == 5) {
          // Settings — pushed so back-button returns to previous branch
          context.push('/settings');
        }
      },
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home HD',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Dialysis tracker', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          label: Text('Treatment'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.science_outlined),
          label: Text('Blood Tests'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: Text('Inventory'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.fitness_center_outlined),
          label: Text('Fitness'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.menu_book_outlined),
          label: Text('Knowledge Base'),
        ),
        Divider(indent: 28, endIndent: 28),
        NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          label: Text('Settings'),
        ),
      ],
    );
  }
}
```

Keep `AppShell`, `_AppShellState`, `HdScaffold`, and `ChatFab` exactly as they are. Only remove `_Dest`, `_destinations`, `_DrawerItem` and replace `_HdDrawer`.

- [ ] **Run tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass.

- [ ] **Commit**

```bash
git add flutter/lib/app/shell.dart
git commit -m "feat(flutter): replace drawer with M3 NavigationDrawer + active pill"
```

---

## Task 3: PressableScale widget

**Files:**
- Create: `flutter/lib/widgets/pressable_scale.dart`

- [ ] **Create `flutter/lib/widgets/pressable_scale.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a child widget (typically an ElevatedButton) with a scale + haptic
/// press animation. On tap-down: fires a light haptic tick and scales to 95%.
/// On tap-up or cancel: springs back to 100% with an elastic curve.
///
/// The GestureDetector uses HitTestBehavior.translucent so the inner button
/// still receives its own tap events and fires onPressed normally.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 180),
        curve: _pressed ? Curves.easeIn : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}
```

- [ ] **Run tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass (new file, no existing tests reference it).

- [ ] **Commit**

```bash
git add flutter/lib/widgets/pressable_scale.dart
git commit -m "feat(flutter): add PressableScale widget — scale + haptic on button press"
```

---

## Task 4: Apply PressableScale to SaveButton

**Files:**
- Modify: `flutter/lib/widgets/save_button.dart`

`SaveButton` is used by `pre.dart`, `post.dart`, and `add_reading_sheet.dart`. Wrapping here applies the animation to all three at once.

- [ ] **Replace `flutter/lib/widgets/save_button.dart`**

```dart
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'pressable_scale.dart';

/// Full-width pill CTA with a saving spinner and an inline error+Retry box.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.saving,
    required this.onPressed,
    required this.label,
    this.error,
    this.icon,
    this.enabled = true,
  });

  final bool saving;
  final VoidCallback onPressed;
  final String label;
  final String? error;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PressableScale(
          child: ElevatedButton.icon(
            onPressed: (saving || !enabled) ? null : onPressed,
            icon: saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.accentOn))
                : (icon != null ? Icon(icon) : const SizedBox.shrink()),
            label: Text(saving ? 'Saving…' : label),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.danger.withValues(alpha: 0.15),
              border: Border.all(color: t.danger),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                    child: Text(error!,
                        style: TextStyle(color: t.danger, fontSize: 13))),
                TextButton(
                    onPressed: saving ? null : onPressed,
                    child: const Text('Retry')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Run tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass. `PressableScale` wraps the button but doesn't change the widget tree that tests probe (text labels, find-by-type queries).

- [ ] **Commit**

```bash
git add flutter/lib/widgets/save_button.dart
git commit -m "feat(flutter): wrap SaveButton with PressableScale"
```

---

## Task 5: Apply PressableScale + outline icon pass

**Files:**
- Modify: `flutter/lib/features/treatment/screens/home.dart`
- Modify: `flutter/lib/features/treatment/screens/active.dart`
- Modify: `flutter/lib/features/treatment/screens/pre.dart`
- Modify: `flutter/lib/features/treatment/treatment_flow.dart`

### home.dart

- [ ] **Add `PressableScale` import to `home.dart`**

At the top of `flutter/lib/features/treatment/screens/home.dart`, add:
```dart
import '../../../widgets/pressable_scale.dart';
```

- [ ] **Wrap the Start session `ElevatedButton.icon` with `PressableScale` in `home.dart`**

Find the `ElevatedButton.icon` at line ~136 (the "Start session" button):
```dart
// Before:
ElevatedButton.icon(
  onPressed: loaded ? () => widget.onStartSession(ids) : null,
  icon: loaded
      ? const Icon(Icons.play_arrow)
      : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
  label: const Text('Start session'),
  // ...
),

// After:
PressableScale(
  child: ElevatedButton.icon(
    onPressed: loaded ? () => widget.onStartSession(ids) : null,
    icon: loaded
        ? const Icon(Icons.play_arrow_outlined)
        : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    label: const Text('Start session'),
    // ...all existing style params unchanged...
  ),
),
```

Note: `Icons.play_arrow` → `Icons.play_arrow_outlined` in the same edit.

### active.dart

- [ ] **Add `PressableScale` import to `active.dart`**

```dart
import '../../../widgets/pressable_scale.dart';
```

- [ ] **Wrap the "Add reading" `ElevatedButton.icon` with `PressableScale` in `active.dart`**

Find the `ElevatedButton.icon` at line ~251 (the "Add reading" button). The surrounding `SizedBox(width: double.infinity, child: ...)` stays; only the button itself gets wrapped:

```dart
// Before:
SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    onPressed: () => showAddReadingSheet(...),
    icon: const Icon(Icons.add),
    label: const Text('Add reading'),
    style: ElevatedButton.styleFrom(...),
  ),
),

// After:
SizedBox(
  width: double.infinity,
  child: PressableScale(
    child: ElevatedButton.icon(
      onPressed: () => showAddReadingSheet(...),
      icon: const Icon(Icons.add),
      label: const Text('Add reading'),
      style: ElevatedButton.styleFrom(...),
    ),
  ),
),
```

- [ ] **Replace `Icons.scale` with `Icons.scale_outlined` in `active.dart`**

Find at line ~444:
```dart
// Before:
refCard(Icons.scale, t.textSecondary, 'WEIGHT', ...

// After:
refCard(Icons.scale_outlined, t.textSecondary, 'WEIGHT', ...
```

### pre.dart

- [ ] **Replace `Icons.play_arrow` with `Icons.play_arrow_outlined` in `pre.dart`**

Find at line ~233 (the icon field passed to a button or `SaveButton`-like call):
```dart
// Before:
icon: Icons.play_arrow,

// After:
icon: Icons.play_arrow_outlined,
```

### treatment_flow.dart

- [ ] **Replace `Icons.refresh` with `Icons.refresh_outlined` in `treatment_flow.dart`**

Find at line ~270:
```dart
// Before:
icon: const Icon(Icons.refresh),

// After:
icon: const Icon(Icons.refresh_outlined),
```

- [ ] **Run tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass. `Icons.play_arrow_outlined` is a valid `IconData`; the test that checks for `'Start session'` text still finds it.

- [ ] **Commit**

```bash
git add flutter/lib/features/treatment/screens/home.dart \
        flutter/lib/features/treatment/screens/active.dart \
        flutter/lib/features/treatment/screens/pre.dart \
        flutter/lib/features/treatment/treatment_flow.dart
git commit -m "feat(flutter): PressableScale on primary CTAs + outline icon pass"
```

---

## Task 6: Full test run + build verify

- [ ] **Run all tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass with 0 failures.

- [ ] **Build a debug APK to confirm no compile errors**

```bash
cd flutter && flutter build apk --debug
```

Expected: exits 0, `build/app/outputs/flutter-apk/app-debug.apk` produced.

- [ ] **Visual smoke check on device or emulator**

```bash
cd flutter && flutter run
```

Verify:
1. App opens on a white/light background ✅
2. Drawer opens — active destination has a teal rounded-rectangle pill indicator ✅
3. Navigate Treatment → Pre-treatment: scale-fade transition plays ✅
4. Tap "Start session": button shrinks to ~95% on press, snaps back with spring on release, light haptic fires ✅
5. "Start session" icon is outline (play arrow outline) ✅
6. Inside Active session, "Add reading" button has same press animation ✅
7. Pre/Post "Save" buttons (via SaveButton) have the same animation ✅
8. Timer icon, weight icon in Active session are outline variants ✅
