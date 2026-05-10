import { useEffect, useState } from 'react';
import { getSettings } from './storage';
import type { Settings } from './schemas';
import { Setup } from './screens/Setup';
import { Home } from './screens/Home';

type Screen =
  | { name: 'loading' }
  | { name: 'setup' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; sessionId: string }
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

  // Pre/Active/Post screens land in Tasks 10-12.
  return <div className="p-4 text-slate-400">Screen "{screen.name}" not built yet.</div>;
}
