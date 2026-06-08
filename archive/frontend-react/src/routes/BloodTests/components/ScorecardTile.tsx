import { Star } from 'lucide-react';
import type { MarkerSummary } from '../lib/scorecard';
import { displayName } from '../markers';

const BORDER: Record<MarkerSummary['status'], string> = {
  in:      'border-l-emerald-500',
  out:     'border-l-red-500',
  unknown: 'border-l-slate-600',
};

const VALUE_COLOR: Record<MarkerSummary['status'], string> = {
  in:      'text-slate-100',
  out:     'text-red-400',
  unknown: 'text-slate-300',
};

function formatDate(datetime: string): string {
  return new Date(datetime).toLocaleDateString('en-GB', {
    day: 'numeric', month: 'short', year: '2-digit',
  });
}

function formatDelta(delta: number, prevValue: number): string {
  const sign = delta >= 0 ? '+' : '−';
  const abs = Math.abs(delta);
  return `${sign}${abs} from ${prevValue}`;
}

type Props = {
  summary: MarkerSummary;
  starred: boolean;
  onSelect: (marker: string) => void;
  onToggleStar: (marker: string) => void;
};

export function ScorecardTile({ summary, starred, onSelect, onToggleStar }: Props) {
  const { marker, latest, previous, delta, status } = summary;

  const refRange = latest?.ref_low != null && latest?.ref_high != null
    ? `${latest.ref_low}–${latest.ref_high} ${latest.unit}`
    : null;

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => onSelect(marker)}
      onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') onSelect(marker); }}
      className={`flex items-center gap-3 rounded border-l-4 bg-slate-800/60 px-3 py-2.5 cursor-pointer hover:bg-slate-700/60 active:bg-slate-700 ${BORDER[status]}`}
    >
      {/* left: name · date · ref range */}
      <div className="flex-1 min-w-0">
        <div className="text-sm font-medium text-slate-200 truncate">{displayName(marker)}</div>
        {latest && (
          <div className="text-xs text-slate-500 mt-0.5">{formatDate(latest.datetime)}</div>
        )}
        {refRange && (
          <div className="text-xs text-slate-600 mt-0.5">{refRange}</div>
        )}
      </div>

      {/* right: value · delta from previous */}
      <div className="text-right shrink-0">
        <div className={`text-sm font-semibold ${VALUE_COLOR[status]}`}>
          {latest ? `${latest.value} ${latest.unit}` : '—'}
        </div>
        {delta != null && previous && (
          <div className="text-xs text-slate-500 mt-0.5">
            {formatDelta(delta, previous.value)}
          </div>
        )}
      </div>

      {/* star */}
      <button
        type="button"
        onClick={e => { e.stopPropagation(); onToggleStar(marker); }}
        className="shrink-0 p-0.5"
        aria-label={starred ? 'Unstar' : 'Star'}
      >
        <Star
          size={13}
          className={starred ? 'fill-yellow-400 text-yellow-400' : 'text-slate-600 hover:text-slate-400'}
        />
      </button>
    </div>
  );
}
