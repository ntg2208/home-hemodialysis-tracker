import { useRef, useState } from 'react';
import { Minus, Plus } from 'lucide-react';
import { sessionsRemaining, stockStatus } from '../lib/stockCalc';
import type { ItemDef } from '../constants';

interface Props {
  item: ItemDef;
  qty: number;
  onAdjust: (delta: number) => Promise<void>;
}

const STATUS_COLOUR: Record<string, string> = {
  red: 'text-red-400',
  amber: 'text-amber-400',
  green: 'text-emerald-400',
};

const STATUS_DOT: Record<string, string> = {
  red: 'bg-red-500',
  amber: 'bg-amber-500',
  green: 'bg-emerald-500',
};

interface Toast {
  id: number;
  label: string;
  undoDelta: number;
}

export function StockItemRow({ item, qty, onAdjust }: Props) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  async function handleAdjust(delta: number) {
    const id = ++toastId.current;
    const label = `${delta > 0 ? '+' : ''}${delta} ${item.label}`;
    setToasts(ts => [...ts, { id, label, undoDelta: -delta }]);

    // Fire API immediately (optimistic — parent already updated qty)
    try {
      await onAdjust(delta);
    } catch {
      // If API fails, revert via undo
      setToasts(ts => ts.filter(t => t.id !== id));
      try { await onAdjust(-delta); } catch { /* best effort revert */ }
    }

    // Auto-dismiss after 5s
    setTimeout(() => setToasts(ts => ts.filter(t => t.id !== id)), 5000);
  }

  async function handleUndo(toast: Toast) {
    setToasts(ts => ts.filter(t => t.id !== toast.id));
    try { await onAdjust(toast.undoDelta); } catch { /* best effort */ }
  }

  const sr = sessionsRemaining(item.code, qty);
  const status = stockStatus(item.code, qty);

  return (
    <div className="relative">
      <div className="flex items-center gap-3 py-2">
        <span className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${STATUS_DOT[status]}`} />

        <span className="flex-1 text-sm">
          <span className="text-slate-200">{item.label}</span>
          <span className={`ml-2 text-xs ${STATUS_COLOUR[status]}`}>
            {qty} {item.unit}{qty !== 1 ? 's' : ''}
            {sr != null && <span className="text-slate-500 ml-1">~{sr} sess</span>}
          </span>
        </span>

        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => handleAdjust(-1)}
            disabled={qty <= 0}
            className="w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200 disabled:opacity-30"
            aria-label={`Use one ${item.label}`}
          >
            <Minus size={12} />
          </button>
          <button
            type="button"
            onClick={() => handleAdjust(1)}
            className="w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200"
            aria-label={`Add one ${item.label}`}
          >
            <Plus size={12} />
          </button>
        </div>
      </div>

      {toasts.map(t => (
        <div
          key={t.id}
          className="absolute right-0 -bottom-8 z-10 bg-slate-700 border border-slate-600 rounded text-xs px-3 py-1 flex items-center gap-3 shadow"
        >
          <span className="text-slate-300">{t.label}</span>
          <button
            type="button"
            onClick={() => handleUndo(t)}
            className="text-accent underline"
          >
            Undo
          </button>
        </div>
      ))}
    </div>
  );
}
