import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[]; heparinUsed: boolean; countdownStartedAt?: number; targetMin?: number }
  | { name: 'post'; session: Session; consumed: SessionConsumed };

interface TokenResponse { token: string; expires_at: number }

async function ensureFirebaseAuth(auth: AuthSettings): Promise<AuthSettings> {
  const now = Date.now();
  const needsRefresh = !auth.treatmentToken
    || !auth.treatmentTokenExpiresAt
    || auth.treatmentTokenExpiresAt - now < 10 * 60 * 1000;

  if (needsRefresh) {
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

  useEffect(() => {
    let cancelled = false;
    getAuth().then(async (a) => {
      if (!a) { navigate('/setup', { replace: true }); return; }

      let currentAuth = a;
      try {
        currentAuth = await ensureFirebaseAuth(a);
      } catch (e) {
        // Token refresh failed — existing Firebase session may still be valid for up to 1h
        console.warn('Firebase token refresh failed:', e);
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
  }, [navigate]);

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
