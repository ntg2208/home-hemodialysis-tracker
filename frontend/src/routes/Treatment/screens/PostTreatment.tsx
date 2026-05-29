import { useEffect, useState } from 'react';
import { CheckCircle2 } from 'lucide-react';
import { ApiError, updateSession } from '../api';
import { NumberField } from '../components/NumberField';
import { SaveButton } from '../components/SaveButton';
import { cloudGet } from '../../../api/cloudRun';
import { logEvent } from '../../Inventory/api';
import { SESSION_FIXED_DELTAS } from '../../Inventory/constants';
import type { Session, Settings } from '../schemas';
import type { AuthSettings } from '../../../auth/storage';
import type { SessionConsumed } from '../storage';

interface Props {
  settings: Settings;
  auth: AuthSettings | null;
  session: Session;
  consumed: SessionConsumed;
  onSaved: () => void;
}

interface FormState {
  post_weight?: number;
  post_bp_sys?: number;
  post_bp_dia?: number;
  post_pulse?: number;
  duration_min?: number;
  dialysate_volume?: number;
  total_uf?: number;
  blood_processed?: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

// 4:15 = 4*60 + 15 = 255 minutes
const DEFAULT_DURATION_MIN = 255;
const DEFAULT_DIALYSATE_VOLUME = 49;

export function PostTreatment({ settings, auth, session, consumed, onSaved }: Props) {
  const sessionId = session.session_id;
  const [form, setForm] = useState<FormState>({
    duration_min: consumed.durationMin ?? DEFAULT_DURATION_MIN,
    dialysate_volume: DEFAULT_DIALYSATE_VOLUME,
  });
  const [totalUfTouched, setTotalUfTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [epoUsed, setEpoUsed] = useState(true);
  const [epoStock, setEpoStock] = useState<number | null>(null);

  useEffect(() => {
    if (!auth) return;
    cloudGet<{ stock: Record<string, number> }>(auth, '/api/inventory')
      .then(data => setEpoStock(data.stock['epo'] ?? 0))
      .catch(() => {});
  }, [auth]);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  // total_uf = pre_weight - post_weight; autofill while the user hasn't manually edited it.
  const derivedTotalUf =
    session.pre_weight != null && form.post_weight != null
      ? round2(session.pre_weight - form.post_weight)
      : undefined;
  const effectiveTotalUf = totalUfTouched ? form.total_uf : derivedTotalUf;

  const ready = form.post_weight != null && form.post_bp_sys != null && form.post_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    try {
      await updateSession(settings, {
        session_id: sessionId,
        ...form,
        total_uf: effectiveTotalUf,
      });

      if (auth) {
        const deltas: Record<string, number> = {
          ...SESSION_FIXED_DELTAS,
          'P00012326': -consumed.needles,
          'UK00000774': -consumed.onOffPacks,
        };
        if (consumed.heparinUsed) deltas['heparin'] = -1;
        if (epoUsed) deltas['epo'] = -1;
        logEvent(auth, 'session', deltas).catch(() => {});
      }

      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-bold inline-flex items-center gap-2">
        <CheckCircle2 size={20} className="text-accent" /> Post-treatment
      </h1>
      <p className="text-sm text-slate-500 font-mono">{sessionId}</p>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Blood processed (L)" value={form.blood_processed} onChange={v => update('blood_processed', v)} />
        <NumberField label="BP sys" value={form.post_bp_sys} onChange={v => update('post_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.post_bp_dia} onChange={v => update('post_bp_dia', v)} step="1" required />
        <NumberField label="Pulse" value={form.post_pulse} onChange={v => update('post_pulse', v)} step="1" />
        <NumberField label="Weight (kg)" value={form.post_weight} onChange={v => update('post_weight', v)} required />
        <NumberField label="Duration (min)" value={form.duration_min} onChange={v => update('duration_min', v)} step="1" />
        <NumberField label="Dialysate vol (L)" value={form.dialysate_volume} onChange={v => update('dialysate_volume', v)} />
        <NumberField
          label="Total UF (L)"
          value={effectiveTotalUf}
          onChange={v => { setTotalUfTouched(v != null); update('total_uf', v); }}
        />
      </div>

      <div className="flex items-center justify-between bg-panel border border-slate-700 rounded-lg px-3 py-2">
        <div>
          <span className="text-sm text-slate-200">EPO</span>
          {epoStock !== null && (
            <span className="ml-2 text-xs text-slate-500">{epoStock} remaining</span>
          )}
        </div>
        <button
          type="button"
          onClick={() => setEpoUsed(e => !e)}
          className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
            epoUsed
              ? 'bg-accent text-bg'
              : 'bg-slate-700 text-slate-400'
          }`}
        >
          {epoUsed ? 'Used' : 'Not used'}
        </button>
      </div>

      <SaveButton
        saving={saving}
        error={error}
        onClick={submit}
        disabled={!ready}
        icon={<CheckCircle2 size={20} />}
      >
        Finish session
      </SaveButton>
    </div>
  );
}
