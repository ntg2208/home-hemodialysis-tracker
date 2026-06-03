# Flutter Material You Light Mode — Design Spec
<!-- 2026-06-03 -->

## Overview

Apply Material You (M3) to the Flutter app: updated light colour tokens, proper M3 `ColorScheme.fromSeed`, scale-fade page transitions, M3 `NavigationDrawer` with active indicator pill, a `PressableScale` widget for button press animations, and an outline icon pass. Dark mode tokens and the `hdDarkTheme()` function are untouched.

---

## 1. Colour tokens — `HdTokens.light`

File: `flutter/lib/app/theme.dart`

### Updated fields on `HdTokens.light`

| Field | Old hex | New hex | Notes |
|---|---|---|---|
| `bg` | `#F8FAFC` | `#FAFDFE` | Slight cyan tint |
| `accent` | `#0891B2` | `#006874` | Deeper — WCAG AA on white |
| `border` | `#E2E8F0` | `#DBE4E6` | Slightly tinted |
| `textPrimary` | `#0F172A` | `#191C1D` | Near-black |
| `textSecondary` | `#64748B` | `#3F484A` | Warmer grey |
| `textMuted` | `#94A3B8` | `#6F797A` | Warmer grey |
| `good` | `#059669` | `#2E7D32` | M3 tertiary green |
| `warning` | `#D97706` | `#E65100` | M3 orange |
| `danger` | `#DC2626` | `#B71C1C` | M3 error red |

`panel`, `accentOn`, and `vital` stay unchanged.

### New fields added to `HdTokens`

Three new fields added to the class and both dark/light instances:

| Field | Light value | Dark value | Usage |
|---|---|---|---|
| `primaryContainer` | `#97F0FF` | `#004F58` | Drawer active pill bg — dark uses deep teal |
| `onPrimaryContainer` | `#001F24` | `#97F0FF` | Drawer active icon/label — dark inverts |
| `surfaceContainer` | `#E8F7F9` | `#162022` | Stat cells — dark uses very dark teal |

### `ColorScheme` — switch to `fromSeed`

Replace the manual `ColorScheme(...)` constructor in `_build()` with:

```dart
final scheme = ColorScheme.fromSeed(
  seedColor: t.accent,
  brightness: brightness,
).copyWith(
  surface: t.panel,
  onSurface: t.textPrimary,
  error: t.danger,
);
```

