import type { MarkerSummary } from '../lib/scorecard';
import { displayName } from '../markers';

const STATUS_STYLE: Record<MarkerSummary['status'], string> = {
  in: 'border-emerald-600 bg-emerald-950',
  out: 'border-red-600 bg-red-950',
  unknown: 'border-slate-600 bg-slate-800',
};

const ARROW: Record<NonNullable<MarkerSummary['direction']>, string> = {
  up: '↑', down: '↓', flat: '→',
};

type Props = {
  summary: MarkerSummary;
  onSelect: (marker: string) => void;
};

export function ScorecardTile({ summary, onSelect }: Props) {
  const { marker, latest, delta, direction, status } = summary;
  return (
    <button
      type="button"
      onClick={() => onSelect(marker)}
      className={`flex flex-col rounded border p-3 text-left ${STATUS_STYLE[status]}
                  hover:brightness-125`}
    >
      <span className="text-xs text-slate-400">{displayName(marker)}</span>
      <span className="text-lg font-semibold text-slate-100">
        {latest ? `${latest.value} ${latest.unit}` : '—'}
      </span>
      {delta != null && direction && (
        <span className="text-xs text-slate-400">
          {ARROW[direction]} {Math.abs(delta)}
        </span>
      )}
    </button>
  );
}
