import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'features/treatment/providers.dart';
import 'firebase/firebase_init.dart';
import 'flavor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!kCommunity) {
      await initFirebase().timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception(
            'Firebase initialisation timed out. Check your internet connection and restart the app.');
      });
    }

    await Hive.initFlutter();
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);

    if (kCommunity) {
      await Future.wait([
        Hive.openBox(communitySessionsBox),
        Hive.openBox(communityReadingsBox),
        Hive.openBox(communityBtBox),
        Hive.openBox(communityInventoryBox),
        Hive.openBox(communityEventsBox),
        Hive.openBox(communityKbBox),
        Hive.openBox(communityChatBox),
      ]);
    }

    final container = ProviderContainer();

    if (!kCommunity) {
      final auth = container.read(authControllerProvider);
      await auth.load().timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Credential store timed out. Try restarting the app.');
      });
    }

    try {
      await container.read(aiSettingsControllerProvider.notifier).load()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: HomeHdApp(router: buildRouter(container.read(authControllerProvider))),
      ),
    );
  } catch (e) {
    runApp(_StartupErrorApp(message: e.toString()));
  }
}

class HomeHdApp extends ConsumerWidget {
  const HomeHdApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Home HD',
      debugShowCheckedModeBanner: false,
      theme: hdLightTheme(),
      darkTheme: hdDarkTheme(),
      themeMode: mode,
      routerConfig: router,
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: hdDarkTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Color(0xFFF87171)),
                const SizedBox(height: 20),
                const Text(
                  'App failed to start',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF1F5F9)),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Close and reopen the app to try again.\nIf the problem persists, check your internet connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
