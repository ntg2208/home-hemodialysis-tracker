import { useState } from 'react';
import { X, Copy, Check } from 'lucide-react';
import { ITEMS } from '../constants';
import { orderBoxes, orderUnits } from '../lib/stockCalc';

interface Props {
  stock: Record<string, number>;
  callDate: string;
  onStockCount: (deltas: Record<string, number>) => Promise<void>;
  onConfirmOrder: (callDate: string, order: Record<string, number>) => Promise<void>;
  onApplyDelivery: (adjustments?: Record<string, number>) => Promise<void>;
  mode: 'order' | 'delivery';
  onClose: () => void;
}

type Step = 'count' | 'order_list' | 'confirm_delivery';

export function OrderView({ stock, callDate, onStockCount, onConfirmOrder, onApplyDelivery, mode, onClose }: Props) {
  const [step, setStep] = useState<Step>(mode === 'delivery' ? 'confirm_delivery' : 'count');
  const [counts, setCounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(ITEMS.filter(i => i.section === 'nxstage').map(i => [i.code, String(stock[i.code] ?? 0)]))
  );
  const [adjustments, setAdjustments] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  // Step 1: save stock count, advance to order list
  async function handleCountSubmit() {
    setSaving(true); setError(null);
    try {
      const deltas: Record<string, number> = {};
      for (const [code, val] of Object.entries(counts)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) deltas[code] = n;
      }
      await onStockCount(deltas);
      setStep('order_list');
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Computed order using the entered counts as current stock
  const orderedItems = ITEMS.filter(i => i.section === 'nxstage').map(i => {
    const current = parseInt(counts[i.code] ?? '0', 10) || 0;
    const boxes = orderBoxes(i.code, current);
    const units = orderUnits(i.code, current);
    return { item: i, current, boxes, units };
  }).filter(r => r.boxes > 0);

  // Step 2: confirm the order
  async function handleConfirmOrder() {
    setSaving(true); setError(null);
    try {
      const order: Record<string, number> = {};
      for (const { item, units } of orderedItems) order[item.code] = units;
      await onConfirmOrder(callDate, order);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Copy order list to clipboard
  function copyToClipboard() {
    const lines = orderedItems.map(({ item, boxes }) =>
      `${item.label}: ${boxes} ${boxes === 1 ? item.boxLabel : item.boxLabel + 's'}`
    );
    navigator.clipboard.writeText(lines.join('\n')).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  // Delivery mode: show adjusted quantities, confirm apply
  async function handleApplyDelivery() {
    setSaving(true); setError(null);
    try {
      const adj: Record<string, number> = {};
      for (const [code, val] of Object.entries(adjustments)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) adj[code] = n;
      }
      await onApplyDelivery(Object.keys(adj).length > 0 ? adj : undefined);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
      <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-4 pt-4 pb-3 flex-shrink-0">
          <span className="font-semibold text-slate-200">
            {step === 'count' ? 'Step 1: Stock count' :
             step === 'order_list' ? 'Step 2: Order list' :
             'Apply delivery'}
          </span>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-slate-300">
            <X size={18} />
          </button>
        </div>

        <div className="overflow-y-auto flex-1 px-4 pb-4 space-y-3">
          {step === 'count' && (
            <>
              <p className="text-xs text-slate-500">Count what you physically have. This resets the running estimate before calculating the order.</p>
              {ITEMS.filter(i => i.section === 'nxstage').map(i => (
                <div key={i.code} className="flex items-center gap-3">
                  <span className="flex-1 text-sm text-slate-300 truncate">{i.label}</span>
                  <span className="text-xs text-slate-500">{i.unit}s</span>
                  <input
                    type="number"
                    min="0"
                    inputMode="numeric"
                    value={counts[i.code] ?? '0'}
                    onChange={e => setCounts(c => ({ ...c, [i.code]: e.target.value }))}
                    className="w-20 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right"
                  />
                </div>
              ))}
              <button
                type="button"
                onClick={handleCountSubmit}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Next: calculate order →'}
              </button>
            </>
          )}

          {step === 'order_list' && (
            <>
              {orderedItems.length === 0 ? (
                <p className="text-sm text-slate-400 text-center py-4">Stock is sufficient — nothing to order.</p>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-xs text-slate-500 uppercase">
                      <th className="text-left py-1">Item</th>
                      <th className="text-right py-1">Have</th>
                      <th className="text-right py-1">Order</th>
                    </tr>
                  </thead>
                  <tbody>
                    {orderedItems.map(({ item, current, boxes }) => (
                      <tr key={item.code} className="border-t border-slate-800 text-slate-300">
                        <td className="py-1.5">{item.label}</td>
                        <td className="text-right text-slate-500">{current}</td>
                        <td className="text-right font-semibold text-accent">
                          {boxes} {boxes === 1 ? item.boxLabel : item.boxLabel + 's'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={copyToClipboard}
                  className="flex-1 border border-slate-600 text-slate-300 rounded-lg py-2 text-sm inline-flex items-center justify-center gap-2"
                >
                  {copied ? <><Check size={14} /> Copied</> : <><Copy size={14} /> Copy list</>}
                </button>
                <button
                  type="button"
                  onClick={handleConfirmOrder}
                  disabled={saving}
                  className="flex-1 bg-accent text-bg font-semibold rounded-lg py-2 text-sm"
                >
                  {saving ? 'Saving…' : 'Confirm order'}
                </button>
              </div>
            </>
          )}

          {step === 'confirm_delivery' && (
            <>
              <p className="text-xs text-slate-500">Edit quantities if anything arrived differently. Leave blank to use the ordered amounts.</p>
              {ITEMS.filter(i => i.section === 'nxstage' && stock[i.code] !== undefined).map(i => (
                <div key={i.code} className="flex items-center gap-3">
                  <span className="flex-1 text-sm text-slate-300 truncate">{i.label}</span>
                  <input
                    type="number"
                    min="0"
                    inputMode="numeric"
                    value={adjustments[i.code] ?? ''}
                    placeholder="as ordered"
                    onChange={e => setAdjustments(a => ({ ...a, [i.code]: e.target.value }))}
                    className="w-24 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right placeholder:text-slate-600"
                  />
                </div>
              ))}
              <button
                type="button"
                onClick={handleApplyDelivery}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Applying…' : 'Apply delivery'}
              </button>
            </>
          )}

          {error && <p className="text-red-400 text-sm">{error}</p>}
        </div>
      </div>
    </div>
  );
}
