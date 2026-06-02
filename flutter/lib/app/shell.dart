import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import '../features/chat/chat_sheet.dart';

/// Drawer destinations, in order. `route` is the go_router path.
class _Dest {
  const _Dest(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

const _destinations = [
  _Dest('Treatment', Icons.monitor_heart_outlined, '/treatment'),
  _Dest('Blood Tests', Icons.science_outlined, '/blood-tests'),
  _Dest('Inventory', Icons.inventory_2_outlined, '/inventory'),
  _Dest('Fitness', Icons.fitness_center, '/fitness'),
  _Dest('Knowledge Base', Icons.menu_book_outlined, '/kb'),
];

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
  });

  final String title;
  final Widget body;
  final bool showDrawer;
  final List<Widget>? actions;
  final bool showChatFab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      drawer: showDrawer ? const _HdDrawer() : null,
      floatingActionButton: showChatFab ? const ChatFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _HdDrawer extends StatelessWidget {
  const _HdDrawer();

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final current = GoRouterState.of(context).matchedLocation;
    return Drawer(
      backgroundColor: t.panel,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Home HD',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Dialysis tracker',
                      style: TextStyle(color: t.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            for (final d in _destinations)
              _DrawerItem(d: d, active: current.startsWith(d.route)),
            const Divider(height: 24),
            _DrawerItem(
              d: const _Dest('Settings', Icons.settings_outlined, '/settings'),
              active: current.startsWith('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.d, required this.active});
  final _Dest d;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return ListTile(
      leading: Icon(d.icon, color: active ? t.accent : t.textSecondary),
      title: Text(d.label,
          style: TextStyle(
              color: active ? t.accent : t.textPrimary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      tileColor: active ? t.accent.withValues(alpha: 0.10) : null,
      onTap: () {
        Navigator.of(context).pop(); // close drawer
        if (!active) context.go(d.route);
      },
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
