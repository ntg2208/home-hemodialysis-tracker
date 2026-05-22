import { useMemo, useState } from 'react';
import type { BloodTestRow } from '../schemas';
import { filterRows } from '../lib/queryFilter';
import { FilterBar, type FilterState } from '../components/FilterBar';
import { Scorecard } from '../components/Scorecard';
import { TrendChart } from '../components/TrendChart';

type Props = { rows: BloodTestRow[] };
type Tab = 'scorecard' | 'trend';

export function Dashboard({ rows }: Props) {
  const markers = useMemo(
    () => [...new Set(rows.map((r) => r.marker))].sort(),
    [rows],
  );

  const [tab, setTab] = useState<Tab>('scorecard');
  const [filter, setFilter] = useState<FilterState>({
    phases: ['home-hd'],
    from: '',
    to: '',
    granularity: 'month',
    marker: markers[0] ?? '',
  });

  const scoped = useMemo(
    () =>
      filterRows(rows, {
        phase: filter.phases,
        from: filter.from || undefined,
        to: filter.to || undefined,
      }),
    [rows, filter.phases, filter.from, filter.to],
  );

  const trendRows = useMemo(
    () => scoped.filter((r) => r.marker === filter.marker),
    [scoped, filter.marker],
  );

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      <FilterBar filter={filter} markers={markers} onChange={setFilter} />

      <div className="flex gap-2 border-b border-slate-700 bg-slate-800 px-3">
        {(['scorecard', 'trend'] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm capitalize ${
              tab === t ? 'border-b-2 border-cyan-400 text-cyan-300' : 'text-slate-400'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'scorecard' ? (
        <Scorecard
          rows={scoped}
          onSelectMarker={(marker) => {
            setFilter((f) => ({ ...f, marker }));
            setTab('trend');
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
          <th className="py-1 pr-4">Timing</th>
          <th className="py-1">Note</th>
        </tr>
      </thead>
      <tbody className="text-slate-300">
        {sorted.map((r) => (
          <tr key={`${r.marker}-${r.lab_id}`} className="border-t border-slate-800">
            <td className="py-1 pr-4">{r.datetime.slice(0, 16).replace('T', ' ')}</td>
            <td className="py-1 pr-4">
              {r.qualitative ? r.unit : `${r.value} ${r.unit}`}
            </td>
            <td className="py-1 pr-4">
              {r.ref_low != null && r.ref_high != null ? `${r.ref_low}–${r.ref_high}` : '—'}
            </td>
            <td className="py-1 pr-4">{r.timing || '—'}</td>
            <td className="py-1">{r.note || '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
