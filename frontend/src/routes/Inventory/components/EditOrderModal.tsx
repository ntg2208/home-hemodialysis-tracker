import { useState } from 'react';
import { X, Plus, Minus, Trash2 } from 'lucide-react';
import { ITEMS } from '../constants';
import type { Cycle } from '../schemas';

type Props = {
  cycle: Cycle;
  onSave: (order: Record<string, number>) => Promise<void>;
  onClose: () => void;
};

export function EditOrderModal({ cycle, onSave, onClose }: Props) {
  const nxstageItems = ITEMS.filter(i => i.section === 'nxstage');

  const [boxes, setBoxes] = useState<Record<string, number>>(() => {
    const init: Record<string, number> = {};
    for (const [code, qty] of Object.entries(cycle.order ?? {})) {
      const item = ITEMS.find(i => i.code === code);
      if (item && qty > 0) init[code] = Math.round(qty / item.boxSize);
    }
    return init;
  });
  const [addCode, setAddCode] = useState('');
  const [addQty, setAddQty] = useState('1');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const inOrder = new Set(Object.keys(boxes).filter(k => (boxes[k] ?? 0) > 0));
  const addableItems = nxstageItems.filter(i => !inOrder.has(i.code));
  const orderItems = nxstageItems.filter(i => (boxes[i.code] ?? 0) > 0);

  function handleAdd() {
    if (!addCode) return;
    const qty = parseInt(addQty, 10);
    if (isNaN(qty) || qty <= 0) return;
    setBoxes(b => ({ ...b, [addCode]: qty }));
    setAddCode('');
    setAddQty('1');
  }

  function removeItem(code: string) {
    setBoxes(b => { const next = { ...b }; delete next[code]; return next; });
  }

  async function handleSave() {
    setSaving(true);
    setError(null);
    try {
      const order: Record<string, number> = {};
      for (const [code, qty] of Object.entries(boxes)) {
        const item = ITEMS.find(i => i.code === code);
        if (item && qty > 0) order[code] = qty * item.boxSize;
      }
      await onSave(order);
      onClose();
    } catch {
      setError('Save failed');
    } finally {
      setSaving(false);
    }
  }

  function adjBtn(onClick: () => void, disabled: boolean, children: React.ReactNode) {
    return (
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        className="w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200 disabled:opacity-30 flex-shrink-0"
      >
        {children}
      </button>
    );
  }

  return (
    <div className="kb-overlay fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
      <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-4 pt-4 pb-3 flex-shrink-0">
          <span className="font-semibold text-slate-200">Edit order</span>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-slate-300">
            <X size={18} />
          </button>
        </div>

        <div className="overflow-y-auto flex-1 px-4 pb-4 space-y-3">
          {orderItems.length === 0 ? (
            <p className="text-sm text-slate-400 text-center py-2">No items — add one below.</p>
          ) : (
            <div className="space-y-2">
              {orderItems.map(item => {
                const qty = boxes[item.code] ?? 0;
                return (
                  <div key={item.code} className="flex items-center gap-2">
                    <div className="flex-1 min-w-0">
                      <span className="text-sm text-slate-200 truncate block">{item.label}</span>
                    </div>
                    <button
                      type="button"
                      onClick={() => removeItem(item.code)}
                      className="w-7 h-7 rounded-full border border-slate-700 flex items-center justify-center text-slate-600 hover:text-red-400 hover:border-red-400/50 flex-shrink-0"
                    >
                      <Trash2 size={11} />
                    </button>
                    {adjBtn(() => setBoxes(b => ({ ...b, [item.code]: Math.max(1, qty - 1) })), qty <= 1, <Minus size={12} />)}
                    <span className="text-sm font-semibold text-accent w-16 text-center">
                      {qty} {qty === 1 ? item.boxLabel : item.boxLabel + 's'}
                    </span>
                    {adjBtn(() => setBoxes(b => ({ ...b, [item.code]: qty + 1 })), false, <Plus size={12} />)}
                  </div>
                );
              })}
            </div>
          )}

          {addableItems.length > 0 && (
            <div className="border-t border-slate-800 pt-3">
              <p className="text-xs text-slate-500 mb-2">Add item</p>
              <div className="flex gap-2">
                <select
                  value={addCode}
                  onChange={e => setAddCode(e.target.value)}
                  className="flex-1 bg-panel border border-slate-600 rounded px-2 py-1.5 text-sm text-slate-200 min-w-0"
                >
                  <option value="">Select item…</option>
                  {addableItems.map(i => (
                    <option key={i.code} value={i.code}>{i.label}</option>
                  ))}
                </select>
                <input
                  type="number"
                  min="1"
                  inputMode="numeric"
                  value={addQty}
                  onChange={e => setAddQty(e.target.value)}
                  className="w-16 bg-panel border border-slate-600 rounded px-2 py-1.5 text-sm text-slate-200 text-right"
                />
                <button
                  type="button"
                  onClick={handleAdd}
                  disabled={!addCode}
                  className="w-9 h-9 rounded-lg bg-slate-700 border border-slate-600 flex items-center justify-center text-slate-300 hover:bg-slate-600 disabled:opacity-40 flex-shrink-0"
                >
                  <Plus size={16} />
                </button>
              </div>
            </div>
          )}

          {error && <p className="text-red-400 text-sm">{error}</p>}

          <button
            type="button"
            onClick={handleSave}
            disabled={saving || orderItems.length === 0}
            className="w-full bg-accent text-bg font-semibold rounded-lg py-2 disabled:opacity-40"
          >
            {saving ? 'Saving…' : 'Save order'}
          </button>
        </div>
      </div>
    </div>
  );
}
