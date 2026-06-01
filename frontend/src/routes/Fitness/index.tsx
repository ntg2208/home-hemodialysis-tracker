import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity, RefreshCw, CheckCircle2, AlertTriangle,
  Heart, Footprints, Moon, Wind, Thermometer, Droplet, Gauge,
} from 'lucide-react';
import { getAuth, type AuthSettings } from '../../auth/storage';
import { cloudGet, cloudPost, CloudRunError } from '../../api/cloudRun';

interface Latest { label: string; value: string; unit: string; at: string }
interface TypeSummary {
  type: string;
  last_synced?: string | null;
  count?: number;
  last_date?: string | null;
  stale?: boolean;
  latest?: Latest | null;
  bytes?: number;
  error?: string;
}
interface Summary {
  ok: true;
  generated_at: string;
  types: TypeSummary[];
  totals: { types: number; healthy: number; stale: number; bytes: number };
}
interface SyncResponse { ok: boolean; synced?: Record<string, { status: string; error?: string }> }

type State =
  | { status: 'loading' }
  | { status: 'ready'; summary: Summary; stale?: boolean }
  | { status: 'error'; message: string };

const CACHE_KEY = 'fitness_summary_cache';
const CACHE_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours

function readCache(): Summary | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const { summary, cachedAt } = JSON.parse(raw) as { summary: Summary; cachedAt: number };
    if (Date.now() - cachedAt > CACHE_TTL_MS) return null;
    return summary;
  } catch { return null; }
}

function writeCache(summary: Summary): void {
  try { localStorage.setItem(CACHE_KEY, JSON.stringify({ summary, cachedAt: Date.now() })); } catch {}
}

// Short labels + icons for the per-type status table.
const TYPE_META: Record<string, { label: string; Icon: typeof Heart }> = {
  'steps': { label: 'Steps', Icon: Footprints },
  'daily-resting-heart-rate': { label: 'Resting HR', Icon: Heart },
  'sleep': { label: 'Sleep', Icon: Moon },
  'oxygen-saturation': { label: 'SpO₂', Icon: Droplet },
  'daily-heart-rate-variability': { label: 'HRV (daily)', Icon: Activity },
  'heart-rate-variability': { label: 'HRV (raw)', Icon: Activity },
  'respiratory-rate-sleep-summary': { label: 'Respiratory rate', Icon: Wind },
  'daily-sleep-temperature-derivations': { label: 'Skin temp', Icon: Thermometer },
  'heart-rate': { label: 'Heart rate', Icon: Gauge },
};

const META_FALLBACK = { label: '', Icon: Activity };

function fmtMB(bytes: number): string {
  return bytes >= 1_000_000 ? `${(bytes / 1_000_000).toFixed(1)} MB` : `${Math.round(bytes / 1000)} KB`;
}

function daysAgo(date: string | null | undefined): string {
  if (!date) return 'never';
  const then = new Date(date + 'T00:00:00Z').getTime();
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'today';
  if (days === 1) return 'yesterday';
  return `${days} days ago`;
}

