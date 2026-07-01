// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase config for project `homehd-personal`.
///
/// On Android, `Firebase.initializeApp()` is called without options so the
/// native SDK reads from google-services.json (avoids [core/duplicate-app] from
/// the auto-init that happens before Dart runs). These options are used on web
/// only, where there is no native auto-init.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    // Mobile: google-services.json / GoogleService-Info.plist is the source
    // of truth. Passing options here would conflict with the auto-init that
    // the native Firebase SDK performs before main() runs.
    throw UnsupportedError(
        'Pass no options on mobile — call Firebase.initializeApp() directly.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
    authDomain: 'homehd-personal.firebaseapp.com',
    projectId: 'homehd-personal',
    storageBucket: 'homehd-personal.firebasestorage.app',
    messagingSenderId: '266908773576',
    appId: '1:266908773576:web:2ac0026f747cf0994c09fd',
  );
}
