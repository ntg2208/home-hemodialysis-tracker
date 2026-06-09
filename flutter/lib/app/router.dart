import 'package:go_router/go_router.dart';

import '../flavor.dart';
import 'branch_switcher.dart';
import 'providers.dart';
import 'shell.dart';
import '../features/blood_tests/blood_tests_screen.dart';
import '../features/fitness/fitness_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/settings/community_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/treatment/treatment_flow.dart';
import '../features/kb/kb_screen.dart';

/// App router with the Setup gate and a [StatefulShellRoute] for the five main
/// sections. Switching between sections via the drawer never pushes to the
/// back-stack — pressing back at any section root exits the app cleanly.
///
/// /setup  and /settings live outside the shell so they can be pushed onto the
/// back-stack: back from Settings returns to whichever section the user was in.
GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    refreshListenable: auth,
    initialLocation: '/treatment',
    redirect: (context, state) {
      if (kCommunity) return null;
      final atSetup = state.matchedLocation == '/setup';
      if (!auth.isAuthed) return atSetup ? null : '/setup';
      if (atSetup) return '/treatment';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),

      // Settings is outside the shell so context.push('/settings') puts it on
      // the back-stack and back-button returns to the previous shell branch.
      GoRoute(path: '/settings', builder: (_, _) => kCommunity
          ? const CommunitySettingsScreen()
          : const SettingsScreen()),

      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) =>
            BranchSwitcher(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/treatment',
                builder: (_, _) => const TreatmentFlow()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/blood-tests',
                builder: (_, _) => const BloodTestsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/inventory',
                builder: (_, _) => const InventoryScreen()),
          ]),
          if (!kCommunity)
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/fitness',
                  builder: (_, _) => const FitnessScreen()),
            ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/kb',
                builder: (_, _) => const KbScreen()),
          ]),
        ],
      ),
    ],
  );
}
