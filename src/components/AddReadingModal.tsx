import { useState } from 'react';
import { NumberField } from './NumberField';
import { SaveButton } from './SaveButton';
import type { Reading } from '../schemas';
import { nowHHMM } from '../sessionId';

interface Props {
  sessionId: string;
  seq: number;
  defaultBloodFlow?: number;
  onSave: (reading: Reading) => Promise<void>;
  onClose: () => void;
}

interface FormState {
  time: string;
  bp_sys?: number;
  bp_dia?: number;
  pulse?: number;
  blood_flow?: number;
  venous_pressure?: number;
  arterial_pressure?: number;
  note?: string;
}

export function AddReadingModal({ sessionId, seq, defaultBloodFlow, onSave, onClose }: Props) {
  const [form, setForm] = useState<FormState>({ time: nowHHMM(), blood_flow: defaultBloodFlow });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  async function submit() {
    setError(null);
    setSaving(true);
    const reading: Reading = {
      reading_id: `${sessionId}-r${seq}`,
      session_id: sessionId,
      seq,
      ...form,
    };
    try {
      await onSave(reading);
      onClose();
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-end sm:items-center justify-center z-50">
      <div className="bg-bg border border-slate-700 rounded-t-2xl sm:rounded-2xl p-4 w-full max-w-md max-h-[90vh] overflow-y-auto space-y-3">
        <header className="flex items-center justify-between">
          <h2 className="text-lg font-bold">Reading #{seq}</h2>
          <button type="button" onClick={onClose} className="text-slate-400 text-sm underline">Close</button>
        </header>

        <label className="block">
          <span className="block text-sm text-slate-400 mb-1">Time</span>
          <input
            type="time"
            value={form.time}
            onChange={e => update('time', e.target.value)}
            className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-lg focus:border-accent focus:outline-none"
          />
        </label>

        <div className="grid grid-cols-2 gap-3">
          <NumberField label="BP sys" value={form.bp_sys} onChange={v => update('bp_sys', v)} step="1" />
          <NumberField label="BP dia" value={form.bp_dia} onChange={v => update('bp_dia', v)} step="1" />
          <NumberField label="Pulse" value={form.pulse} onChange={v => update('pulse', v)} step="1" />
          <NumberField label="Blood flow" value={form.blood_flow} onChange={v => update('blood_flow', v)} step="1" />
          <NumberField label="VP" value={form.venous_pressure} onChange={v => update('venous_pressure', v)} step="1" />
          <NumberField label="AP" value={form.arterial_pressure} onChange={v => update('arterial_pressure', v)} step="1" />
        </div>

        <label className="block">
          <span className="block text-sm text-slate-400 mb-1">Note</span>
          <input
            type="text"
            value={form.note ?? ''}
            onChange={e => update('note', e.target.value || undefined)}
            className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-base focus:border-accent focus:outline-none"
          />
        </label>

        <SaveButton saving={saving} error={error} onClick={submit}>Save reading</SaveButton>
      </div>
    </div>
  );
}
