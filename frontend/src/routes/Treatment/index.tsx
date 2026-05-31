import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { signInWithCustomToken } from 'firebase/auth';
import { getAuth, saveAuth, type AuthSettings } from '../../auth/storage';
import { firebaseAuth } from '../../lib/firebaseClient';
import { cloudGet } from '../../api/cloudRun';
import {
  clearActiveState,
  getActiveState,
  saveActiveState,
} from './storage';
import type { SessionConsumed } from './storage';
import type { PendingReading, Session } from './schemas';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'error' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[]; heparinUsed: boolean; countdownStartedAt?: number; targetMin?: number }
  | { name: 'post'; session: Session; consumed: SessionConsumed };

interface TokenResponse { token: string; expires_at: number }

async function ensureFirebaseAuth(auth: AuthSettings): Promise<AuthSettings> {
  const now = Date.now();
  const tokenFresh = auth.treatmentToken
    && auth.treatmentTokenExpiresAt
    && (auth.treatmentTokenExpiresAt - now) > 10 * 60 * 1000;

  // Firebase persists auth state in IndexedDB across sessions.
  // Skip the network round-trip if already signed in and token isn't expiring.
  if (firebaseAuth.currentUser && tokenFresh) return auth;

  if (!tokenFresh) {
    const { token, expires_at } = await cloudGet<TokenResponse>(auth, '/api/treatment/token');
    const updated = { ...auth, treatmentToken: token, treatmentTokenExpiresAt: expires_at };
    await saveAuth(updated);
    auth = updated;
  }
  await signInWithCustomToken(firebaseAuth, auth.treatmentToken!);
  return auth;
}

export default function Treatment() {
  const navigate = useNavigate();
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [auth, setAuth] = useState<AuthSettings | null>(null);
  const [retryCount, setRetryCount] = useState(0);

  useEffect(() => {
    let cancelled = false;
    getAuth().then(async (a) => {
      if (!a) { navigate('/setup', { replace: true }); return; }

      let currentAuth = a;
      try {
        currentAuth = await ensureFirebaseAuth(a);
      } catch (e) {
        console.warn('Firebase token refresh failed:', e);
        // If Firebase has no authenticated user at all, Firestore will fail with
        // permission denied on every read/write — show an error with a retry button.
        if (!firebaseAuth.currentUser) {
          if (!cancelled) setScreen({ name: 'error' });
          return;
        }
        // currentUser exists from a previous session — Firestore may still work.
      }

      if (cancelled) return;
      setAuth(currentAuth);

      const active = getActiveState();
      if (active?.screen === 'pre' && active.existingIds) {
        setScreen({ name: 'pre', existingIds: active.existingIds });
      } else if (active?.screen === 'active' && active.session) {
        const readings = (active.readings ?? []).map(r =>
          r.status === 'pending' ? { ...r, status: 'error' as const, errorMsg: 'interrupted' } : r
        );
        setScreen({ name: 'active', session: active.session, readings, heparinUsed: active.heparinUsed ?? false, countdownStartedAt: active.countdownStartedAt, targetMin: active.targetMin });
      } else if (active?.screen === 'post' && active.session) {
        const consumed: SessionConsumed = active.consumed ?? { needles: 2, onOffPacks: 1, heparinUsed: false };
        setScreen({ name: 'post', session: active.session, consumed });
      } else {
        setScreen({ name: 'home' });
      }
    }).catch(() => { if (!cancelled) navigate('/setup', { replace: true }); });
    return () => { cancelled = true; };
  }, [navigate, retryCount]);

  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings, heparinUsed: screen.heparinUsed, countdownStartedAt: screen.countdownStartedAt, targetMin: screen.targetMin });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session, consumed: screen.consumed });
    } else if (screen.name === 'home') {
      clearActiveState();
    }
  }, [screen]);

  if (screen.name === 'loading') {
    return <div className="p-4 text-slate-400">Loading…</div>;
  }

  if (screen.name === 'error') {
    return (
      <div className="p-8 text-center space-y-3">
        <AlertTriangle className="w-8 h-8 text-amber-400 mx-auto" />
        <p className="text-slate-300">Could not connect. Check your network and try again.</p>
        <button
          type="button"
          onClick={() => { setScreen({ name: 'loading' }); setRetryCount(n => n + 1); }}
          className="flex items-center gap-2 mx-auto px-4 py-2 rounded-lg bg-slate-700 text-slate-100 text-sm"
        >
          <RefreshCw className="w-4 h-4" /> Retry
        </button>
      </div>
    );
  }

  if (screen.name === 'home') {
    return (
      <Home
        onStartSession={existingIds => setScreen({ name: 'pre', existingIds })}
      />
    );
  }
  if (screen.name === 'pre') {
    return (
      <PreTreatment
        auth={auth}
        existingIds={screen.existingIds}
        onSaved={(session, heparinUsed) =>
          setScreen({ name: 'active', session, readings: [], heparinUsed })
        }
        onCancel={() => setScreen({ name: 'home' })}
      />
    );
  }
  if (screen.name === 'active') {
    return (
      <ActiveSession
        session={screen.session}
        initialReadings={screen.readings}
        initialCountdownStartedAt={screen.countdownStartedAt}
        initialTargetMin={screen.targetMin}
        onReadingsChange={rs =>
          setScreen(s => (s.name === 'active' ? { ...s, readings: rs } : s))
        }
        onCountdownChange={(startedAt, targetMin) =>
          setScreen(s => s.name === 'active' ? { ...s, countdownStartedAt: startedAt ?? undefined, targetMin } : s)
        }
        onEnd={consumed =>
          setScreen({ name: 'post', session: screen.session, consumed: { ...consumed, heparinUsed: screen.heparinUsed } })
        }
      />
    );
  }
  if (screen.name === 'post') {
    return (
      <PostTreatment
        auth={auth}
        session={screen.session}
        consumed={screen.consumed}
        onSaved={() => setScreen({ name: 'home' })}
      />
    );
  }

  const _exhaustive: never = screen;
  return _exhaustive;
}
