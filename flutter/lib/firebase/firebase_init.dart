import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

/// Initialises Firebase once for web + mobile. Call from `main()` before runApp.
Future<void> initFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

FirebaseAuth get firebaseAuth => FirebaseAuth.instance;
FirebaseFirestore get firestore => FirebaseFirestore.instance;
