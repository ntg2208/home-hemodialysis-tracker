# Blood Test Chart Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Recharts `TrendChart` with a Nivo `@nivo/line` chart — single line with per-dot colour (pre=cyan, post=amber, out-of-range=red), reference band, latest-value badge, hover-only tooltip, no zoom/brush.

**Architecture:** Pure data-transformation functions live in `lib/chartData.ts` (tested). The chart component `TrendChart.tsx` is fully rewritten using `ResponsiveLine` with three custom layers (reference band, phase boundaries, latest-value badge) built as closures over computed data.

**Tech Stack:** `@nivo/line` (replaces `recharts`), React 18, TypeScript, Vitest

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `frontend/src/routes/BloodTests/lib/chartData.ts` | **Create** | Types + pure functions: `toNivoSeries`, `getReferenceRange`, `getPointColor` |
| `frontend/src/routes/BloodTests/lib/chartData.test.ts` | **Create** | Vitest unit tests for all pure functions |
| `frontend/src/routes/BloodTests/components/TrendChart.tsx` | **Rewrite** | Nivo chart: theme, tooltip, custom layers, legend |
| `frontend/package.json` | **Modify** | Remove `recharts`, add `@nivo/line` |

---

## Task 1: Swap dependencies

**Files:**
- Modify: `frontend/package.json`

- [ ] **Step 1.1: Install @nivo/line**

```bash
cd frontend
npm install @nivo/line
```

Expected: `@nivo/line` and its peer deps (`@nivo/core`, `@nivo/colors`, etc.) appear in `node_modules`. No errors.

- [ ] **Step 1.2: Remove recharts**

```bash
npm uninstall recharts
```

Expected: `recharts` removed from `package.json` dependencies. `TrendChart.tsx` will now have a broken import — that's expected.

- [ ] **Step 1.3: Verify the rest of the app still type-checks (TrendChart errors expected)**

```bash
npx tsc --noEmit 2>&1 | grep -v TrendChart
```

Expected: no errors outside `TrendChart.tsx`.

- [ ] **Step 1.4: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: swap recharts for @nivo/line"
```

---

## Task 2: Data transformation layer

**Files:**
- Create: `frontend/src/routes/BloodTests/lib/chartData.ts`
- Create: `frontend/src/routes/BloodTests/lib/chartData.test.ts`

- [ ] **Step 2.1: Write the failing tests**

Create `frontend/src/routes/BloodTests/lib/chartData.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { toNivoSeries, getReferenceRange, getPointColor } from './chartData';
import type { BloodTestRow } from '../schemas';

function row(overrides: Partial<BloodTestRow> = {}): BloodTestRow {
  return {
    marker: 'haemoglobin',
    datetime: '2024-01-15T09:00:00',
    value: 130,
    unit: 'g/L',
    ref_low: 130,
    ref_high: 170,
    timing: '',
    note: '',
    source: '',
    lab_id: '',
    phase: 'home-hd',
    created_at: '2024-01-15T09:00:00',
    qualitative: false,
    ...overrides,
  };
}

describe('getReferenceRange', () => {
  it('returns null when no rows have ref values', () => {
    const rows = [row({ ref_low: null, ref_high: null })];
    expect(getReferenceRange(rows)).toBeNull();
  });

  it('returns low/high/unit from the most recent row with ref values', () => {
    const rows = [
      row({ datetime: '2024-01-01T00:00:00', ref_low: 120, ref_high: 160, unit: 'g/L' }),
      row({ datetime: '2024-06-01T00:00:00', ref_low: 130, ref_high: 170, unit: 'g/L' }),
      row({ datetime: '2024-03-01T00:00:00', ref_low: 125, ref_high: 165, unit: 'g/L' }),
    ];
    expect(getReferenceRange(rows)).toEqual({ low: 130, high: 170, unit: 'g/L' });
  });

  it('ignores rows where only one ref value is set', () => {
    const rows = [
      row({ ref_low: 130, ref_high: null }),
      row({ datetime: '2023-01-01T00:00:00', ref_low: 120, ref_high: 160 }),
    ];
    expect(getReferenceRange(rows)).toEqual({ low: 120, high: 160, unit: 'g/L' });
  });
});

