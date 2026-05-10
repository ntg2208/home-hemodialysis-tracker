import { useState } from 'react';
import { ApiError, saveReading } from '../api';
import { AddReadingModal } from '../components/AddReadingModal';
import type { Reading, Settings } from '../schemas';

interface Props {
  settings: Settings;
  sessionId: string;
  onEnd: () => void;
}

interface PendingReading extends Reading {
  status: 'pending' | 'saved' | 'error';
  errorMsg?: string;
}

export function ActiveSession({ settings, sessionId, onEnd }: Props) {
  const [readings, setReadings] = useState<PendingReading[]>([]);
  const [modalOpen, setModalOpen] = useState(false);

  const nextSeq = readings.length === 0 ? 1 : Math.max(...readings.map(r => r.seq)) + 1;
  // readings is stored newest-first (persist prepends), so first hit = most recent.
  const lastBloodFlow = readings.find(r => r.blood_flow != null)?.blood_flow;

  async function persist(reading: Reading): Promise<void> {
    // Idempotent on reading_id: upsert the row instead of always prepending,
    // so a modal-level retry after a failed save updates in place.
    setReadings(rs => {
      const existing = rs.findIndex(r => r.reading_id === reading.reading_id);
      const next: PendingReading = { ...reading, status: 'pending' };
      if (existing >= 0) return rs.map((r, i) => i === existing ? next : r);
      return [next, ...rs];
    });
    try {
      await saveReading(settings, reading);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'saved' } : r));
    } catch (e) {
      const msg = e instanceof ApiError ? e.code : String(e);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'error', errorMsg: msg } : r));
      throw e;
    }
  }

  async function retry(reading: PendingReading) {
    setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'pending', errorMsg: undefined } : r));
    // Strip UI-only fields before sending over the wire.
    const { status: _s, errorMsg: _e, ...wire } = reading;
    void _s; void _e;
    try {
      await saveReading(settings, wire);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'saved' } : r));
    } catch (e) {
      const msg = e instanceof ApiError ? e.code : String(e);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'error', errorMsg: msg } : r));
    }
  }

  // Sort by seq desc — time is user-editable so seq is the stable order.
  const sorted = [...readings].sort((a, b) => b.seq - a.seq);

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold">Session {sessionId}</h1>
        <button type="button" onClick={onEnd} className="text-sm text-accent underline">End session</button>
      </header>

      <button
        type="button"
        onClick={() => setModalOpen(true)}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 text-lg"
      >
        + Add reading
      </button>

      <ul className="space-y-2">
        {sorted.length === 0 && <li className="text-slate-500 text-sm">No readings yet.</li>}
        {sorted.map(r => (
          <li key={r.reading_id} className="bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm">
            <div className="flex justify-between">
              <span className="font-mono text-slate-300">{r.time}</span>
              <span className={
                r.status === 'pending' ? 'text-slate-500' :
                r.status === 'error'   ? 'text-red-400'   :
                                         'text-emerald-400'
              }>
                {r.status === 'pending' ? 'saving…' : r.status === 'error' ? '⚠ error' : '✓'}
              </span>
            </div>
            <div className="text-slate-400">
              BP {r.bp_sys ?? '–'}/{r.bp_dia ?? '–'} · pulse {r.pulse ?? '–'} · BF {r.blood_flow ?? '–'} · VP {r.venous_pressure ?? '–'} · AP {r.arterial_pressure ?? '–'}
            </div>
            {r.note && <div className="text-slate-500 italic">{r.note}</div>}
            {r.status === 'error' && (
              <div className="text-red-400 text-xs mt-1">
                {r.errorMsg} <button type="button" className="underline ml-2" onClick={() => retry(r)}>Retry</button>
              </div>
            )}
          </li>
        ))}
      </ul>

      {modalOpen && (
        <AddReadingModal
          sessionId={sessionId}
          seq={nextSeq}
          defaultBloodFlow={lastBloodFlow}
          onSave={persist}
          onClose={() => setModalOpen(false)}
        />
      )}
    </div>
  );
}
