import { useEffect, useState } from 'react';
import { getSettings } from './storage';
import type { Settings } from './schemas';
import { Setup } from './screens/Setup';

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
    getSettings().then(s => {
      if (s) { setSettings(s); setScreen({ name: 'home' }); }
      else setScreen({ name: 'setup' });
    });
  }, []);

  if (screen.name === 'loading') return <div className="p-4 text-slate-400">Loading…</div>;

  if (screen.name === 'setup') {
    return <Setup onSaved={s => { setSettings(s); setScreen({ name: 'home' }); }} />;
  }

  if (!settings) return <div className="p-4 text-slate-400">Loading…</div>;

  // Home/Pre/Active/Post screens land in Tasks 9-12.
  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold">Home (placeholder)</h1>
      <p className="text-sm text-slate-400 break-all">URL: {settings.script_url}</p>
      <p className="text-sm text-slate-400">Screen: {screen.name}</p>
    </div>
  );
}
