# Blood Test Chart Redesign — Nivo Line Chart

**Date:** 2026-05-29
**Status:** Approved

## Goal

Replace the current Recharts `TrendChart` with a Nivo `@nivo/line` implementation that is visually cleaner, works better on mobile, and communicates out-of-range status through dot colour alone rather than separate indicators.

## Library Change

- **Remove:** `recharts`
- **Add:** `@nivo/line` (includes `@nivo/core`, `@nivo/tooltip`, etc.)
- Net bundle impact: +~60KB gzipped (recharts removed ~120KB, nivo/line adds ~180KB)

## Visual Design

### Single line, three dot states

All readings for a marker are plotted as one continuous line (colour: indigo `#818cf8`). Individual dots are coloured by state, evaluated in this priority order:

| State | Colour | Condition |
|---|---|---|
| Out of range | Red `#f87171` | `value < ref_low` or `value > ref_high` |
| Pre-dialysis | Cyan `#22d3ee` | `timing === 'pre'` and in range |
| Post-dialysis | Amber `#f59e0b` | `timing === 'post'` and in range |
| Plain / unknown | Indigo `#818cf8` | `timing === ''` and in range |

Out-of-range overrides timing colour. If ref_low/ref_high are absent the dot falls through to the timing colour.

### Reference range band

Rendered as a custom Nivo layer. Uses `ref_low` and `ref_high` from the most recent reading that has both values. Renders as:
- Semi-transparent indigo fill (`rgba(129,140,248,0.07)`)
- Dashed indigo lines top and bottom (`#818cf8`, opacity 0.5)

If no reading has reference range values the band is omitted.

### Latest value badge

A pill badge rendered above the last data point as a custom Nivo layer. Colour matches the last dot's state colour. Format: `{value} {unit}` (e.g. `152 g/L`).

### Filled area under line

`enableArea={true}`, `areaOpacity={0.15}`, gradient from indigo at top to transparent at bottom.

### Curve

`curve="monotoneX"` — smooth, no overshoot.

### Tooltip

Rendered only on hover/tap (`useMesh={true}`, Nivo default). Custom tooltip component showing:
- Date: `15 Jan 2024`
- Value + unit: `122 g/L` (coloured red if out of range)
- Timing: `Pre` / `Post` / `—`
- Range status: `↓ low` / `↑ high` if out of range, otherwise omitted

No persistent tooltip; crosshair line shown on hover.

### Legend

Shown below the chart only when the marker has at least one pre or post reading. Two entries:
- `● Pre` (cyan)
- `● Post` (amber)

No "Out of range" legend entry — red dots are self-explanatory.

### Axes

- **X-axis:** time scale, formatted as `Jan '24`. Auto-scales to the full date range of available data. No zoom/brush.
- **Y-axis:** linear, `min: 'auto'`, `max: 'auto'`. 5 tick values.

### Phase boundaries

Two vertical reference lines kept as custom layer markers at `2023-10-16` and `2026-02-01` (slate `#64748b`, dashed). Omitted if no data point falls on or after the boundary date.

### Dark theme

Nivo theme object matching app palette:

```ts
const nivoTheme = {
  background: 'transparent',
  textColor: '#94a3b8',
  fontSize: 11,
  axis: {
    ticks: { text: { fill: '#64748b', fontSize: 10 } },
    legend: { text: { fill: '#64748b' } },
  },
  grid: { line: { stroke: '#1e293b', strokeWidth: 1 } },
  crosshair: { line: { stroke: '#334155', strokeWidth: 1, strokeDasharray: '3 2' } },
  tooltip: { container: { background: '#1e293b', border: '1px solid #334155', fontSize: 12 } },
};
```

## Component Architecture

### `TrendChart.tsx` (full rewrite)

**Inputs:** `marker: string`, `rows: BloodTestRow[]` (already filtered to this marker, phase, date range)

**Internal functions:**

- `toNivoSeries(rows)` — filters to numeric rows, sorts by datetime, returns:
  ```ts
  {
    id: marker,
    data: Array<{ x: Date; y: number; timing: string; inRange: boolean; refLow: number|null; refHigh: number|null; unit: string }>
  }
  ```
  Point metadata (`timing`, `inRange`, `unit`) is stored on each point object for use by the custom dot renderer and tooltip.

