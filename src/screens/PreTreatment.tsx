import { useEffect, useState } from 'react';
import { ApiError, saveSession } from '../api';
import { getLastSession, saveLastSession } from '../storage';
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

export function PreTreatment({ settings, existingIds, onSaved, onCancel }: Props) {
  const [form, setForm] = useState<FormState>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getLastSession()
      .then(last => {
        if (last) setForm(f => ({ ...f, uf_goal: f.uf_goal ?? last.uf_goal, uf_rate: f.uf_rate ?? last.uf_rate }));
      })
      .catch(() => {});
  }, []);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  const ready = form.pre_weight != null && form.uf_goal != null && form.pre_bp_sys != null && form.pre_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    const date = todayIso();
    const session_id = nextSessionId(date, existingIds);
    const session: Session = { session_id, date, ...form };
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
        <h1 className="text-xl font-bold">Pre-treatment</h1>
        <button type="button" onClick={onCancel} className="text-sm text-slate-400 underline">Cancel</button>
      </header>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Weight (kg)" value={form.pre_weight} onChange={v => update('pre_weight', v)} required />
        <NumberField label="UF goal (L)" value={form.uf_goal} onChange={v => update('uf_goal', v)} required />
        <NumberField label="UF rate (L/h)" value={form.uf_rate} onChange={v => update('uf_rate', v)} />
        <NumberField label="Pulse" value={form.pre_pulse} onChange={v => update('pre_pulse', v)} step="1" />
        <NumberField label="BP sys" value={form.pre_bp_sys} onChange={v => update('pre_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.pre_bp_dia} onChange={v => update('pre_bp_dia', v)} step="1" required />
      </div>

      <SaveButton saving={saving} error={error} onClick={submit} disabled={!ready}>
        Start session
      </SaveButton>
    </div>
  );
}
