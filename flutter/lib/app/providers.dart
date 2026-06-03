import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../api/rest_client.dart';
import '../storage/cache_store.dart';
import '../storage/secure_store.dart';

/// On-device credential store.
final secureStoreProvider = Provider<SecureStore>((_) => SecureStore());

/// Shared stale-while-revalidate cache box (fitness, blood tests). Opened in main.
const cacheBoxName = 'hd_cache';
final cacheStoreProvider =
    Provider<CacheStore>((_) => CacheStore(Hive.box(cacheBoxName)));

/// Holds the current [AuthSettings] in memory and drives the router's Setup gate.
/// Doubles as a [Listenable] for go_router's `refreshListenable`.
class AuthController extends ChangeNotifier {
  AuthController(this._store);
  final SecureStore _store;

  AuthSettings? _settings;
  bool _loaded = false;

  AuthSettings? get settings => _settings;
  bool get loaded => _loaded;
  bool get isAuthed => _settings != null;
  String get mainKey => _settings?.mainKey ?? '';

  Future<void> load() async {
    _settings = await _store.read();
    _loaded = true;
    notifyListeners();
  }

  /// First sign-in / key change — notifies so the router leaves Setup.
  Future<void> signIn(AuthSettings a) async {
    await _store.write(a);
    _settings = a;
    notifyListeners();
  }

  /// Token refresh — persists without a router refresh (no navigation change).
  Future<void> saveSilently(AuthSettings a) async {
    await _store.write(a);
    _settings = a;
  }

  Future<void> signOut() async {
    await _store.clear();
    _settings = null;
    notifyListeners();
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.read(secureStoreProvider));
});

/// Builds a one-off [RestClient] for a candidate key (used by Setup to verify a
/// key before it's stored). Overridable in tests with a fake-backed client.
typedef RestClientFactory = RestClient Function(String mainKey);
final restClientFactoryProvider = Provider<RestClientFactory>(
    (_) => (key) => RestClient(mainKey: () => key));

/// REST client for Cloud Run endpoints. Reads the live key from [AuthController]
/// and routes 401s back to Setup by clearing credentials.
final restClientProvider = Provider<RestClient>((ref) {
  final auth = ref.watch(authControllerProvider);
  return RestClient(
    mainKey: () => auth.mainKey,
    onUnauthorized: () {
      // Defer to avoid mutating state during a build/redirect pass.
      WidgetsBinding.instance.addPostFrameCallback((_) => auth.signOut());
    },
  );
});

/// App theme mode. Defaults to system; persisted in the cache box.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final raw = Hive.box(cacheBoxName).get(_key) as String?;
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void set(ThemeMode mode) {
    state = mode;
    Hive.box(cacheBoxName).put(_key, mode.name);
  }
}

/// Holds current AI assistant settings in memory.
class AiSettings {
  const AiSettings({this.enabled = false, this.apiKey});
  final bool enabled;
  final String? apiKey;
  bool get ready => enabled && (apiKey?.isNotEmpty ?? false);
}

final aiSettingsControllerProvider =
    NotifierProvider<AiSettingsController, AiSettings>(AiSettingsController.new);

class AiSettingsController extends Notifier<AiSettings> {
  @override
  AiSettings build() => const AiSettings();

  Future<void> load() async {
    final store = ref.read(secureStoreProvider);
    final enabled = await store.readAiEnabled();
    final key = await store.readAiKey();
    state = AiSettings(enabled: enabled, apiKey: key);
  }

  Future<void> setEnabled(bool v) async {
    await ref.read(secureStoreProvider).writeAiEnabled(v);
    state = AiSettings(enabled: v, apiKey: state.apiKey);
  }

  Future<void> setKey(String k) async {
    await ref.read(secureStoreProvider).writeAiKey(k);
    state = AiSettings(enabled: state.enabled, apiKey: k);
  }

  Future<void> clearKey() async {
    await ref.read(secureStoreProvider).clearAiKey();
    state = AiSettings(enabled: state.enabled, apiKey: null);
  }
}
