import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kKey = 'mcp_bearer_key';

/// Generate a cryptographically random 256-bit key (64 hex chars).
String generateMcpKey() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Load the stored key or generate and persist one.
Future<String> mcpLoadOrCreateKey() async {
  final existing = await _storage.read(key: _kKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final key = generateMcpKey();
  await _storage.write(key: _kKey, value: key);
  return key;
}

/// Returns true if [authHeader] is "Bearer <expectedKey>".
bool checkBearer(String? authHeader, String expectedKey) =>
    authHeader != null && authHeader == 'Bearer $expectedKey';

/// Lazy-loads the bearer key (generates on first access).
final mcpBearerKeyProvider =
    FutureProvider<String>((ref) => mcpLoadOrCreateKey());
