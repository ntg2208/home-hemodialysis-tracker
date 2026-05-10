import { useState } from 'react';
import { ApiError, updateSession } from '../api';
import { NumberField } from '../components/NumberField';
import { SaveButton } from '../components/SaveButton';
import type { Settings } from '../schemas';

interface Props {
  settings: Settings;
  sessionId: string;
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

export function PostTreatment({ settings, sessionId, onSaved }: Props) {
  const [form, setForm] = useState<FormState>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  const ready = form.post_weight != null && form.post_bp_sys != null && form.post_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    try {
      await updateSession(settings, { session_id: sessionId, ...form });
      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-bold">Post-treatment</h1>
      <p className="text-sm text-slate-500 font-mono">{sessionId}</p>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Weight (kg)" value={form.post_weight} onChange={v => update('post_weight', v)} required />
        <NumberField label="Pulse" value={form.post_pulse} onChange={v => update('post_pulse', v)} step="1" />
        <NumberField label="BP sys" value={form.post_bp_sys} onChange={v => update('post_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.post_bp_dia} onChange={v => update('post_bp_dia', v)} step="1" required />
        <NumberField label="Duration (min)" value={form.duration_min} onChange={v => update('duration_min', v)} step="1" />
        <NumberField label="Dialysate vol (L)" value={form.dialysate_volume} onChange={v => update('dialysate_volume', v)} />
        <NumberField label="Total UF (L)" value={form.total_uf} onChange={v => update('total_uf', v)} />
        <NumberField label="Blood processed (L)" value={form.blood_processed} onChange={v => update('blood_processed', v)} />
      </div>

      <SaveButton saving={saving} error={error} onClick={submit} disabled={!ready}>
        Finish session
      </SaveButton>
    </div>
  );
}
