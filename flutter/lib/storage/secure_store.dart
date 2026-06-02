import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials stored on-device. Mirrors the React `AuthSettings` shape
/// (frontend/src/auth/storage.ts). Replaces the IndexedDB `homehd-auth` store.
class AuthSettings {
  const AuthSettings({
    required this.mainKey,
    this.treatmentToken,
    this.treatmentTokenExpiresAt,
  });

  final String mainKey;
  final String? treatmentToken;
  final int? treatmentTokenExpiresAt; // unix ms

  AuthSettings copyWith({String? treatmentToken, int? treatmentTokenExpiresAt}) {
    return AuthSettings(
      mainKey: mainKey,
      treatmentToken: treatmentToken ?? this.treatmentToken,
      treatmentTokenExpiresAt:
          treatmentTokenExpiresAt ?? this.treatmentTokenExpiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'mainKey': mainKey,
        'treatmentToken': treatmentToken,
        'treatmentTokenExpiresAt': treatmentTokenExpiresAt,
      };

  factory AuthSettings.fromJson(Map<String, dynamic> j) => AuthSettings(
        mainKey: j['mainKey'] as String,
        treatmentToken: j['treatmentToken'] as String?,
        treatmentTokenExpiresAt: j['treatmentTokenExpiresAt'] as int?,
      );
}

/// Single source of truth for the stored credential.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'homehd-auth';

  Future<AuthSettings?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return AuthSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AuthSettings a) =>
      _storage.write(key: _key, value: jsonEncode(a.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