- `getReferenceRange(rows)` — returns `{ low, high, unit }` from the most recent row with both `ref_low` and `ref_high`. Returns `null` if none found.

- `getPointColor(point)` — returns hex colour based on state priority table above.

- `ReferenceBandLayer` — custom Nivo layer component. Receives chart context (xScale, yScale, innerWidth). Renders a `<rect>` and two `<line>` elements for the reference range. No-ops if `getReferenceRange` returns null.

- `LatestValueBadgeLayer` — custom Nivo layer. Renders a rounded-rect badge above the last data point. Colour from `getPointColor` applied to last point.

- `CustomTooltip` — Nivo tooltip component. Receives the hovered point. Renders date, value, timing, range status.

**Rendering:**
```tsx
<ResponsiveLine
  data={[series]}
  layers={['grid', 'axes', ReferenceBandLayer, 'lines', 'areas', 'points', LatestValueBadgeLayer, 'mesh']}
  xScale={{ type: 'time', format: 'native', precision: 'day' }}
  xFormat="time:%b '%y"
  yScale={{ type: 'linear', min: 'auto', max: 'auto' }}
  curve="monotoneX"
  enableArea={true}
  areaOpacity={0.15}
  colors={['#818cf8']}
  lineWidth={2.5}
  pointSize={10}
  pointColor={getPointColor}
  pointBorderWidth={2}
  pointBorderColor="#0f172a"
  useMesh={true}
  tooltip={CustomTooltip}
  theme={nivoTheme}
  margin={{ top: 24, right: 24, bottom: 48, left: 44 }}
  axisBottom={{ format: "%b '%y", tickRotation: -30, tickSize: 0 }}
  axisLeft={{ tickSize: 0, tickValues: 5 }}
/>
```

**Height:** fixed `300px` container (down from 360px — no brush strip needed).

### No other file changes

`Scorecard.tsx`, `FilterBar.tsx`, `index.tsx`, `ResultsTable`, `markers.ts`, `scorecard.ts` — all unchanged.

## Out of Scope

- Qualitative markers (shown as text, no chart) — unchanged behaviour
- FilterBar (phase, date range, granularity) — unchanged
- ResultsTable below chart — unchanged
- Scorecard tiles — unchanged

---

## Update Log

### 2026-05-30 — Chart fixes, scorecard redesign, FilterBar overhaul

**Chart: same-day deduplication**
`toNivoSeries` now collapses multiple readings on the same calendar date to one point using priority `pre > post > plain`. Prevented a visual zigzag that looked like two separate lines when both pre and post readings existed on the same day. Implemented via `TIMING_RANK` map in `chartData.ts`.

**Chart: timing-only dot colour (removed red override)**
`getPointColor` was previously overriding dot colour to red when `inRange === false`, making pre and post readings indistinguishable when out of range. Changed to timing-only colours at all times (cyan=pre, amber=post, indigo=plain). Out-of-range status is still shown in the tooltip (`↓ low` / `↑ high`). The design table in the spec above is superseded — out-of-range no longer overrides timing colour.

**Scorecard tiles: horizontal list layout** (`ScorecardTile.tsx` rewritten)
Replaced the grid-card layout with horizontal rows:
- Left: marker name, date (formatted `15 Jan '26`), ref range on its own line (e.g. `130–170 g/L`)
- Right: latest value (red if out of range), delta from previous reading (`+3 from 115`)
- Left border colour: emerald=in range, red=out of range, slate=unknown
- Star button at far right; zero delta shows `+0 from X`
- `Scorecard.tsx` grids changed from `grid-cols` to `flex flex-col gap-1`

**FilterBar: month + year dropdowns** (`FilterBar.tsx` rewritten)
Replaced native `<input type="month">` (browser-inconsistent on mobile) with explicit month/year `<select>` pairs. `FilterState.granularity` field removed entirely. `bound(year, month)` helper builds `YYYY-MM` string; empty year returns `''`. `queryFilter.ts` unchanged — already used prefix comparison on YYYY-MM strings. `years: number[]` prop derived from all rows in `index.tsx`.
