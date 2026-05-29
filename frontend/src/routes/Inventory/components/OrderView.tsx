import { useState } from 'react';
import { X, Copy, Check, Minus, Plus } from 'lucide-react';
import { ITEMS } from '../constants';
import { orderBoxes } from '../lib/stockCalc';

interface Props {
  stock: Record<string, number>;
  callDate: string;
  cycleOrder?: Record<string, number>;
  onStockCount: (deltas: Record<string, number>) => Promise<void>;
  onConfirmOrder: (callDate: string, order: Record<string, number>) => Promise<void>;
  onApplyDelivery: (adjustments?: Record<string, number>) => Promise<void>;
  mode: 'order' | 'delivery';
  onClose: () => void;
}

type Step = 'count' | 'order_list' | 'confirm_delivery';

export function OrderView({ stock, callDate, cycleOrder, onStockCount, onConfirmOrder, onApplyDelivery, mode, onClose }: Props) {
  const [step, setStep] = useState<Step>(mode === 'delivery' ? 'confirm_delivery' : 'count');
  const [counts, setCounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(ITEMS.filter(i => i.section === 'nxstage').map(i => [i.code, String(stock[i.code] ?? 0)]))
  );
  // order_list: box counts per item (set when advancing from stock count step)
  const [orderCounts, setOrderCounts] = useState<Record<string, number>>({});
  // confirm_delivery: unit counts per item (initialized from cycleOrder)
  const [deliveryCounts, setDeliveryCounts] = useState<Record<string, number>>(() =>
    Object.fromEntries(
      ITEMS.filter(i => i.section === 'nxstage' && (cycleOrder?.[i.code] ?? 0) > 0)
        .map(i => [i.code, cycleOrder?.[i.code] ?? 0])
    )
  );
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
      // Initialise order box counts from calculated values
      const initial: Record<string, number> = {};
      for (const i of ITEMS.filter(x => x.section === 'nxstage')) {
        const current = parseInt(counts[i.code] ?? '0', 10) || 0;
        const boxes = orderBoxes(i.code, current);
        if (boxes > 0) initial[i.code] = boxes;
      }
      setOrderCounts(initial);
      setStep('order_list');
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Items shown in order list: those with a box count > 0
  const orderListItems = ITEMS.filter(i => i.section === 'nxstage' && (orderCounts[i.code] ?? 0) > 0)
    .map(i => ({ item: i, current: parseInt(counts[i.code] ?? '0', 10) || 0, boxes: orderCounts[i.code] ?? 0 }));

  // Step 2: confirm the order
  async function handleConfirmOrder() {
    setSaving(true); setError(null);
    try {
      const order: Record<string, number> = {};
      for (const { item, boxes } of orderListItems) order[item.code] = boxes * item.boxSize;
      await onConfirmOrder(callDate, order);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Copy order list to clipboard
  function copyToClipboard() {
    const lines = orderListItems.map(({ item, boxes }) =>
      `${item.label}: ${boxes} ${boxes === 1 ? item.boxLabel : item.boxLabel + 's'}`
    );
    navigator.clipboard.writeText(lines.join('\n')).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  // Delivery mode: apply delivery using current deliveryCounts
  async function handleApplyDelivery() {
    setSaving(true); setError(null);
    try {
      const adj: Record<string, number> = {};
      for (const [code, qty] of Object.entries(deliveryCounts)) {
        if (qty >= 0) adj[code] = qty;
      }
      await onApplyDelivery(Object.keys(adj).length > 0 ? adj : undefined);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  function adjBtn(className: string, children: React.ReactNode, onClick: () => void, disabled?: boolean) {
    return (
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        className={`w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200 disabled:opacity-30 flex-shrink-0 ${className}`}
      >
        {children}
      </button>
    );
  }

  return (
    <div className="kb-overlay fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
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
              {orderListItems.length === 0 ? (
                <p className="text-sm text-slate-400 text-center py-4">Stock is sufficient — nothing to order.</p>
              ) : (
                <div className="space-y-2">
                  {orderListItems.map(({ item, current, boxes }) => (
                    <div key={item.code} className="flex items-center gap-2">
                      <div className="flex-1 min-w-0">
                        <span className="text-sm text-slate-200 truncate block">{item.label}</span>
                        <span className="text-xs text-slate-500">have {current}</span>
                      </div>
                      {adjBtn('', <Minus size={12} />, () => setOrderCounts(o => ({ ...o, [item.code]: Math.max(0, (o[item.code] ?? boxes) - 1) })), (orderCounts[item.code] ?? boxes) <= 0)}
                      <span className="text-sm font-semibold text-accent w-16 text-center">
                        {orderCounts[item.code] ?? boxes} {(orderCounts[item.code] ?? boxes) === 1 ? item.boxLabel : item.boxLabel + 's'}
                      </span>
                      {adjBtn('', <Plus size={12} />, () => setOrderCounts(o => ({ ...o, [item.code]: (o[item.code] ?? boxes) + 1 })))}
                    </div>
                  ))}
                </div>
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
                  disabled={saving || orderListItems.length === 0}
                  className="flex-1 bg-accent text-bg font-semibold rounded-lg py-2 text-sm disabled:opacity-40"
                >
                  {saving ? 'Saving…' : 'Confirm order'}
                </button>
              </div>
            </>
          )}

          {step === 'confirm_delivery' && (
            <>
              <p className="text-xs text-slate-500">Adjust quantities if anything arrived differently from what was ordered.</p>
              {Object.keys(deliveryCounts).length === 0 ? (
                <p className="text-sm text-slate-400 text-center py-4">No order on record — use Log event → Manual use to adjust stock.</p>
              ) : (
                <div className="space-y-2">
                  {ITEMS.filter(i => i.section === 'nxstage' && deliveryCounts[i.code] !== undefined).map(i => (
                    <div key={i.code} className="flex items-center gap-2">
                      <span className="flex-1 text-sm text-slate-200 truncate">{i.label}</span>
                      {adjBtn('', <Minus size={12} />, () => setDeliveryCounts(d => ({ ...d, [i.code]: Math.max(0, (d[i.code] ?? 0) - 1) })), (deliveryCounts[i.code] ?? 0) <= 0)}
                      <span className="text-sm font-semibold text-accent w-14 text-center">
                        {deliveryCounts[i.code] ?? 0} {i.unit}
                      </span>
                      {adjBtn('', <Plus size={12} />, () => setDeliveryCounts(d => ({ ...d, [i.code]: (d[i.code] ?? 0) + 1 })))}
                    </div>
                  ))}
                </div>
              )}
              <button
                type="button"
                onClick={handleApplyDelivery}
                disabled={saving || Object.keys(deliveryCounts).length === 0}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2 disabled:opacity-40"
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
