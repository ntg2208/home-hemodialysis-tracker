import { useEffect, useState } from 'react';
import { Activity, CalendarDays, Check, Pencil, Play, RefreshCw, Settings as SettingsIcon, X } from 'lucide-react';
import { getAll, ApiError } from '../api';
import {
  clearSettings,
  getCachedSessions,
  getDriedWeight,
  saveCachedSessions,
  saveDriedWeight,
} from '../storage';
import type { Session, Settings } from '../schemas';
import { SessionListItem } from '../components/SessionListItem';

interface Props {
  settings: Settings;
  onStartSession: (existingIds: string[]) => void;
  onSettingsCleared: () => void;
}

export function Home({ settings, onStartSession, onSettingsCleared }: Props) {
  const [sessions, setSessions] = useState<Session[] | null>(null);
  // Start session is gated on a fresh load so nextSessionId() doesn't collide
  // with ids the cache missed (e.g., a session created from another device).
  const [freshLoaded, setFreshLoaded] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [driedWeight, setDriedWeight] = useState<number | null>(null);
  const [editingDried, setEditingDried] = useState(false);
  const [driedDraft, setDriedDraft] = useState('');

  useEffect(() => {
    getDriedWeight().then(setDriedWeight).catch(() => setDriedWeight(59));
  }, []);

  function startEditDried() {
    setDriedDraft(driedWeight != null ? String(driedWeight) : '');
    setEditingDried(true);
  }

  async function commitDried() {
    const n = Number(driedDraft);
    if (!Number.isFinite(n) || n <= 0) { setEditingDried(false); return; }
    setDriedWeight(n);
    setEditingDried(false);
    saveDriedWeight(n).catch(() => {});
  }

  async function load() {
    setError(null);
    setRefreshing(true);
    try {
      const r = await getAll(settings);
      const sorted = [...r.sessions].sort((a, b) => b.date.localeCompare(a.date));
      setSessions(sorted);
      setFreshLoaded(true);
      saveCachedSessions(sorted).catch(() => {});
    } catch (e) {
      setError(e instanceof ApiError ? `Load failed: ${e.code}` : String(e));
    } finally {
      setRefreshing(false);
    }
  }

  useEffect(() => {
    // Render from cache first (instant) then refresh from the backend.
    // Apps Script cold starts can take several seconds; the cache hides that.
    let cancelled = false;
    getCachedSessions()
      .then(cached => {
        if (!cancelled && cached && sessions === null) setSessions(cached);
      })
      .catch(() => {})
      .finally(() => { if (!cancelled) load(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold inline-flex items-center gap-2">
          <Activity size={24} className="text-accent" /> Treatment tracker
          <span className="text-xs font-normal text-slate-500 ml-1">v2</span>
        </h1>
        <button
          type="button"
          onClick={clearAndReset}
          aria-label="Settings"
          className="text-slate-500 hover:text-slate-300 p-1"
        >
          <SettingsIcon size={20} />
        </button>
      </header>

      <button
        type="button"
        onClick={() => onStartSession(ids)}
        disabled={!freshLoaded}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-4 text-lg disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
      >
        <Play size={22} fill="currentColor" /> Start session
      </button>

      <div className="bg-panel border border-slate-700 rounded-lg px-3 py-2 flex items-center justify-between gap-3">
        <span className="text-sm text-slate-400">Dried weight</span>
        {editingDried ? (
          <div className="flex items-center gap-2">
            <input
              type="number"
              inputMode="decimal"
              step="any"
              autoFocus
              value={driedDraft}
              onChange={e => setDriedDraft(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter') commitDried();
                if (e.key === 'Escape') setEditingDried(false);
              }}
              className="w-20 bg-bg border border-slate-700 rounded px-2 py-1 text-right focus:border-accent focus:outline-none"
            />
            <span className="text-sm text-slate-500">kg</span>
            <button
              type="button"
              onClick={commitDried}
              aria-label="Save dried weight"
              className="text-accent hover:opacity-80 p-1"
            >
              <Check size={18} />
            </button>
            <button
              type="button"
              onClick={() => setEditingDried(false)}
              aria-label="Cancel"
              className="text-slate-500 hover:text-slate-300 p-1"
            >
              <X size={18} />
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={startEditDried}
            className="inline-flex items-center gap-2 text-slate-200 hover:text-accent"
          >
            <span className="font-semibold">
              {driedWeight != null ? `${driedWeight} kg` : '—'}
            </span>
            <Pencil size={14} className="text-slate-500" />
          </button>
        )}
      </div>

      <section className="space-y-2">
        <h2 className="text-sm uppercase tracking-wide text-slate-500 inline-flex items-center justify-between">
          <span className="inline-flex items-center gap-2">
            <CalendarDays size={14} /> Recent sessions
          </span>
          {refreshing && sessions !== null && (
            <span className="inline-flex items-center gap-1 normal-case tracking-normal text-slate-500">
              <RefreshCw size={12} className="animate-spin" /> refreshing
            </span>
          )}
        </h2>
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
