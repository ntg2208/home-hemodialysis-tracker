import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAuth } from '../../auth/storage';
import {
  clearActiveState,
  getActiveState,
  saveActiveState,
} from './storage';
import type { PendingReading, Session, Settings } from './schemas';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[] }
  | { name: 'post'; session: Session };

export default function Treatment() {
  const navigate = useNavigate();
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [settings, setSettings] = useState<Settings | null>(null);

  useEffect(() => {
    getAuth().then(auth => {
      if (!auth) { navigate('/setup', { replace: true }); return; }
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
        setScreen({ name: 'active', session: active.session, readings });
      } else if (active?.screen === 'post' && active.session) {
        setScreen({ name: 'post', session: active.session });
      } else {
        setScreen({ name: 'home' });
      }
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session });
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
        existingIds={screen.existingIds}
        onSaved={session => setScreen({ name: 'active', session, readings: [] })}
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
        onEnd={() => setScreen({ name: 'post', session: screen.session })}
      />
    );
  }
  if (screen.name === 'post') {
    return (
      <PostTreatment
        settings={settings}
        session={screen.session}
        onSaved={() => setScreen({ name: 'home' })}
      />
    );
  }

  const _exhaustive: never = screen;
  return _exhaustive;
}
