import { PHASES } from '../schemas';

export type FilterState = {
  phases: string[];
  from: string;   // YYYY-MM or ''
  to: string;     // YYYY-MM or ''
  marker: string;
};

const MONTHS = [
  { value: '01', label: 'Jan' }, { value: '02', label: 'Feb' },
  { value: '03', label: 'Mar' }, { value: '04', label: 'Apr' },
  { value: '05', label: 'May' }, { value: '06', label: 'Jun' },
  { value: '07', label: 'Jul' }, { value: '08', label: 'Aug' },
  { value: '09', label: 'Sep' }, { value: '10', label: 'Oct' },
  { value: '11', label: 'Nov' }, { value: '12', label: 'Dec' },
];

type Props = {
  filter: FilterState;
  markers: string[];
  years: number[];
  onChange: (next: FilterState) => void;
};

function bound(year: string, month: string): string {
  if (!year) return '';
  return month ? `${year}-${month}` : '';
}

export function FilterBar({ filter, markers, years, onChange }: Props) {
  const set = (patch: Partial<FilterState>) => onChange({ ...filter, ...patch });

  const fromYear  = filter.from.slice(0, 4);
  const fromMonth = filter.from.slice(5, 7);
  const toYear    = filter.to.slice(0, 4);
  const toMonth   = filter.to.slice(5, 7);

  function setFrom(year: string, month: string) {
    set({ from: bound(year, month) });
  }
  function setTo(year: string, month: string) {
    set({ to: bound(year, month) });
  }

  const selectCls = 'mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100';

  return (
    <div className="flex flex-wrap items-end gap-3 border-b border-slate-700 bg-slate-800 p-3">

      <label className="flex flex-col text-xs text-slate-400">
        Phase
        <select
          value={filter.phases[0] ?? 'all'}
          onChange={e => set({ phases: e.target.value === 'all' ? [] : [e.target.value] })}
          className={selectCls}
        >
          <option value="all">All phases</option>
          {PHASES.map(p => <option key={p} value={p}>{p}</option>)}
        </select>
      </label>

      <div className="flex flex-col text-xs text-slate-400">
        From
        <div className="flex gap-1 mt-1">
          <select
            value={fromMonth}
            onChange={e => setFrom(fromYear, e.target.value)}
            className={selectCls + ' mt-0'}
          >
            <option value="">Month</option>
            {MONTHS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
          <select
            value={fromYear}
            onChange={e => setFrom(e.target.value, fromMonth)}
            className={selectCls + ' mt-0'}
          >
            <option value="">Year</option>
            {years.map(y => <option key={y} value={String(y)}>{y}</option>)}
          </select>
        </div>
      </div>

      <div className="flex flex-col text-xs text-slate-400">
        To
        <div className="flex gap-1 mt-1">
          <select
            value={toMonth}
            onChange={e => setTo(toYear, e.target.value)}
            className={selectCls + ' mt-0'}
          >
            <option value="">Month</option>
            {MONTHS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
          <select
            value={toYear}
            onChange={e => setTo(e.target.value, toMonth)}
            className={selectCls + ' mt-0'}
          >
            <option value="">Year</option>
            {years.map(y => <option key={y} value={String(y)}>{y}</option>)}
          </select>
        </div>
      </div>

      <label className="flex flex-col text-xs text-slate-400">
        Marker (trend)
        <select
          value={filter.marker}
          onChange={e => set({ marker: e.target.value })}
          className={selectCls}
        >
          {markers.map(m => <option key={m} value={m}>{m}</option>)}
        </select>
      </label>

    </div>
  );
}
