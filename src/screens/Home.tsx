import { useEffect, useState } from 'react';
import { getAll, ApiError } from '../api';
import { clearSettings } from '../storage';
import type { Session, Settings } from '../schemas';
import { SessionListItem } from '../components/SessionListItem';

interface Props {
  settings: Settings;
  onStartSession: (existingIds: string[]) => void;
  onSettingsCleared: () => void;
}

export function Home({ settings, onStartSession, onSettingsCleared }: Props) {
  const [sessions, setSessions] = useState<Session[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setError(null);
    try {
      const r = await getAll(settings);
      const sorted = [...r.sessions].sort((a, b) => b.date.localeCompare(a.date));
      setSessions(sorted);
    } catch (e) {
      setError(e instanceof ApiError ? `Load failed: ${e.code}` : String(e));
    }
  }

  useEffect(() => { load(); }, []);

  async function clearAndReset() {
    if (!confirm('Clear saved URL and secret on this device?')) return;
    try {
      await clearSettings();
      onSettingsCleared();
    } catch {
      setError('Failed to clear settings. Please try again.');
    }
  }

  const ids = sessions?.map(s => s.session_id) ?? [];

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-baseline justify-between">
        <h1 className="text-2xl font-bold">HD Tracker</h1>
        <button type="button" onClick={clearAndReset} className="text-xs text-slate-500 underline">Settings</button>
      </header>

      <button
        type="button"
        onClick={() => onStartSession(ids)}
        disabled={sessions === null}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-4 text-lg disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Start session
      </button>

      <section className="space-y-2">
        <h2 className="text-sm uppercase tracking-wide text-slate-500">Recent sessions</h2>
        {error && (
          <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
            {error} <button type="button" className="underline ml-2" onClick={load}>Retry</button>
          </div>
        )}
        {!sessions && !error && <div className="text-slate-500 text-sm">Loading…</div>}
        {sessions && sessions.length === 0 && <div className="text-slate-500 text-sm">No sessions yet.</div>}
        {sessions?.slice(0, 5).map(s => <SessionListItem key={s.session_id} session={s} />)}
      </section>
    </div>
  );
}
