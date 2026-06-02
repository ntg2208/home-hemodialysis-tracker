import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/app/providers.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/api/rest_client.dart';
import 'package:home_hd/features/setup/setup_screen.dart';
import 'package:home_hd/storage/secure_store.dart';

/// Canned dio adapter: 200 for 'Bearer good', else 401 — no network.
class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final authed = options.headers['Authorization'] == 'Bearer good';
    final body = authed
        ? '{"ok":true,"token":"t","expires_at":9999999999999}'
        : '{"error":"unauthorized"}';
    return ResponseBody.fromString(body, authed ? 200 : 401, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Records signIn without touching secure storage.
class _FakeAuth extends AuthController {
  _FakeAuth() : super(SecureStore());
  AuthSettings? signedIn;
  @override
  Future<void> signIn(AuthSettings a) async => signedIn = a;
}

RestClient _client(String key) =>
    RestClient(mainKey: () => key, dio: Dio()..httpClientAdapter = _FakeAdapter());

Widget _app(_FakeAuth auth) => ProviderScope(
      overrides: [
        authControllerProvider.overrideWithValue(auth),
        restClientFactoryProvider.overrideWithValue(_client),
      ],
      child: MaterialApp(theme: hdLightTheme(), home: const SetupScreen()),
    );

void main() {
  testWidgets('Setup renders its first frame', (tester) async {
    await tester.pumpWidget(_app(_FakeAuth()));
    expect(find.text('Home HD'), findsOneWidget);
    expect(find.text('Save and continue'), findsOneWidget);
  });

  testWidgets('wrong key shows the rejected error, does not sign in',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();
    expect(find.text('That key was rejected.'), findsOneWidget);
    expect(auth.signedIn, isNull);
  });

  testWidgets('valid key signs in', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.enterText(find.byType(TextField), 'good');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();
    expect(auth.signedIn?.mainKey, 'good');
  });
}
