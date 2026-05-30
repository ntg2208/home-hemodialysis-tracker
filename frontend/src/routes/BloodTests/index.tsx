import { useEffect, useMemo, useState } from 'react';
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
import { getAuth } from '../../auth/storage';
import { fetchAll, ApiError } from './api';
import type { BloodTestRow } from './schemas';
import { filterRows } from './lib/queryFilter';
import { FilterBar, type FilterState } from './components/FilterBar';
import { Scorecard } from './components/Scorecard';
import { TrendChart } from './components/TrendChart';

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; rows: BloodTestRow[] };

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

function Dashboard({ rows }: { rows: BloodTestRow[] }) {
  const markers = useMemo(() => [...new Set(rows.map((r) => r.marker))].sort(), [rows]);
  const years = useMemo(
    () => [...new Set(rows.map((r) => parseInt(r.datetime.slice(0, 4))))].sort(),
    [rows],
  );
  const [tab, setTab] = useState<Tab>('scorecard');
  const [favorites, setFavorites] = useState<Set<string>>(() => loadFavorites());
  const [filter, setFilter] = useState<FilterState>({
    phases: ['home-hd'],
    from: '',
    to: '',
    marker: markers[0] ?? '',
  });

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

  useEffect(() => {
    getAuth().then(async (auth) => {
      if (!auth) { navigate('/setup', { replace: true }); return; }
      try {
        const { rows } = await fetchAll(auth);
        setState({ status: 'ready', rows });
      } catch (e) {
        if (e instanceof ApiError && e.code === 'unauthorized') {
          navigate('/setup', { replace: true, state: { message: 'Access key rejected — please re-enter.' } });
        } else {
          setState({ status: 'error', message: e instanceof Error ? e.message : 'Unknown error.' });
        }
      }
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

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
  return <Dashboard rows={state.rows} />;
}