This gives any M3 widget that reads `Theme.of(context).colorScheme` correct tonal values automatically (including `NavigationDrawer`'s active indicator).

---

## 2. Screen transitions

File: `flutter/lib/app/theme.dart` — inside `_build()`

Add to `ThemeData`:

```dart
pageTransitionsTheme: const PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(),
    TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
  },
),
```

`ZoomPageTransitionsBuilder` is Flutter's built-in M3 scale-fade: new screen enters from scale 0.87 → 1.0 with fade, outgoing shrinks and fades. Fires on every GoRouter `push` (Pre → Active → Post, Settings, etc.). No per-screen code needed.

`BranchSwitcher` (drawer → section switching) keeps its 200ms crossfade — correct M3 motion for sibling navigation.

---

## 3. NavigationDrawer

File: `flutter/lib/app/shell.dart`

Replace `_HdDrawer` (custom `ListTile`-based drawer) with Flutter's `NavigationDrawer` widget. `NavigationDrawer` renders an M3 active indicator pill (`primaryContainer`-coloured rounded rectangle) behind the selected destination automatically.

### Structure

```dart
NavigationDrawer(
  selectedIndex: _currentIndex,   // derived from GoRouterState
  onDestinationSelected: _onDestSelected,
  children: [
    // Header — Padding + Column with title/subtitle text
    const Padding(
      padding: EdgeInsets.fromLTRB(28, 24, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home HD', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Dialysis tracker', style: TextStyle(fontSize: 13)),
        ],
      ),
    ),
    // Destinations
    const NavigationDrawerDestination(
      icon: Icon(Icons.monitor_heart_outlined),
      label: Text('Treatment'),
    ),
    const NavigationDrawerDestination(
      icon: Icon(Icons.science_outlined),
      label: Text('Blood Tests'),
    ),
    const NavigationDrawerDestination(
      icon: Icon(Icons.inventory_2_outlined),
      label: Text('Inventory'),
    ),
    const NavigationDrawerDestination(
      icon: Icon(Icons.fitness_center_outlined),
      label: Text('Fitness'),
    ),
    const NavigationDrawerDestination(
      icon: Icon(Icons.menu_book_outlined),
      label: Text('Knowledge Base'),
    ),
    const Divider(indent: 28, endIndent: 28),
    // Settings — uses context.push so it stays on back-stack
    const NavigationDrawerDestination(
      icon: Icon(Icons.settings_outlined),
      label: Text('Settings'),
    ),
  ],
)
```

### `_currentIndex` derivation

`NavigationDrawer.selectedIndex` maps to the branch index (0–4 for main branches; Settings at index 5 is a pushed route so it gets `selectedIndex: -1` when active to show no active highlight).

Derive from `GoRouterState.of(context).matchedLocation` using a helper:

```dart
int _drawerIndex(String location) {
  if (location.startsWith('/treatment'))  return 0;
  if (location.startsWith('/blood-tests')) return 1;
  if (location.startsWith('/inventory'))  return 2;
  if (location.startsWith('/fitness'))    return 3;
  if (location.startsWith('/kb'))         return 4;
  return -1; // Settings or unknown — no highlight
}
```

### `_onDestSelected` handler

```dart
void _onDestSelected(int index) {
  Navigator.of(context).pop(); // close drawer
  const paths = ['/treatment', '/blood-tests', '/inventory', '/fitness', '/kb'];
  if (index < paths.length) {
    context.go(paths[index]);
  } else if (index == 5) {
    context.push('/settings');
  }
}
```

---

## 4. `PressableScale` widget

New file: `flutter/lib/widgets/pressable_scale.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a child (typically an ElevatedButton) with a scale-and-haptic press
/// animation. On tap-down: scales to 95% + light haptic. On tap-up/cancel:
/// springs back with an elastic curve.
///
/// The inner widget still receives its own tap events normally — the
/// GestureDetector uses HitTestBehavior.translucent so events propagate through.
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

### Where to apply

Wrap the primary action `ElevatedButton` (or `ElevatedButton.icon`) on each treatment screen:

| Screen | Button |
|---|---|
| `screens/home.dart` | Start session |
| `screens/pre.dart` | Start session (submit) |
| `screens/active.dart` | Add reading, End session (dismiss/confirm) |
| `screens/post.dart` | Finish session |
| `widgets/add_reading_sheet.dart` | Save reading |

Secondary actions (`TextButton`, `OutlinedButton`, cancel buttons) do not get `PressableScale` — the animation is reserved for primary CTAs to keep it meaningful.

---

## 5. Outline icons

File-by-file replacements in `flutter/lib/features/treatment/`:

| File | Old | New |
|---|---|---|
| `screens/home.dart:139` | `Icons.play_arrow` | `Icons.play_arrow_outlined` |
| `screens/pre.dart:233` | `Icons.play_arrow` (icon field) | `Icons.play_arrow_outlined` |
| `treatment_flow.dart:270` | `Icons.refresh` | `Icons.refresh_outlined` |
| `screens/active.dart:444` | `Icons.scale` | `Icons.scale_outlined` |

Icons that have no outlined Flutter equivalent and stay as-is:
- `Icons.add`, `Icons.remove` (math symbols — no outline variant)
- `Icons.close`, `Icons.check` (marks — no outline variant)
- `Icons.warning_amber_rounded` (warning glyph — no outline variant)
- `Icons.favorite_border` (already border ✅)

---

## 6. Files changed

| File | What changes |
|---|---|
| `flutter/lib/app/theme.dart` | `HdTokens` — 3 new fields + `HdTokens.light` updated values + `HdTokens.dark` new field values; `_build()` — `ColorScheme.fromSeed` + `pageTransitionsTheme` |
| `flutter/lib/app/shell.dart` | `_HdDrawer` → `NavigationDrawer` + `NavigationDrawerDestination`; `_drawerIndex` helper; `_onDestSelected` handler |
| `flutter/lib/widgets/pressable_scale.dart` | New file — `PressableScale` widget |
| `flutter/lib/features/treatment/screens/home.dart` | `PressableScale` wrap + `play_arrow_outlined` |
| `flutter/lib/features/treatment/screens/pre.dart` | `PressableScale` wrap + `play_arrow_outlined` |
| `flutter/lib/features/treatment/screens/active.dart` | `PressableScale` wrap + `scale_outlined` |
| `flutter/lib/features/treatment/screens/post.dart` | `PressableScale` wrap |
| `flutter/lib/features/treatment/widgets/add_reading_sheet.dart` | `PressableScale` wrap |
| `flutter/lib/features/treatment/treatment_flow.dart` | `refresh_outlined` |

---

## 7. Out of scope

- Dark mode token changes (untouched)
- Any non-treatment screen icon audit (blood tests, inventory, fitness)
- Dynamic colour extraction from device wallpaper
- Any data / API / storage changes
