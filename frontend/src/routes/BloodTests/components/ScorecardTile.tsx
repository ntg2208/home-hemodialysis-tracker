import { Star } from 'lucide-react';
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
  starred: boolean;
  onSelect: (marker: string) => void;
  onToggleStar: (marker: string) => void;
};

export function ScorecardTile({ summary, starred, onSelect, onToggleStar }: Props) {
  const { marker, latest, delta, direction, status } = summary;
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onSelect(marker)}
      onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') onSelect(marker); }}
      className={`relative flex flex-col rounded border p-3 text-left cursor-pointer ${STATUS_STYLE[status]} hover:brightness-125`}
    >
      <button
        type="button"
        onClick={e => { e.stopPropagation(); onToggleStar(marker); }}
        className="absolute top-1 right-1 p-0.5"
        aria-label={starred ? 'Unstar' : 'Star'}
      >
        <Star
          size={13}
          className={starred ? 'fill-yellow-400 text-yellow-400' : 'text-slate-600 hover:text-slate-400'}
        />
      </button>
      <span className="text-xs text-slate-400 pr-4">{displayName(marker)}</span>
      <span className="text-lg font-semibold text-slate-100">
        {latest ? `${latest.value} ${latest.unit}` : '—'}
      </span>
      {delta != null && direction && (
        <span className="text-xs text-slate-400">
          {ARROW[direction]} {Math.abs(delta)}
        </span>
      )}
    </div>
  );
}
