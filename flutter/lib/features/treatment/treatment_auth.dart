import '../../api/rest_client.dart';
import '../../app/providers.dart';
import '../../firebase/firebase_init.dart';

/// Establishes a Firebase session for Firestore access. Port of `ensureFirebaseAuth`
/// in frontend/src/routes/Treatment/index.tsx — including the two fixes from the
/// 2026-06-01 stuck-on-Loading bug:
///   1. await authStateReady() before reading currentUser (avoids the restore race)
///   2. a 20s timeout around the whole flow (avoids hanging on a slow signIn)
class TreatmentAuth {
  TreatmentAuth(this._rest, this._auth);
  final RestClient _rest;
  final AuthController _auth;

  static const _tokenSkewMs = 10 * 60 * 1000; // refresh within 10 min of expiry
  static const _timeout = Duration(seconds: 20);

  Future<void> ensure() => _ensure().timeout(_timeout);

  Future<void> _ensure() async {
    // Wait for Firebase to restore its session from local storage before reading
    // currentUser — otherwise currentUser is null on startup (the async race) and
    // the fast path never fires, forcing a signIn on every open. The Dart SDK has
    // no authStateReady(); awaiting the first authStateChanges() emission is the
    // equivalent — it fires once Firebase has determined the restored user.
    await firebaseAuth.authStateChanges().first;

    var settings = _auth.settings!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = settings.treatmentTokenExpiresAt;
    final tokenFresh = settings.treatmentToken != null &&
        expiresAt != null &&
        (expiresAt - now) > _tokenSkewMs;

    // Fast path: Firebase already has a session and the token is fresh.
    if (firebaseAuth.currentUser != null && tokenFresh) return;

    if (!tokenFresh) {
      final res = await _rest.get('/api/treatment/token');
      final token = res['token'] as String;
      final exp = (res['expires_at'] as num).toInt();
      settings = settings.copyWith(
          treatmentToken: token, treatmentTokenExpiresAt: exp);
      await _auth.saveSilently(settings);
    }
    await firebaseAuth.signInWithCustomToken(settings.treatmentToken!);
  }

  /// Whether Firebase still has *some* authenticated user (Firestore may work even
  /// after a failed refresh). Mirrors the React error-branch check.
  bool get hasCurrentUser => firebaseAuth.currentUser != null;
}
