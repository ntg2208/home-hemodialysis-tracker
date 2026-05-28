import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAuth, type AuthSettings } from '../../auth/storage';
import {
  clearActiveState,
  getActiveState,
  saveActiveState,
} from './storage';
import type { SessionConsumed } from './storage';
import type { PendingReading, Session, Settings } from './schemas';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[]; heparinUsed: boolean }
  | { name: 'post'; session: Session; consumed: SessionConsumed };

export default function Treatment() {
  const navigate = useNavigate();
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [settings, setSettings] = useState<Settings | null>(null);
  const [auth, setAuth] = useState<AuthSettings | null>(null);

  useEffect(() => {
    getAuth().then(auth => {
      if (!auth) { navigate('/setup', { replace: true }); return; }
      setAuth(auth);
      const s: Settings = {
        script_url: auth.appsScriptUrl,
        shared_secret: auth.appsScriptSecret,
      };
      setSettings(s);
      const active = getActiveState();
      if (active?.screen === 'pre' && active.existingIds) {
        setScreen({ name: 'pre', existingIds: active.existingIds });
      } else if (active?.screen === 'active' && active.session) {
        const readings = (active.readings ?? []).map(r =>
          r.status === 'pending' ? { ...r, status: 'error' as const, errorMsg: 'interrupted' } : r
        );
        setScreen({ name: 'active', session: active.session, readings, heparinUsed: active.heparinUsed ?? false });
      } else if (active?.screen === 'post' && active.session) {
        const consumed: SessionConsumed = active.consumed ?? { needles: 2, onOffPacks: 1, heparinUsed: false };
        setScreen({ name: 'post', session: active.session, consumed });
      } else {
        setScreen({ name: 'home' });
      }
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings, heparinUsed: screen.heparinUsed });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session, consumed: screen.consumed });
    } else if (screen.name === 'home') {
      clearActiveState();
    }
  }, [screen]);

  if (screen.name === 'loading' || !settings) {
    return <div className="p-4 text-slate-400">Loading…</div>;
  }

  if (screen.name === 'home') {
    return (
      <Home
        settings={settings}
        onStartSession={existingIds => setScreen({ name: 'pre', existingIds })}
      />
    );
  }
  if (screen.name === 'pre') {
    return (
      <PreTreatment
        settings={settings}
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
        settings={settings}
        session={screen.session}
        initialReadings={screen.readings}
        onReadingsChange={rs =>
          setScreen(s => (s.name === 'active' ? { ...s, readings: rs } : s))
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
        settings={settings}
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
