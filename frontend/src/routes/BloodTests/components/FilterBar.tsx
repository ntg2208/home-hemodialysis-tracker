import { PHASES } from '../schemas';

export type Granularity = 'month' | 'date';

export type FilterState = {
  phases: string[];
  from: string;
  to: string;
  granularity: Granularity;
  marker: string;
};

type Props = {
  filter: FilterState;
  markers: string[];
  onChange: (next: FilterState) => void;
};

export function FilterBar({ filter, markers, onChange }: Props) {
  const set = (patch: Partial<FilterState>) => onChange({ ...filter, ...patch });
  const inputType = filter.granularity === 'month' ? 'month' : 'date';

  return (
    <div className="flex flex-wrap items-end gap-3 border-b border-slate-700 bg-slate-800 p-3">
      <label className="flex flex-col text-xs text-slate-400">
        Phase
        <select
          value={filter.phases[0] ?? 'all'}
          onChange={(e) =>
            set({ phases: e.target.value === 'all' ? [] : [e.target.value] })
          }
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          <option value="all">All phases</option>
          {PHASES.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        Granularity
        <select
          value={filter.granularity}
          onChange={(e) => set({ granularity: e.target.value as Granularity })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          <option value="month">Month</option>
          <option value="date">Date</option>
        </select>
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        From
        <input
          type={inputType}
          value={filter.from}
          onChange={(e) => set({ from: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        />
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        To
        <input
          type={inputType}
          value={filter.to}
          onChange={(e) => set({ to: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        />
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        Marker (trend)
        <select
          value={filter.marker}
          onChange={(e) => set({ marker: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          {markers.map((m) => (
            <option key={m} value={m}>{m}</option>
          ))}
        </select>
      </label>
    </div>
  );
}
