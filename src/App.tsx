import { useEffect, useState } from 'react';
import { getSettings } from './storage';
import type { Session, Settings } from './schemas';
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
  | { name: 'active'; session: Session }
  | { name: 'post'; sessionId: string };

export function App() {
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [settings, setSettings] = useState<Settings | null>(null);

  useEffect(() => {
    getSettings()
      .then(s => {
        if (s) { setSettings(s); setScreen({ name: 'home' }); }
        else setScreen({ name: 'setup' });
      })
      .catch(() => setScreen({ name: 'setup' }));
  }, []);

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
        onSaved={session => setScreen({ name: 'active', session })}
        onCancel={() => setScreen({ name: 'home' })}
      />
    );
  }

  if (screen.name === 'active') {
    return (
      <ActiveSession
        settings={settings}
        session={screen.session}
        onEnd={() => setScreen({ name: 'post', sessionId: screen.session.session_id })}
      />
    );
  }

  if (screen.name === 'post') {
    return (
      <PostTreatment
        settings={settings}
        sessionId={screen.sessionId}
        onSaved={() => setScreen({ name: 'home' })}
      />
    );
  }

  // Compile-time exhaustiveness: any new Screen variant without a branch
  // above will surface here as a type error.
  const _exhaustive: never = screen;
  return _exhaustive;
}
