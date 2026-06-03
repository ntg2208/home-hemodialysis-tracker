import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import '../features/chat/chat_sheet.dart';

/// Thin shell widget required by [StatefulShellRoute.indexedStack].
///
/// Back-button behaviour:
///   • Non-Treatment branch → go to Treatment (branch 0) instead of exiting.
///   • Treatment branch (Home/Loading/Error) → toast "Press back again to exit";
///     second press within 2 s exits the app.
///   • Treatment sub-screens (Pre/Active/Post) → handled by TreatmentFlow's
///     own PopScope before this one is reached.
///
/// Branch-switch animation is handled by [BranchSwitcher] via
/// `navigatorContainerBuilder` in the router, not here.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // Not on Treatment → go there instead of exiting.
        if (widget.navigationShell.currentIndex != 0) {
          widget.navigationShell.goBranch(0);
          return;
        }

        // On Treatment branch root → double-tap to exit.
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        await SystemNavigator.pop();
      },
      child: widget.navigationShell,
    );
  }
}

/// Shared scaffold for every authenticated screen.
///
/// Top-level drawer destinations pass [showDrawer] = true (hamburger). Pushed
/// sub-screens (Pre/Active/Post) pass false (they get a back arrow) but still show
/// the Chat FAB — the FAB is declared here exactly once so it's identical everywhere.
class HdScaffold extends StatelessWidget {
  const HdScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showDrawer = true,
    this.actions,
    this.showChatFab = true,
    this.floatingActionButton,
    this.leading,
    this.titleWidget,
  });

  final String title;
  final Widget body;
  final bool showDrawer;
  final List<Widget>? actions;
  final bool showChatFab;

  /// Optional custom FAB. When provided, takes precedence over [showChatFab].
  final Widget? floatingActionButton;

  /// Replaces the hamburger on pushed sub-screens (e.g. a close X or back arrow).
  final Widget? leading;

  /// Optional rich title (e.g. monospace session id). Falls back to [title].
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: titleWidget ?? Text(title),
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: showDrawer,
      ),
      drawer: showDrawer ? const _HdDrawer() : null,
      floatingActionButton:
          floatingActionButton ?? (showChatFab ? const ChatFab() : null),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RepaintBoundary(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

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
  return -1; // Settings or unknown -- no highlight
}

class _HdDrawer extends StatelessWidget {
  const _HdDrawer();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _drawerIndex(location);

    return RepaintBoundary(
      child: NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        Navigator.of(context).pop(); // close drawer
        if (index < _destPaths.length) {
          context.go(_destPaths[index]);
        } else if (index == 5) {
          // Settings -- pushed so back-button returns to previous branch
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
      ),
    );
  }
}

/// The one shared Chat FAB. Opens the chat bottom sheet; identical on every screen.
class ChatFab extends StatelessWidget {
  const ChatFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => showChatSheet(context),
      shape: const CircleBorder(),
      child: const Icon(Icons.chat_bubble_outline),
    );
  }
}
