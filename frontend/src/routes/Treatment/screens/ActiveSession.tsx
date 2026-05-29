import { useEffect, useRef, useState } from 'react';
import { Activity, AlertCircle, Check, Droplets, Heart, Loader2, Pencil, Plus, Scale, Square, Timer, X } from 'lucide-react';
import { ApiError, saveReading } from '../api';
import { AddReadingModal } from '../components/AddReadingModal';
import type { PendingReading, Reading, Session, Settings } from '../schemas';
import type { SessionConsumed } from '../storage';

const DEFAULT_TARGET_MIN = 255; // 4h 15m
const NOTIFY_AT_MINS = [120, 60, 5] as const;

interface Props {
  settings: Settings;
  session: Session;
  initialReadings?: PendingReading[];
  initialCountdownStartedAt?: number;
  initialTargetMin?: number;
  onReadingsChange?: (rs: PendingReading[]) => void;
  onCountdownChange?: (startedAt: number | null, targetMin: number) => void;
  onEnd: (consumed: Omit<SessionConsumed, 'heparinUsed'>) => void;
}

function formatRemaining(remainingMs: number): string {
  const overtime = remainingMs < 0;
  const abs = Math.abs(remainingMs);
  const h = Math.floor(abs / 3_600_000);
  const m = Math.floor((abs % 3_600_000) / 60_000);
  const s = Math.floor((abs % 60_000) / 1_000);
  return `${overtime ? '+' : ''}${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatTarget(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function ActiveSession({
  settings,
  session,
  initialReadings,
  initialCountdownStartedAt,
  initialTargetMin,
  onReadingsChange,
  onCountdownChange,
  onEnd,
}: Props) {
  const sessionId = session.session_id;
  const [readings, setReadings] = useState<PendingReading[]>(initialReadings ?? []);
  const [modalOpen, setModalOpen] = useState(false);
  const [needles, setNeedles] = useState(2);
  const [onOffPacks, setOnOffPacks] = useState(1);

  // Countdown
  const [targetMin, setTargetMin] = useState(initialTargetMin ?? DEFAULT_TARGET_MIN);
  const [countdownStartedAt, setCountdownStartedAt] = useState<number | null>(initialCountdownStartedAt ?? null);
  const [editingTarget, setEditingTarget] = useState(false);
  const [editHours, setEditHours] = useState(Math.floor((initialTargetMin ?? DEFAULT_TARGET_MIN) / 60));
  const [editMins, setEditMins] = useState((initialTargetMin ?? DEFAULT_TARGET_MIN) % 60);
  const [inAppAlert, setInAppAlert] = useState<string | null>(null);
  const [, forceUpdate] = useState(0);

  // Track which notification thresholds have already fired, pre-seeded on restore
  const notifiedRef = useRef<Set<number>>((() => {
    const s = new Set<number>();
    if (initialCountdownStartedAt) {
      const remaining = (initialTargetMin ?? DEFAULT_TARGET_MIN) * 60_000 - (Date.now() - initialCountdownStartedAt);
      for (const mins of NOTIFY_AT_MINS) {
        if (remaining <= mins * 60_000) s.add(mins);
      }
    }
    return s;
  })());

  // Tick every second while countdown is running
  useEffect(() => {
    if (!countdownStartedAt) return;
    const id = setInterval(() => {
      forceUpdate(n => n + 1);
      const remaining = targetMin * 60_000 - (Date.now() - countdownStartedAt);
      for (const mins of NOTIFY_AT_MINS) {
        if (remaining <= mins * 60_000 && !notifiedRef.current.has(mins)) {
          notifiedRef.current.add(mins);
          const label = mins === 120 ? '2 hours' : mins === 60 ? '1 hour' : '5 minutes';
          triggerAlert(`${label} remaining`);
        }
      }
    }, 1_000);
    return () => clearInterval(id);
  }, [countdownStartedAt, targetMin]);

  // Request notification permission when countdown first starts
  useEffect(() => {
    if (!countdownStartedAt) return;
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {});
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [!!countdownStartedAt]);

  function triggerAlert(message: string) {
    setInAppAlert(message);
    if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
    if ('Notification' in window && Notification.permission === 'granted') {
      new Notification('HD Session', { body: message });
    }
  }

  function startEditTarget() {
    setEditHours(Math.floor(targetMin / 60));
    setEditMins(targetMin % 60);
    setEditingTarget(true);
  }

  function commitTarget() {
    const total = editHours * 60 + editMins;
    if (total > 0) setTargetMin(total);
    setEditingTarget(false);
  }

  // Notify parent of countdown state changes for persistence
  const onCountdownChangeRef = useRef(onCountdownChange);
  onCountdownChangeRef.current = onCountdownChange;
  const prevCountdownKey = useRef<string>('');
  useEffect(() => {
    const key = `${countdownStartedAt}:${targetMin}`;
    if (key === prevCountdownKey.current) return;
    prevCountdownKey.current = key;
    onCountdownChangeRef.current?.(countdownStartedAt, targetMin);
  }, [countdownStartedAt, targetMin]);

  // Skip notifying on mount — the initial readings already came from the
  // parent's persisted state, echoing them back would be a no-op write.
  const firstRender = useRef(true);
  const onChangeRef = useRef(onReadingsChange);
  onChangeRef.current = onReadingsChange;
  useEffect(() => {
    if (firstRender.current) { firstRender.current = false; return; }
    onChangeRef.current?.(readings);
  }, [readings]);

  const nextSeq = readings.length === 0 ? 1 : Math.max(...readings.map(r => r.seq)) + 1;
  const lastBloodFlow = readings.find(r => r.blood_flow != null)?.blood_flow;

  async function persist(reading: Reading): Promise<void> {
    setReadings(rs => {
      const existing = rs.findIndex(r => r.reading_id === reading.reading_id);
      const next: PendingReading = { ...reading, status: 'pending' };
      if (existing >= 0) return rs.map((r, i) => i === existing ? next : r);
      return [next, ...rs];
    });
    if (countdownStartedAt === null) {
      setCountdownStartedAt(Date.now());
    }
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

  const sorted = [...readings].sort((a, b) => b.seq - a.seq);

  // Countdown display values
  const targetMs = targetMin * 60_000;
  const remainingMs = countdownStartedAt ? targetMs - (Date.now() - countdownStartedAt) : targetMs;
  const overtime = remainingMs < 0;
  const timerColor = !countdownStartedAt
    ? 'text-slate-500'
    : overtime
      ? 'text-red-400'
      : remainingMs <= 5 * 60_000
        ? 'text-red-400'
        : remainingMs <= 10 * 60_000
          ? 'text-amber-300'
          : 'text-emerald-400';

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      {/* In-app alert banner */}
      {inAppAlert && (
        <div className="fixed top-0 left-0 right-0 z-50 bg-amber-900/95 border-b border-amber-600 px-4 py-3 flex items-center justify-between">
          <span className="text-amber-200 text-sm font-semibold">{inAppAlert}</span>
          <button type="button" onClick={() => setInAppAlert(null)} className="text-amber-400 hover:text-amber-200 ml-4">
            <X size={16} />
          </button>
        </div>
      )}

      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold inline-flex items-center gap-2">
          <Activity size={20} className="text-accent" />
          Session <span className="font-mono text-base text-slate-300">{sessionId}</span>
        </h1>
        <button
          type="button"
          onClick={() => onEnd({ needles, onOffPacks, durationMin: countdownStartedAt ? Math.round((Date.now() - countdownStartedAt) / 60_000) : undefined })}
          className="text-sm text-accent inline-flex items-center gap-1"
        >
          <Square size={14} fill="currentColor" /> End
        </button>
      </header>

      <div className="bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-300 grid grid-cols-2 gap-x-4 gap-y-1">
        <div className="inline-flex items-center gap-2">
          <Scale size={14} className="text-slate-500" />
          Weight <span className="text-slate-100">{session.pre_weight ?? '–'} kg</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Droplets size={14} className="text-cyan-400" />
          UF goal <span className="text-slate-100">{session.uf_goal ?? '–'} L</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Heart size={14} className="text-rose-400" />
          BP <span className="text-slate-100">{session.pre_bp_sys ?? '–'}/{session.pre_bp_dia ?? '–'}</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Activity size={14} className="text-emerald-400" />
          Pulse <span className="text-slate-100">{session.pre_pulse ?? '–'}</span>
        </div>
      </div>

      {/* Countdown */}
      <div className="bg-panel border border-slate-700 rounded-lg px-3 py-2 flex items-center justify-between gap-3">
        <div className="inline-flex items-center gap-2">
          <Timer size={16} className={timerColor} />
          {countdownStartedAt ? (
            <span className={`font-mono text-xl font-semibold ${timerColor}`}>
              {formatRemaining(remainingMs)}
            </span>
          ) : (
            <span className="text-slate-500 text-sm">Waiting for first reading</span>
          )}
        </div>
        {editingTarget ? (
          <div className="inline-flex items-center gap-1">
            <input
              type="number"
              min="0"
              max="23"
              value={editHours}
              onChange={e => setEditHours(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-10 bg-bg border border-slate-600 rounded px-1 py-0.5 text-sm text-center text-slate-200"
            />
            <span className="text-slate-400 text-sm">h</span>
            <input
              type="number"
              min="0"
              max="59"
              value={editMins}
              onChange={e => setEditMins(Math.max(0, Math.min(59, parseInt(e.target.value, 10) || 0)))}
              className="w-10 bg-bg border border-slate-600 rounded px-1 py-0.5 text-sm text-center text-slate-200"
            />
            <span className="text-slate-400 text-sm">m</span>
            <button type="button" onClick={commitTarget} className="text-accent hover:opacity-80 p-1">
              <Check size={16} />
            </button>
            <button type="button" onClick={() => setEditingTarget(false)} className="text-slate-500 hover:text-slate-300 p-1">
              <X size={16} />
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={startEditTarget}
            className="inline-flex items-center gap-1.5 text-slate-400 hover:text-slate-200"
          >
            <span className="text-sm font-mono">{formatTarget(targetMin)}</span>
            <Pencil size={12} className="text-slate-600" />
          </button>
        )}
      </div>

      <button
        type="button"
        onClick={() => setModalOpen(true)}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 text-lg inline-flex items-center justify-center gap-2"
      >
        <Plus size={22} /> Add reading
      </button>

      {/* Consumed this session */}
      <div className="bg-panel border border-slate-700 rounded-lg px-3 py-2">
        <p className="text-xs text-slate-500 mb-2">Consumed this session</p>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs text-slate-400 block mb-1">Needles used</label>
            <input
              type="number"
              min="0"
              inputMode="numeric"
              value={needles}
              onChange={e => setNeedles(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-full bg-bg border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-center"
            />
          </div>
          <div>
            <label className="text-xs text-slate-400 block mb-1">On/Off packs</label>
            <input
              type="number"
              min="0"
              inputMode="numeric"
              value={onOffPacks}
              onChange={e => setOnOffPacks(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-full bg-bg border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-center"
            />
          </div>
        </div>
      </div>

      <ul className="space-y-2">
        {sorted.length === 0 && <li className="text-slate-500 text-sm">No readings yet.</li>}
        {sorted.map(r => (
          <li key={r.reading_id} className="bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm">
            <div className="flex justify-between">
              <span className="font-mono text-slate-300">{r.time}</span>
              <span className={
                'inline-flex items-center gap-1 ' + (
                  r.status === 'pending' ? 'text-slate-500' :
                  r.status === 'error'   ? 'text-red-400'   :
                                           'text-emerald-400'
                )
              }>
                {r.status === 'pending' ? <><Loader2 size={14} className="animate-spin" /> saving…</> :
                 r.status === 'error'   ? <><AlertCircle size={14} /> error</> :
                                          <Check size={14} />}
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
