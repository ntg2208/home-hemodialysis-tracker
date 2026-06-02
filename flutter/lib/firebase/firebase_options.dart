import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase config for project `homehd-personal`.
///
/// Built by hand from the existing React web config (frontend/src/lib/firebaseClient.ts)
/// to avoid the interactive `flutterfire configure` step. The web app config works for
/// Flutter web verbatim; the Android/iOS app IDs are filled in when the mobile toolchains
/// are set up (run `flutterfire configure` then to regenerate this file natively).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        // Mobile registrations not yet created. Web options work for auth+Firestore
        // against the same project until native apps are registered.
        return web;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REDACTED_FIREBASE_WEB_API_KEY',
    authDomain: 'homehd-personal.firebaseapp.com',
    projectId: 'homehd-personal',
    storageBucket: 'homehd-personal.firebasestorage.app',
    messagingSenderId: '266908773576',
    appId: '1:266908773576:web:2ac0026f747cf0994c09fd',
  );
}
