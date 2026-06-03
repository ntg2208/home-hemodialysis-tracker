// flutter/test/secure_store_ai_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/storage/secure_store.dart';

class _FakeStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({required String key, AppleOptions? iOptions,
      AndroidOptions? aOptions, LinuxOptions? lOptions,
      WebOptions? webOptions, AppleOptions? mOptions,
      WindowsOptions? wOptions}) async =>
      _data[key];

  @override
  Future<void> write({required String key, required String? value,
      AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
      WebOptions? webOptions, AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions,
      AndroidOptions? aOptions, LinuxOptions? lOptions,
      WebOptions? webOptions, AppleOptions? mOptions,
      WindowsOptions? wOptions}) async =>
      _data.remove(key);
}

void main() {
  group('SecureStore AI settings', () {
    late SecureStore store;

    setUp(() => store = SecureStore(_FakeStorage()));

    test('readAiEnabled defaults to false', () async {
      expect(await store.readAiEnabled(), isFalse);
    });

    test('writeAiEnabled / readAiEnabled round-trips', () async {
      await store.writeAiEnabled(true);
      expect(await store.readAiEnabled(), isTrue);
      await store.writeAiEnabled(false);
      expect(await store.readAiEnabled(), isFalse);
    });

    test('readAiKey returns null when not set', () async {
      expect(await store.readAiKey(), isNull);
    });

    test('writeAiKey / readAiKey round-trips', () async {
      await store.writeAiKey('AIzaTestKey123');
      expect(await store.readAiKey(), 'AIzaTestKey123');
    });

    test('clearAiKey removes the key', () async {
      await store.writeAiKey('AIzaTestKey123');
      await store.clearAiKey();
      expect(await store.readAiKey(), isNull);
    });

    test('clear() also wipes AI keys', () async {
      await store.writeAiEnabled(true);
      await store.writeAiKey('AIzaTestKey123');
      await store.clear();
      expect(await store.readAiEnabled(), isFalse);
      expect(await store.readAiKey(), isNull);
    });
  });
}
