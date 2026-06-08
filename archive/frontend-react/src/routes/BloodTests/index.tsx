import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';

const FAV_KEY = 'blood_test_favorites';
function loadFavorites(): Set<string> {
  try {
    const raw = localStorage.getItem(FAV_KEY);
    if (!raw) return new Set();
    return new Set(JSON.parse(raw) as string[]);
  } catch { return new Set(); }
}
function saveFavorites(s: Set<string>): void {
  try { localStorage.setItem(FAV_KEY, JSON.stringify([...s])); } catch {}
}
import { getAuth, type AuthSettings } from '../../auth/storage';
import { fetchRange, ApiError } from './api';
import type { BloodTestRow } from './schemas';
import { filterRows } from './lib/queryFilter';
import { mergeRows, sixMonthsAgo, computeFetchRange, earlierMonth } from './lib/cache';
import { readCache, writeCache } from './storage';
import { FilterBar, type FilterState } from './components/FilterBar';
import { Scorecard } from './components/Scorecard';
import { TrendChart } from './components/TrendChart';

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | {
      status: 'ready';
      rows: BloodTestRow[];
      coveredFrom: string;
      lastSynced: number | null;
      refreshing: boolean;
      refreshError: boolean;
    };

type Tab = 'scorecard' | 'trend';

