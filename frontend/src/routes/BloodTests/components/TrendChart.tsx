import { ResponsiveLine } from '@nivo/line';
import type { LineCustomSvgLayerProps } from '@nivo/line';
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
  return function PhaseBoundariesLayer(props: LineCustomSvgLayerProps<ChartSeries>) {
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
  return function ReferenceBandLayer(props: LineCustomSvgLayerProps<ChartSeries>) {
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
  return function LatestValueBadgeLayer(props: LineCustomSvgLayerProps<ChartSeries>) {
    if (!props.points.length) return null;

    const lastPoint = [...props.points].sort((a, b) =>
      (a.data as ChartDatum).x.getTime() - (b.data as ChartDatum).x.getTime()
    ).at(-1);
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
          pointColor={(context) => getPointColor(context.point.data as ChartDatum)}
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
            format: (v: unknown) =>
              (v instanceof Date ? v : new Date(v as string))
                .toLocaleDateString('en-GB', { month: 'short', year: '2-digit' }),
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