export default function Fitness() {
  const navigate = useNavigate();
  const [state, setState] = useState<State>({ status: 'loading' });
  const [syncing, setSyncing] = useState(false);
  const [syncNote, setSyncNote] = useState<string | null>(null);
  const authRef = useRef<AuthSettings | null>(null);

  function toSetup(message?: string) {
    navigate('/setup', { replace: true, state: message ? { message } : undefined });
  }

  async function load(background = false) {
    const auth = authRef.current;
    if (!auth) return;
    try {
      const summary = await cloudGet<Summary>(auth, '/api/fitness/summary');
      writeCache(summary);
      setState({ status: 'ready', summary });
    } catch (e) {
      if (e instanceof CloudRunError && e.code === 'unauthorized') {
        toSetup('Access key rejected — please re-enter.');
      } else if (!background) {
        setState({ status: 'error', message: e instanceof Error ? e.message : 'Unknown error.' });
      }
      // background refresh failure: keep showing the cached data, don't flash an error
    }
  }

  useEffect(() => {
    let cancelled = false;
    getAuth().then((auth) => {
      if (!auth) { toSetup(); return; }
      authRef.current = auth;
      if (cancelled) return;
      const cached = readCache();
      if (cached) {
        setState({ status: 'ready', summary: cached, stale: true });
        void load(true);   // refresh silently in the background
      } else {
        void load(false);  // no cache — show loading state while fetching
      }
    }).catch(() => { if (!cancelled) toSetup(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [navigate]);

  async function onSync() {
    const auth = authRef.current;
    if (!auth || syncing) return;
    setSyncing(true);
    setSyncNote(null);
    try {
      const res = await cloudPost<SyncResponse>(auth, '/api/fitness/sync', {});
      const errored = Object.entries(res.synced ?? {}).filter(([, v]) => v.status === 'error');
      setSyncNote(errored.length ? `Synced with ${errored.length} type(s) failing: ${errored.map(([k]) => k).join(', ')}` : 'Sync complete.');
      await load(false);
    } catch (e) {
      setSyncNote(e instanceof CloudRunError ? e.message : 'Sync failed.');
    } finally {
      setSyncing(false);
    }
  }

  if (state.status === 'loading') {
    return <div className="p-8 text-slate-400 text-center">Loading fitness data…</div>;
  }
  if (state.status === 'error') {
    return (
      <div className="p-8 text-center space-y-3">
        <AlertTriangle className="w-8 h-8 text-amber-400 mx-auto" />
        <p className="text-slate-300">{state.message}</p>
        <button onClick={() => void load()} className="px-4 py-2 rounded-lg bg-slate-700 text-slate-100 text-sm">Retry</button>
      </div>
    );
  }

  const { summary } = state;
  const lastSynced = summary.types.reduce<string | null>((max, t) => {
    const d = t.last_synced ?? null;
    return d && (!max || d > max) ? d : max;
  }, null);
  const allHealthy = summary.totals.stale === 0 && !summary.types.some((t) => t.error);
  const cards = summary.types.filter((t) => t.latest);
  const hasData = summary.types.some((t) => (t.count ?? 0) > 0);

  return (
    <div className="p-4 max-w-2xl mx-auto space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="flex items-center gap-2 text-xl font-semibold text-slate-100">
          <Activity className="w-5 h-5 text-cyan-400" /> Fitness
        </h1>
        <button
          onClick={() => void onSync()}
          disabled={syncing}
          className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 disabled:opacity-50 text-white text-sm"
        >
          <RefreshCw className={`w-4 h-4 ${syncing ? 'animate-spin' : ''}`} /> {syncing ? 'Syncing…' : 'Sync now'}
        </button>
      </div>

      {/* Health line */}
      <div className="flex items-center gap-2 text-sm">
        {allHealthy
          ? <CheckCircle2 className="w-4 h-4 text-emerald-400" />
          : <AlertTriangle className="w-4 h-4 text-amber-400" />}
        <span className="text-slate-300">
          Last sync {daysAgo(lastSynced)} · {summary.totals.healthy}/{summary.totals.types} types healthy
        </span>
      </div>
      {syncNote && <p className="text-xs text-slate-400">{syncNote}</p>}

      {!hasData && (
        <p className="text-slate-400 text-center py-6">No fitness data synced yet. Press “Sync now”.</p>
      )}

      {/* Latest readings */}
      {cards.length > 0 && (
        <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
          <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-3">Latest readings</h2>
          <div className="grid grid-cols-2 gap-3">
            {cards.map((t) => {
              const { Icon } = TYPE_META[t.type] ?? META_FALLBACK;
              const l = t.latest!;
              return (
                <div key={t.type} className="flex items-center gap-3">
                  <Icon className="w-4 h-4 text-cyan-400 shrink-0" />
                  <div className="min-w-0">
                    <div className="text-slate-100">
                      <span className="font-semibold">{l.value}</span>
                      {l.unit && <span className="text-slate-400 text-sm"> {l.unit}</span>}
                    </div>
                    <div className="text-xs text-slate-500 truncate">
                      {l.label}{t.type === 'oxygen-saturation' ? ' (latest sample)' : ''}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Per-type status table */}
      <div className="rounded-xl border border-slate-700 bg-slate-800/40 overflow-hidden">
        <h2 className="text-xs uppercase tracking-wide text-slate-500 px-4 pt-4 pb-2">Pipeline status</h2>
        <table className="w-full text-sm">
          <tbody>
            {summary.types.map((t) => {
              const meta = TYPE_META[t.type] ?? META_FALLBACK;
              const ok = !t.error && !t.stale;
              return (
                <tr key={t.type} className="border-t border-slate-700/60">
                  <td className="px-4 py-2 text-slate-300">
                    <span className="flex items-center gap-2">
                      <meta.Icon className="w-3.5 h-3.5 text-slate-500" /> {meta.label || t.type}
                    </span>
                  </td>
                  <td className="px-2 py-2 text-right text-slate-400 tabular-nums">
                    {t.error ? '—' : (t.count ?? 0).toLocaleString()}
                  </td>
                  <td className="px-2 py-2 text-right text-slate-500 text-xs">{t.error ? '' : t.last_date}</td>
                  <td className="px-4 py-2 text-right">
                    {t.error
                      ? <span title={t.error}><AlertTriangle className="w-4 h-4 text-red-400 inline" /></span>
                      : ok
                        ? <CheckCircle2 className="w-4 h-4 text-emerald-400 inline" />
                        : <AlertTriangle className="w-4 h-4 text-amber-400 inline" />}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p className="text-xs text-slate-500 text-center">{fmtMB(summary.totals.bytes)} stored in GCS</p>
    </div>
  );
}