function ResultsTable({ rows }: { rows: BloodTestRow[] }) {
  if (rows.length === 0) return null;
  const sorted = [...rows].sort((a, b) => b.datetime.localeCompare(a.datetime));
  return (
    <table className="m-4 w-[calc(100%-2rem)] text-left text-sm">
      <thead className="text-xs uppercase text-slate-400">
        <tr>
          <th className="py-1 pr-4">Date</th>
          <th className="py-1 pr-4">Value</th>
          <th className="py-1 pr-4">Range</th>
          <th className="py-1 pr-4">Flag</th>
          <th className="py-1 pr-4">Timing</th>
          <th className="py-1">Note</th>
        </tr>
      </thead>
      <tbody className="text-slate-300">
        {sorted.map((r) => {
          const flag =
            r.qualitative || r.ref_low == null || r.ref_high == null
              ? null
              : r.value >= r.ref_low && r.value <= r.ref_high ? 'in' : 'out';
          return (
            <tr key={`${r.marker}-${r.lab_id}`} className="border-t border-slate-800">
              <td className="py-1 pr-4">{r.datetime.slice(0, 16).replace('T', ' ')}</td>
              <td className="py-1 pr-4">{r.qualitative ? r.unit : `${r.value} ${r.unit}`}</td>
              <td className="py-1 pr-4">
                {r.ref_low != null && r.ref_high != null ? `${r.ref_low}–${r.ref_high}` : '—'}
              </td>
              <td className={`py-1 pr-4 ${flag === 'out' ? 'text-red-400' : flag === 'in' ? 'text-emerald-400' : ''}`}>
                {flag ?? '—'}
              </td>
              <td className="py-1 pr-4">{r.timing || '—'}</td>
              <td className="py-1">{r.note || '—'}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

interface DashboardProps {
  rows: BloodTestRow[];
  refreshing: boolean;
  refreshError: boolean;
  lastSynced: number | null;
  onRequireRange: (from: string) => void;
  onSync: (from: string) => void;
}

function syncLabel(lastSynced: number | null, refreshing: boolean, refreshError: boolean): string {
  if (refreshing) return 'Syncing…';
  if (refreshError) return 'Offline — showing cached';
  if (lastSynced == null) return 'Not synced yet';
  const mins = Math.round((Date.now() - lastSynced) / 60000);
  if (mins < 1) return 'Synced just now';
  if (mins < 60) return `Synced ${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `Synced ${hrs}h ago`;
  return `Synced ${Math.round(hrs / 24)}d ago`;
}

function Dashboard({ rows, refreshing, refreshError, lastSynced, onRequireRange, onSync }: DashboardProps) {
  const markers = useMemo(() => [...new Set(rows.map((r) => r.marker))].sort(), [rows]);
  // Year options span the full record (in-center era → now) so older ranges are
  // selectable even before they're cached — picking one triggers a backfill fetch.
  const years = useMemo(() => {
    const nowYear = new Date().getFullYear();
    const ys = new Set<number>(rows.map((r) => parseInt(r.datetime.slice(0, 4))));
    for (let y = 2023; y <= nowYear; y++) ys.add(y);
    return [...ys].sort();
  }, [rows]);
  const [tab, setTab] = useState<Tab>('scorecard');
  const [favorites, setFavorites] = useState<Set<string>>(() => loadFavorites());
  const [filter, setFilter] = useState<FilterState>({
    phases: ['home-hd'],
    from: '',
    to: '',
    marker: markers[0] ?? '',
  });

  // When the user picks an older `from`, ensure that range is fetched + cached.
  useEffect(() => {
    if (filter.from) onRequireRange(filter.from);
  }, [filter.from, onRequireRange]);

  const scoped = useMemo(
    () => filterRows(rows, { phase: filter.phases, from: filter.from || undefined, to: filter.to || undefined }),
    [rows, filter.phases, filter.from, filter.to],
  );
  const trendRows = useMemo(() => scoped.filter((r) => r.marker === filter.marker), [scoped, filter.marker]);

  function selectMarker(marker: string) {
    setFilter(f => ({ ...f, marker }));
    if (tab !== 'trend') {
      window.history.pushState({ bloodTestTrend: true }, '');
      setTab('trend');
    }
  }

  // Intercept back button while in trend view to return to scorecard
  useEffect(() => {
    if (tab !== 'trend') return;
    const handler = () => setTab('scorecard');
    window.addEventListener('popstate', handler);
    return () => window.removeEventListener('popstate', handler);
  }, [tab]);

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      <FilterBar filter={filter} markers={markers} years={years} onChange={setFilter} />
      <div className="flex items-center justify-between border-b border-slate-700 bg-slate-800 px-3 py-1.5">
        <span className={`text-xs ${refreshError ? 'text-amber-400' : 'text-slate-500'}`}>
          {syncLabel(lastSynced, refreshing, refreshError)}
        </span>
        <button
          type="button"
          disabled={refreshing}
          onClick={() => onSync(filter.from)}
          className="rounded bg-cyan-700 px-3 py-1 text-xs font-medium text-white disabled:opacity-50 hover:bg-cyan-600"
        >
          {refreshing ? 'Syncing…' : 'Sync'}
        </button>
      </div>
      <div className="flex gap-2 border-b border-slate-700 bg-slate-800 px-3">
        {(['scorecard', 'trend'] as Tab[]).map((t) => (
          <button key={t} type="button"
            onClick={() => { if (t === 'trend') selectMarker(filter.marker); else setTab('scorecard'); }}
            className={`px-3 py-2 text-sm capitalize ${tab === t ? 'border-b-2 border-cyan-400 text-cyan-300' : 'text-slate-400'}`}>
            {t}
          </button>
        ))}
      </div>
      {tab === 'scorecard' ? (
        <Scorecard
          rows={scoped}
          favorites={favorites}
          onSelectMarker={selectMarker}
          onToggleFavorite={(marker) => {
            setFavorites(prev => {
              const next = new Set(prev);
              if (next.has(marker)) next.delete(marker); else next.add(marker);
              saveFavorites(next);
              return next;
            });
          }}
        />
      ) : (
        <>
          <TrendChart marker={filter.marker} rows={trendRows} />
          <ResultsTable rows={trendRows} />
        </>
      )}
    </div>
  );
}

export default function BloodTests() {
  const navigate = useNavigate();
  const [state, setState] = useState<State>({ status: 'loading' });
  const authRef = useRef<AuthSettings | null>(null);

  function toSetup(message?: string) {
    navigate('/setup', { replace: true, state: message ? { message } : undefined });
  }

  // Cache-first: render cache immediately, then revalidate the default 6-month
  // window in the background. Empty cache → fetch 6 months before first render.
  useEffect(() => {
    let cancelled = false;
    getAuth().then(async (auth) => {
      if (!auth) { toSetup(); return; }
      authRef.current = auth;
      const cache = await readCache();
      const defaultFrom = sixMonthsAgo(new Date());

      if (cache.rows.length > 0) {
        if (cancelled) return;
        setState({
          status: 'ready',
          rows: cache.rows,
          coveredFrom: cache.coveredFrom ?? defaultFrom,
          lastSynced: cache.lastSynced,
          refreshing: true,
          refreshError: false,
        });
        void revalidate(defaultFrom);
        return;
      }

      // Empty cache — must hit the network once.
      try {
        const { rows } = await fetchRange(auth, { from: defaultFrom });
        const now = Date.now();
        await writeCache(rows, defaultFrom, now);
        if (cancelled) return;
        setState({ status: 'ready', rows, coveredFrom: defaultFrom, lastSynced: now, refreshing: false, refreshError: false });
      } catch (e) {
        if (cancelled) return;
        if (e instanceof ApiError && e.code === 'unauthorized') {
          toSetup('Access key rejected — please re-enter.');
        } else {
          setState({ status: 'error', message: e instanceof Error ? e.message : 'Unknown error.' });
        }
      }
    }).catch(() => { if (!cancelled) toSetup(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [navigate]);

  // Re-fetch [fromFloor → now], merge (picks up new rows + edits), update lastSynced.
  // On failure keep cached rows and flag refreshError — never blank the screen.
  async function revalidate(fromFloor: string) {
    const auth = authRef.current;
    if (!auth) return;
    setState((s) => (s.status === 'ready' ? { ...s, refreshing: true, refreshError: false } : s));
    try {
      const { rows: fresh } = await fetchRange(auth, { from: fromFloor });
      const now = Date.now();
      setState((s) => {
        if (s.status !== 'ready') return s;
        const merged = mergeRows(s.rows, fresh);
        const coveredFrom = earlierMonth(fromFloor, s.coveredFrom) ? fromFloor : s.coveredFrom;
        void writeCache(merged, coveredFrom, now);
        return { ...s, rows: merged, coveredFrom, lastSynced: now, refreshing: false, refreshError: false };
      });
    } catch (e) {
      if (e instanceof ApiError && e.code === 'unauthorized') { toSetup('Access key rejected — please re-enter.'); return; }
      setState((s) => (s.status === 'ready' ? { ...s, refreshing: false, refreshError: true } : s));
    }
  }

  // Backfill only the uncovered older slice when a range older than coverage is picked.
  async function ensureRange(requestedFrom: string) {
    const auth = authRef.current;
    if (!auth || state.status !== 'ready') return;
    const need = computeFetchRange(state.coveredFrom, requestedFrom);
    if (!need) return;
    setState((s) => (s.status === 'ready' ? { ...s, refreshing: true, refreshError: false } : s));
    try {
      const { rows: older } = await fetchRange(auth, need);
      const now = Date.now();
      setState((s) => {
        if (s.status !== 'ready') return s;
        const merged = mergeRows(s.rows, older);
        void writeCache(merged, requestedFrom, now);
        return { ...s, rows: merged, coveredFrom: requestedFrom, lastSynced: now, refreshing: false, refreshError: false };
      });
    } catch (e) {
      if (e instanceof ApiError && e.code === 'unauthorized') { toSetup('Access key rejected — please re-enter.'); return; }
      setState((s) => (s.status === 'ready' ? { ...s, refreshing: false, refreshError: true } : s));
    }
  }

  if (state.status === 'loading') {
    return <div className="min-h-screen bg-slate-900 p-8 text-slate-400">Loading…</div>;
  }
  if (state.status === 'error') {
    return (
      <div className="min-h-screen bg-slate-900 p-8 text-center">
        <p className="mb-4 text-red-400">{state.message}</p>
        <button type="button" onClick={() => window.location.reload()}
          className="rounded bg-cyan-600 px-4 py-2 font-medium text-white hover:bg-cyan-500">
          Retry
        </button>
      </div>
    );
  }
  return (
    <Dashboard
      rows={state.rows}
      refreshing={state.refreshing}
      refreshError={state.refreshError}
      lastSynced={state.lastSynced}
      onRequireRange={ensureRange}
      onSync={(from) => revalidate(from || sixMonthsAgo(new Date()))}
    />
  );
}
