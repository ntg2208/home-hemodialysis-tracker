import {
  ComposedChart, Line, Area, XAxis, YAxis, Tooltip, CartesianGrid,
  ReferenceLine, Brush, ResponsiveContainer,
} from 'recharts';
import type { BloodTestRow } from '../schemas';
import { displayName } from '../markers';

type Props = {
  marker: string;
  rows: BloodTestRow[]; // already filtered to this marker + phase + range
};

type Point = {
  datetime: string;
  pre: number | null;
  post: number | null;
  plain: number | null;
  range: [number, number] | null;
  outlier: number | null;
};

// Phase boundary dates (from the spec's data model).
const PHASE_BOUNDARIES = ['2023-10-16', '2026-02-01'];

function toPoints(rows: BloodTestRow[]): Point[] {
  return rows
    .filter((r) => !r.qualitative)
    .slice()
    .sort((a, b) => a.datetime.localeCompare(b.datetime))
    .map((r) => {
      const lo = r.ref_low;
      const hi = r.ref_high;
      const range: [number, number] | null = lo != null && hi != null ? [lo, hi] : null;
      const out = range != null && (r.value < range[0] || r.value > range[1]);
      return {
        datetime: r.datetime,
        pre: r.timing === 'pre' ? r.value : null,
        post: r.timing === 'post' ? r.value : null,
        plain: r.timing === '' ? r.value : null,
        range,
        outlier: out ? r.value : null,
      };
    });
}

export function TrendChart({ marker, rows }: Props) {
  const data = toPoints(rows);

  if (data.length === 0) {
    return <p className="p-6 text-slate-400">No numeric readings for {displayName(marker)} in this range.</p>;
  }

  const hasPrePost = data.some((d) => d.pre != null || d.post != null);

  return (
    <div className="p-4">
      <h2 className="mb-2 text-sm font-semibold text-slate-200">{displayName(marker)}</h2>
      <ResponsiveContainer width="100%" height={360}>
        <ComposedChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 0 }}>
          <CartesianGrid stroke="#334155" strokeDasharray="3 3" />
          <XAxis dataKey="datetime" tick={{ fontSize: 11, fill: '#94a3b8' }} minTickGap={32} />
          <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} />
          <Tooltip
            contentStyle={{ background: '#1e293b', border: '1px solid #334155', fontSize: 12 }}
          />
          <Area
            dataKey="range"
            type="stepAfter"
            stroke="none"
            fill="#22d3ee"
            fillOpacity={0.12}
            isAnimationActive={false}
          />
          {PHASE_BOUNDARIES.map((d) => (
            <ReferenceLine key={d} x={data.find((p) => p.datetime.slice(0, 10) >= d)?.datetime}
              stroke="#64748b" strokeDasharray="4 4" />
          ))}
          {hasPrePost ? (
            <>
              <Line dataKey="pre" name="Pre" stroke="#22d3ee" dot connectNulls
                isAnimationActive={false} />
              <Line dataKey="post" name="Post" stroke="#f59e0b" dot connectNulls
                isAnimationActive={false} />
            </>
          ) : (
            <Line dataKey="plain" name={displayName(marker)} stroke="#22d3ee" dot
              connectNulls isAnimationActive={false} />
          )}
          <Line
            dataKey="outlier"
            name="Out of range"
            stroke="none"
            legendType="none"
            dot={{ r: 5, fill: '#f87171', stroke: '#f87171' }}
            isAnimationActive={false}
          />
          <Brush dataKey="datetime" height={20} stroke="#475569" fill="#0f172a" />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
