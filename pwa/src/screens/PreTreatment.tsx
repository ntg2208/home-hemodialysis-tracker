import { useEffect, useState } from 'react';
import { ClipboardList, Play, X } from 'lucide-react';
import { ApiError, saveSession } from '../api';
import { getDriedWeight, getLastSession, saveLastSession } from '../storage';
import { nextSessionId, todayIso } from '../sessionId';
import { NumberField } from '../components/NumberField';
import { SaveButton } from '../components/SaveButton';
import type { Session, Settings } from '../schemas';

interface Props {
  settings: Settings;
  existingIds: string[];
  onSaved: (session: Session) => void;
  onCancel: () => void;
}

interface FormState {
  pre_weight?: number;
  uf_goal?: number;
  uf_rate?: number;
  pre_bp_sys?: number;
  pre_bp_dia?: number;
  pre_pulse?: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export function PreTreatment({ settings, existingIds, onSaved, onCancel }: Props) {
  const [form, setForm] = useState<FormState>({});
  const [goalTouched, setGoalTouched] = useState(false);
  const [rateTouched, setRateTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [driedWeight, setDriedWeight] = useState<number | null>(null);

  useEffect(() => {
    // Last-session prefill is no longer used for uf_goal / uf_rate —
    // those are derived from pre_weight via the formula below.
    getLastSession().catch(() => {});
    getDriedWeight().then(setDriedWeight).catch(() => setDriedWeight(59));
  }, []);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  // Derived defaults: uf_goal = pre_weight - dried_weight;
  // uf_rate = uf_goal / 0.004. Only used when the user hasn't manually
  // edited that field. Block derivation until dried weight has loaded so
  // the formula doesn't briefly use a stale constant.
  const derivedGoal =
    form.pre_weight != null && driedWeight != null
      ? round2(form.pre_weight - driedWeight)
      : undefined;
  const effectiveGoal = goalTouched ? form.uf_goal : derivedGoal;
  const derivedRate =
    effectiveGoal != null ? round2(effectiveGoal / 0.004) : undefined;
  const effectiveRate = rateTouched ? form.uf_rate : derivedRate;

  const ready = form.pre_weight != null && effectiveGoal != null && form.pre_bp_sys != null && form.pre_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    const date = todayIso();
    const session_id = nextSessionId(date, existingIds);
    const session: Session = {
      session_id,
      date,
      ...form,
      uf_goal: effectiveGoal,
      uf_rate: effectiveRate,
    };
    try {
      await saveSession(settings, session);
      // Local cache is a UX nicety; don't fail the submit if IDB write fails.
      saveLastSession(session).catch(() => {});
      onSaved(session);
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold inline-flex items-center gap-2">
          <ClipboardList size={20} className="text-accent" /> Pre-treatment
        </h1>
        <button
          type="button"
          onClick={onCancel}
          aria-label="Cancel"
          className="text-slate-500 hover:text-slate-300 p-1"
        >
          <X size={20} />
        </button>
      </header>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Weight (kg)" value={form.pre_weight} onChange={v => update('pre_weight', v)} required />
        <NumberField
          label="UF goal (L)"
          value={effectiveGoal}
          onChange={v => { setGoalTouched(v != null); update('uf_goal', v); }}
          required
        />
        <NumberField
          label="UF rate"
          value={effectiveRate}
          onChange={v => { setRateTouched(v != null); update('uf_rate', v); }}
        />
        <NumberField label="BP sys" value={form.pre_bp_sys} onChange={v => update('pre_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.pre_bp_dia} onChange={v => update('pre_bp_dia', v)} step="1" required />
        <NumberField label="Pulse" value={form.pre_pulse} onChange={v => update('pre_pulse', v)} step="1" />
      </div>

      <SaveButton
        saving={saving}
        error={error}
        onClick={submit}
        disabled={!ready}
        icon={<Play size={20} fill="currentColor" />}
      >
        Start session
      </SaveButton>
    </div>
  );
}