describe('getPointColor', () => {
  it('returns red for out-of-range points', () => {
    expect(getPointColor({ inRange: false, timing: '' })).toBe('#f87171');
  });

  it('returns red for out-of-range even if timing is pre', () => {
    expect(getPointColor({ inRange: false, timing: 'pre' })).toBe('#f87171');
  });

  it('returns cyan for pre-dialysis in-range', () => {
    expect(getPointColor({ inRange: true, timing: 'pre' })).toBe('#22d3ee');
  });

  it('returns amber for post-dialysis in-range', () => {
    expect(getPointColor({ inRange: true, timing: 'post' })).toBe('#f59e0b');
  });

  it('returns indigo for plain in-range', () => {
    expect(getPointColor({ inRange: true, timing: '' })).toBe('#818cf8');
  });

  it('returns indigo for plain when inRange is null (no ref data)', () => {
    expect(getPointColor({ inRange: null, timing: '' })).toBe('#818cf8');
  });

  it('returns cyan for pre when inRange is null', () => {
    expect(getPointColor({ inRange: null, timing: 'pre' })).toBe('#22d3ee');
  });
});

describe('toNivoSeries', () => {
  it('filters out qualitative rows', () => {
    const rows = [
      row({ qualitative: false, value: 130 }),
      row({ datetime: '2024-02-01T00:00:00', qualitative: true, value: 999 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data).toHaveLength(1);
    expect(series.data[0].y).toBe(130);
  });

  it('sorts rows by datetime ascending', () => {
    const rows = [
      row({ datetime: '2024-03-01T00:00:00', value: 140 }),
      row({ datetime: '2024-01-01T00:00:00', value: 120 }),
      row({ datetime: '2024-02-01T00:00:00', value: 130 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data.map(d => d.y)).toEqual([120, 130, 140]);
  });

  it('sets x as a Date object', () => {
    const rows = [row({ datetime: '2024-01-15T09:00:00' })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].x).toBeInstanceOf(Date);
  });

  it('marks a point inRange=false when value is below ref_low', () => {
    const rows = [row({ value: 110, ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBe(false);
  });

  it('marks a point inRange=true when value is within range', () => {
    const rows = [row({ value: 150, ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBe(true);
  });

  it('sets inRange=null when ref values are missing', () => {
    const rows = [row({ value: 150, ref_low: null, ref_high: null })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBeNull();
  });

  it('preserves timing, unit, refLow, refHigh on each datum', () => {
    const rows = [row({ timing: 'pre', unit: 'g/L', ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    const d = series.data[0];
    expect(d.timing).toBe('pre');
    expect(d.unit).toBe('g/L');
    expect(d.refLow).toBe(130);
    expect(d.refHigh).toBe(170);
  });
});
```

- [ ] **Step 2.2: Run tests — verify they fail**

```bash
cd frontend
npx vitest run src/routes/BloodTests/lib/chartData.test.ts
```

Expected: all tests fail with "Cannot find module './chartData'".

- [ ] **Step 2.3: Implement chartData.ts**

Create `frontend/src/routes/BloodTests/lib/chartData.ts`:

```typescript
import type { BloodTestRow } from '../schemas';

export type ChartDatum = {
  x: Date;
  y: number;
  timing: string;
  inRange: boolean | null;
  unit: string;
  datetime: string;
  refLow: number | null;
  refHigh: number | null;
};

export type ChartSeries = {
  id: string;
  data: ChartDatum[];
};

export type RefRange = {
  low: number;
  high: number;
  unit: string;
};

export function getReferenceRange(rows: BloodTestRow[]): RefRange | null {
  const withRange = rows
    .filter(r => r.ref_low != null && r.ref_high != null)
    .sort((a, b) => b.datetime.localeCompare(a.datetime));
  const latest = withRange[0];
  if (!latest || latest.ref_low == null || latest.ref_high == null) return null;
  return { low: latest.ref_low, high: latest.ref_high, unit: latest.unit };
}

export function getPointColor(datum: Pick<ChartDatum, 'inRange' | 'timing'>): string {
  if (datum.inRange === false) return '#f87171';   // out of range — always red
  if (datum.timing === 'pre')  return '#22d3ee';   // pre-dialysis — cyan
  if (datum.timing === 'post') return '#f59e0b';   // post-dialysis — amber
  return '#818cf8';                                 // plain / unknown timing — indigo
}

export function toNivoSeries(marker: string, rows: BloodTestRow[]): ChartSeries {
  const data: ChartDatum[] = rows
    .filter(r => !r.qualitative)
    .sort((a, b) => a.datetime.localeCompare(b.datetime))
    .map(r => {
      const inRange =
        r.ref_low != null && r.ref_high != null
          ? r.value >= r.ref_low && r.value <= r.ref_high
          : null;
      return {
        x: new Date(r.datetime),
        y: r.value,
        timing: r.timing,
        inRange,
        unit: r.unit,
        datetime: r.datetime,
        refLow: r.ref_low,
        refHigh: r.ref_high,
      };
    });
  return { id: marker, data };
}
```

- [ ] **Step 2.4: Run tests — verify they pass**

```bash
npx vitest run src/routes/BloodTests/lib/chartData.test.ts
```

Expected: all 14 tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add src/routes/BloodTests/lib/chartData.ts src/routes/BloodTests/lib/chartData.test.ts
git commit -m "feat: add chartData pure functions for nivo line chart"
```

---

## Task 3: Rewrite TrendChart.tsx

**Files:**
- Rewrite: `frontend/src/routes/BloodTests/components/TrendChart.tsx`

The full component is assembled here. Read this task completely before starting — later steps build on earlier ones.

- [ ] **Step 3.1: Replace the file contents**

Overwrite `frontend/src/routes/BloodTests/components/TrendChart.tsx` with:

```typescript
import { ResponsiveLine } from '@nivo/line';
import type { CustomLayerProps } from '@nivo/line';
import type { BloodTestRow } from '../schemas';
import { displayName } from '../markers';
import { toNivoSeries, getReferenceRange, getPointColor } from '../lib/chartData';
import type { ChartDatum, RefRange, ChartSeries } from '../lib/chartData';

// ─── Theme ───────────────────────────────────────────────────────────────────

const NIVO_THEME = {
  background: 'transparent',
  textColor: '#94a3b8',
  fontSize: 11,
  axis: {
    ticks: {
      line: { stroke: 'transparent' },
      text: { fill: '#64748b', fontSize: 10 },
    },
    domain: { line: { stroke: '#334155' } },
  },
  grid: { line: { stroke: '#1e293b', strokeWidth: 1 } },
  crosshair: { line: { stroke: '#334155', strokeWidth: 1, strokeDasharray: '3 2' } },
};

// ─── Tooltip ─────────────────────────────────────────────────────────────────

function CustomTooltip({ point }: { point: { data: unknown } }) {
  const d = point.data as ChartDatum;
  const date = new Date(d.datetime).toLocaleDateString('en-GB', {
    day: 'numeric', month: 'short', year: 'numeric',
  });
  const outOfRange = d.inRange === false;
  let rangeLabel: string | null = null;
  if (outOfRange) {
    if (d.refHigh != null && d.y > d.refHigh) rangeLabel = '↑ high';
    else if (d.refLow != null && d.y < d.refLow) rangeLabel = '↓ low';
  }
  const timingLabel = d.timing === 'pre' ? 'Pre' : d.timing === 'post' ? 'Post' : null;
  const parts = [timingLabel, rangeLabel].filter(Boolean).join(' · ');

  return (
    <div style={{
      background: '#1e293b', border: '1px solid #334155', borderRadius: 6,
      padding: '8px 12px', fontSize: 12,
    }}>
      <div style={{ color: '#64748b', marginBottom: 4 }}>{date}</div>
      <div style={{ color: outOfRange ? '#f87171' : '#e2e8f0', fontWeight: 700, fontSize: 14 }}>
        {d.y} {d.unit}
      </div>
      {parts && (
        <div style={{ color: '#64748b', marginTop: 2 }}>{parts}</div>
      )}
    </div>
  );
}

// ─── Custom layers ────────────────────────────────────────────────────────────

const PHASE_BOUNDARIES = ['2023-10-16', '2026-02-01'];

function makePhaseBoundariesLayer() {
  return function PhaseBoundariesLayer(props: CustomLayerProps) {
    const xScale = props.xScale as (v: Date) => number;
    return (
      <g>
        {PHASE_BOUNDARIES.map(dateStr => {
          const x = xScale(new Date(dateStr));
          if (x < 0 || x > props.innerWidth) return null;
          return (
            <line key={dateStr}
              x1={x} x2={x} y1={0} y2={props.innerHeight}
              stroke="#64748b" strokeWidth={1} strokeDasharray="4 4"
            />
          );
        })}
      </g>
    );
  };
}

function makeReferenceBandLayer(refRange: RefRange | null) {
  return function ReferenceBandLayer(props: CustomLayerProps) {
    if (!refRange) return null;
    const yScale = props.yScale as (v: number) => number;
    const y1 = yScale(refRange.high);
    const y2 = yScale(refRange.low);
    if (y1 == null || y2 == null) return null;
    return (
      <g>
        <rect
          x={0} y={y1} width={props.innerWidth} height={y2 - y1}
          fill="rgba(129,140,248,0.07)"
        />
        <line x1={0} x2={props.innerWidth} y1={y1} y2={y1}
          stroke="#818cf8" strokeWidth={1.2} strokeDasharray="4 3" opacity={0.5}
        />
        <line x1={0} x2={props.innerWidth} y1={y2} y2={y2}
          stroke="#818cf8" strokeWidth={1.2} strokeDasharray="4 3" opacity={0.5}
        />
      </g>
    );
  };
}

function makeLatestValueBadgeLayer(series: ChartSeries) {
  return function LatestValueBadgeLayer(props: CustomLayerProps) {
    const points = props.points as Array<{ x: number; y: number; data: unknown }>;
    if (!points.length) return null;

    // Find the computed point with the latest original x date
    const lastPoint = [...points].sort((a, b) => {
      const ta = ((a.data as ChartDatum).x as Date).getTime();
      const tb = ((b.data as ChartDatum).x as Date).getTime();
      return ta - tb;
    }).at(-1);
    if (!lastPoint) return null;

    const lastDatum = series.data.at(-1);
    if (!lastDatum) return null;

    const color = getPointColor(lastDatum);
    const label = `${lastDatum.y} ${lastDatum.unit}`;
    const charW = 7;
    const padX = 10;
    const badgeW = label.length * charW + padX * 2;
    const badgeH = 18;
    const cx = lastPoint.x;
    const cy = lastPoint.y;
    const badgeX = Math.min(cx - badgeW / 2, props.innerWidth - badgeW);
    const badgeY = cy - 28;

    return (
      <g>
        <rect x={badgeX} y={badgeY} width={badgeW} height={badgeH} rx={9} fill={color} />
        <text
          x={badgeX + badgeW / 2} y={badgeY + 12}
          textAnchor="middle" fill="#0f172a" fontSize={10} fontWeight={800}
        >
          {label}
        </text>
      </g>
    );
  };
}

// ─── Component ────────────────────────────────────────────────────────────────

type Props = {
  marker: string;
  rows: BloodTestRow[];
};

export function TrendChart({ marker, rows }: Props) {
  const series = toNivoSeries(marker, rows);

  if (series.data.length === 0) {
    return (
      <p className="p-6 text-slate-400">
        No numeric readings for {displayName(marker)} in this range.
      </p>
    );
  }

  const refRange = getReferenceRange(rows);
  const hasPrePost = series.data.some(d => d.timing === 'pre' || d.timing === 'post');

  const ReferenceBandLayer = makeReferenceBandLayer(refRange);
  const LatestValueBadgeLayer = makeLatestValueBadgeLayer(series);
  const PhaseBoundariesLayer = makePhaseBoundariesLayer();

  return (
    <div className="p-4">
      <h2 className="mb-2 text-sm font-semibold text-slate-200">{displayName(marker)}</h2>

      <div style={{ height: 300 }}>
        <ResponsiveLine
          data={[series]}
          margin={{ top: 28, right: 28, bottom: 48, left: 44 }}
          xScale={{ type: 'time', format: 'native', precision: 'day' }}
          yScale={{ type: 'linear', min: 'auto', max: 'auto', nice: true }}
          curve="monotoneX"
          enableArea
          areaOpacity={0.12}
          colors={['#818cf8']}
          lineWidth={2.5}
          pointSize={10}
          pointColor={(datum) => getPointColor(datum.data as ChartDatum)}
          pointBorderWidth={2}
          pointBorderColor="#0f172a"
          enablePointLabel={false}
          useMesh
          tooltip={CustomTooltip}
          theme={NIVO_THEME}
          layers={[
            'grid',
            'axes',
            ReferenceBandLayer,
            PhaseBoundariesLayer,
            'lines',
            'areas',
            'points',
            LatestValueBadgeLayer,
            'mesh',
          ]}
          axisBottom={{
            format: (v: Date) =>
              v.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' }),
            tickRotation: -30,
            tickSize: 0,
          }}
          axisLeft={{
            tickSize: 0,
            tickValues: 5,
          }}
          enableGridX={false}
        />
      </div>

      {hasPrePost && (
        <div className="flex gap-4 mt-2 px-1">
          <span className="flex items-center gap-1.5 text-xs text-slate-400">
            <svg width="10" height="10">
              <circle cx="5" cy="5" r="4.5" fill="#22d3ee" />
            </svg>
            Pre
          </span>
          <span className="flex items-center gap-1.5 text-xs text-slate-400">
            <svg width="10" height="10">
              <circle cx="5" cy="5" r="4.5" fill="#f59e0b" />
            </svg>
            Post
          </span>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3.2: Run type-check**

```bash
cd frontend
npx tsc --noEmit 2>&1
```

Expected: no errors. If Nivo's `CustomLayerProps` causes type errors on `pointColor` or layer props, resolve with targeted casts (e.g., `pointColor={(datum) => getPointColor(datum.data as ChartDatum)}`). Do not suppress with `// @ts-ignore` — use specific type assertions or narrowing.

Common fix if `axisBottom.format` type complains about `Date` param — Nivo's xScale for time format passes `Date` objects; cast:
```typescript
format: (v: unknown) =>
  (v instanceof Date ? v : new Date(v as string))
    .toLocaleDateString('en-GB', { month: 'short', year: '2-digit' }),
```

- [ ] **Step 3.3: Run full test suite**

```bash
npx vitest run
```

Expected: all tests pass (new chartData tests + any existing tests).

- [ ] **Step 3.4: Commit**

```bash
git add src/routes/BloodTests/components/TrendChart.tsx
git commit -m "feat: replace recharts TrendChart with nivo/line"
```

---

## Task 4: Build verification

**Files:** none changed

- [ ] **Step 4.1: Production build**

```bash
cd frontend
npm run build 2>&1
```

Expected: clean build, no TypeScript or Vite errors. Note the final bundle size — it should be comparable to before (recharts ~120KB removed, @nivo/line ~180KB added).

- [ ] **Step 4.2: Visual smoke check**

Start the dev server and open the Tests tab:

```bash
npm run dev
```

Open `http://localhost:5173/blood-tests`. Select any marker with numeric readings and click through to the trend view. Verify:
- [ ] Line renders with smooth curve and filled area underneath
- [ ] Dots are coloured correctly (red for any out-of-range points; cyan/amber for pre/post in-range)
- [ ] No tooltip visible on idle
- [ ] Hovering/tapping a dot shows tooltip with date, value + unit, timing, range direction if applicable
- [ ] Reference band visible for markers with ref_low/ref_high data
- [ ] Latest value badge appears above last dot
- [ ] X-axis labels show `Jan 24` style dates, rotated
- [ ] Pre/Post legend appears below chart only for markers that have pre or post readings
- [ ] Phase boundary dashed lines visible if any data points fall after 2023-10-16 or 2026-02-01

- [ ] **Step 4.3: Commit**

```bash
git add -A
git commit -m "chore: verify nivo line chart build"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ Library swap (recharts out, @nivo/line in) — Task 1
- ✅ Single line, three dot states (out-of-range=red, pre=cyan, post=amber, plain=indigo) — `getPointColor`, Task 2 + 3
- ✅ Reference range band (semi-transparent fill, dashed lines) — `makeReferenceBandLayer`, Task 3
- ✅ Latest value badge (pill above last dot, colour matches dot) — `makeLatestValueBadgeLayer`, Task 3
- ✅ Hover-only tooltip (date, value+unit, timing, ↑/↓ range status) — `CustomTooltip`, Task 3
- ✅ No zoom/brush — `ResponsiveLine` has no `enableSlices` or brush
- ✅ X-axis `Jan 24` format — `axisBottom.format`, Task 3
- ✅ Pre/Post legend below chart only when pre/post data present — `hasPrePost` guard, Task 3
- ✅ Phase boundary lines — `makePhaseBoundariesLayer`, Task 3
- ✅ Dark theme — `NIVO_THEME`, Task 3
- ✅ Filled area under line — `enableArea`, Task 3
- ✅ Smooth curve — `curve="monotoneX"`, Task 3
- ✅ No "out of range" legend entry — only Pre/Post in legend, Task 3
- ✅ Qualitative markers unchanged — `toNivoSeries` filters them; empty-data path returns `<p>`, Task 2 + 3
