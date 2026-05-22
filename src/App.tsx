import { useEffect, useState } from 'react';
import {
  clearActiveState,
  getActiveState,
  getSettings,
  saveActiveState,
} from './storage';
import type { PendingReading, Session, Settings } from './schemas';
import { Setup } from './screens/Setup';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'setup' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[] }
  | { name: 'post'; session: Session };

export function App() {
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [settings, setSettings] = useState<Settings | null>(null);

  useEffect(() => {
    (async () => {
      let s: Settings | undefined;
      try { s = await getSettings(); }
      catch { setScreen({ name: 'setup' }); return; }
      if (!s) { setScreen({ name: 'setup' }); return; }
      setSettings(s);

      // Restore an in-progress session if one was persisted within the TTL.
      // Any reading that was mid-flight when state was last persisted is
      // demoted to 'error' so the user can retry — we can't know whether the
      // backend actually completed the write before we got killed.
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
    })();
  }, []);

  // Persist screen on every transition so a reload/eviction can resume it.
  // localStorage is synchronous — the write is on disk before this returns.
  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session });
    } else if (screen.name === 'home' || screen.name === 'setup') {
      clearActiveState();
    }
  }, [screen]);

  if (screen.name === 'loading') return <div className="p-4 text-slate-400">Loading…</div>;

  if (screen.name === 'setup') {
    return <Setup onSaved={s => { setSettings(s); setScreen({ name: 'home' }); }} />;
  }

  if (!settings) return <div className="p-4 text-slate-400">Loading…</div>;

  if (screen.name === 'home') {
    return (
      <Home
        settings={settings}
        onStartSession={existingIds => setScreen({ name: 'pre', existingIds })}
        onSettingsCleared={() => { setSettings(null); setScreen({ name: 'setup' }); }}
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

  // Compile-time exhaustiveness: any new Screen variant without a branch
  // above will surface here as a type error.
  const _exhaustive: never = screen;
  return _exhaustive;
}
