import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'features/treatment/providers.dart';
import 'firebase/firebase_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFirebase();
  await Hive.initFlutter();
  await Hive.openBox(treatmentBoxName);
  await Hive.openBox(cacheBoxName);

  final container = ProviderContainer();
  final auth = container.read(authControllerProvider);
  await auth.load(); // restore stored key before the router's first redirect

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HomeHdApp(router: buildRouter(auth)),
    ),
  );
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
