import { Star } from 'lucide-react';
import type { BloodTestRow } from '../schemas';
import { summarize } from '../lib/scorecard';
import { panelFor, PANELS, type Panel } from '../markers';
import { ScorecardTile } from './ScorecardTile';

type Props = {
  rows: BloodTestRow[];
  favorites: Set<string>;
  onSelectMarker: (marker: string) => void;
  onToggleFavorite: (marker: string) => void;
};

export function Scorecard({ rows, favorites, onSelectMarker, onToggleFavorite }: Props) {
  if (rows.length === 0) {
    return <p className="p-6 text-slate-400">No results for these filters.</p>;
  }

  const byMarker = new Map<string, BloodTestRow[]>();
  for (const r of rows) {
    const list = byMarker.get(r.marker) ?? [];
    list.push(r);
    byMarker.set(r.marker, list);
  }

  const summaries = [...byMarker.entries()]
    .map(([marker, markerRows]) => summarize(marker, markerRows))
    .sort((a, b) => a.marker.localeCompare(b.marker));

  const byPanel = new Map<Panel, typeof summaries>();
  for (const s of summaries) {
    const panel = panelFor(s.marker);
    const list = byPanel.get(panel) ?? [];
    list.push(s);
    byPanel.set(panel, list);
  }

  const favSummaries = summaries.filter(s => favorites.has(s.marker));

  return (
    <div className="space-y-6 p-4">
      {favSummaries.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-yellow-500 inline-flex items-center gap-1.5">
            <Star size={13} className="fill-yellow-400 text-yellow-400" /> Favourites
          </h2>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
            {favSummaries.map(s => (
              <ScorecardTile
                key={s.marker}
                summary={s}
                starred={true}
                onSelect={onSelectMarker}
                onToggleStar={onToggleFavorite}
              />
            ))}
          </div>
        </section>
      )}

      {PANELS.filter(p => byPanel.has(p)).map(panel => (
        <section key={panel}>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400">
            {panel}
          </h2>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
            {byPanel.get(panel)!.map(s => (
              <ScorecardTile
                key={s.marker}
                summary={s}
                starred={favorites.has(s.marker)}
                onSelect={onSelectMarker}
                onToggleStar={onToggleFavorite}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
