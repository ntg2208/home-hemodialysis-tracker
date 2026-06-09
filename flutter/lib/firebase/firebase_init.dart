import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../firebase_options.dart';
import '../flavor.dart';

/// Initialises Firebase once for web + mobile. Call from `main()` before runApp.
///
/// On **mobile** Firebase is called without options: the native SDK auto-inits
/// from google-services.json before Dart runs, so passing options here would
/// cause [core/duplicate-app]. On **web** there is no native auto-init, so we
/// supply the web FirebaseOptions explicitly.
Future<void> initFirebase() async {
  if (kCommunity) return;
  if (Firebase.apps.isNotEmpty) return;
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } else {
    await Firebase.initializeApp();
  }
  // Offline persistence is on by default for mobile but set an unlimited cache
  // size so Firestore doesn't evict entries when storage is tight.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
}

FirebaseAuth get firebaseAuth => FirebaseAuth.instance;
FirebaseFirestore get firestore => FirebaseFirestore.instance;
