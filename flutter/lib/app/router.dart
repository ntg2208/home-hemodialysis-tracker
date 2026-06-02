import 'package:go_router/go_router.dart';

import 'providers.dart';
import '../features/placeholder_screen.dart';
import '../features/setup/setup_screen.dart';

/// App router with the Setup gate. [auth] drives redirects via `refreshListenable`:
/// no key → Setup; key present while on Setup → Treatment Home.
GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    refreshListenable: auth,
    initialLocation: '/treatment',
    redirect: (context, state) {
      final atSetup = state.matchedLocation == '/setup';
      if (!auth.isAuthed) return atSetup ? null : '/setup';
      if (atSetup) return '/treatment';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
          path: '/treatment',
          builder: (_, _) => const PlaceholderScreen(title: 'Treatment')),
      GoRoute(
          path: '/blood-tests',
          builder: (_, _) => const PlaceholderScreen(title: 'Blood Tests')),
      GoRoute(
          path: '/inventory',
          builder: (_, _) => const PlaceholderScreen(title: 'Inventory')),
      GoRoute(
          path: '/fitness',
          builder: (_, _) => const PlaceholderScreen(title: 'Fitness')),
      GoRoute(
          path: '/kb',
          builder: (_, _) => const PlaceholderScreen(
              title: 'Knowledge Base',
              note: 'NxStage error codes — coming soon.')),
      GoRoute(
          path: '/settings',
          builder: (_, _) => const PlaceholderScreen(title: 'Settings')),
    ],
  );
}
