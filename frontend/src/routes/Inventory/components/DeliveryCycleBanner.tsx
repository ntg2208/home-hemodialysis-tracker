// frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx
import { CalendarDays, Package, Check } from 'lucide-react';
import type { Cycle } from '../schemas';

interface Props {
  cycle: Cycle | null;
  onSetupCycle: () => void;
  onOpenOrder: () => void;
  onViewOrder?: () => void;
}

function daysUntil(dateStr: string): number {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const target = new Date(dateStr);
  target.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

function fmt(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export function DeliveryCycleBanner({ cycle, onSetupCycle, onOpenOrder, onViewOrder }: Props) {
  if (!cycle) {
    return (
      <div className="bg-panel border border-slate-700 rounded-lg px-4 py-3 flex items-center justify-between">
        <span className="text-sm text-slate-400">No delivery cycle set up yet.</span>
        <button type="button" onClick={onSetupCycle} className="text-sm text-accent underline">
          Set call date
        </button>
      </div>
    );
  }

  const callDays = daysUntil(cycle.call_date);
  const deliveryDays = daysUntil(cycle.delivery_date);
  const orderPlaced = !!cycle.order_placed_at;
  // Show "View order" while order is placed and we're within delivery+1 window
  const showViewOrder = orderPlaced && onViewOrder && deliveryDays >= -1;

  // Delivery day or overdue
  if (deliveryDays <= 0 && orderPlaced) {
    const label = deliveryDays === 0 ? 'today' : `${Math.abs(deliveryDays)}d overdue`;
    return (
      <div className="bg-amber-900/30 border border-amber-700 rounded-lg px-4 py-3 space-y-2">
        <div className="flex items-center justify-between">
          <span className="inline-flex items-center gap-2 text-sm text-amber-300">
            <Package size={16} /> Delivery {label} · {fmt(cycle.delivery_date)}
          </span>
          <div className="flex items-center gap-3">
            {showViewOrder && (
              <button type="button" onClick={onViewOrder} className="text-xs text-slate-400 underline">
                View order
              </button>
            )}
            <button type="button" onClick={onOpenOrder} className="text-sm text-accent underline">
              Apply
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-panel border border-slate-700 rounded-lg px-4 py-3 flex items-center gap-4 text-sm">
      <span className={`inline-flex items-center gap-1.5 ${orderPlaced ? 'text-slate-500' : 'text-slate-200'}`}>
        <CalendarDays size={14} />
        {orderPlaced
          ? <><Check size={12} className="text-emerald-400" /> Called · {fmt(cycle.call_date)}</>
          : callDays <= 0
            ? <span className="text-amber-300">Call today · {fmt(cycle.call_date)}</span>
            : <>Call in {callDays}d · {fmt(cycle.call_date)}</>
        }
      </span>

      <span className="text-slate-600">→</span>

      <span className={`inline-flex items-center gap-1.5 ${orderPlaced ? 'text-slate-200' : 'text-slate-500'}`}>
        <Package size={14} />
        {orderPlaced
          ? <>Delivery in {deliveryDays}d · {fmt(cycle.delivery_date)}</>
          : <>{fmt(cycle.delivery_date)}</>
        }
      </span>

      {orderPlaced ? (
        <div className="ml-auto flex items-center gap-3">
          {showViewOrder && (
            <button type="button" onClick={onViewOrder} className="text-xs text-slate-400 underline">
              View order
            </button>
          )}
        </div>
      ) : (
        <button type="button" onClick={onOpenOrder} className="ml-auto text-xs text-accent underline">
          Place order
        </button>
      )}
    </div>
  );
}
