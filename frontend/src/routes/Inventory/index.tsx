// frontend/src/routes/Inventory/index.tsx
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, X } from 'lucide-react';
import { getAuth, type AuthSettings } from '../../auth/storage';
import { fetchInventory, logEvent, confirmOrder, applyDelivery, initCycle, setPakInstall, fetchDeliveries } from './api';
import type { DeliveryEvent } from './schemas';
import { ITEMS } from './constants';
import { sortStock } from './lib/stockCalc';
import { DeliveryCycleBanner } from './components/DeliveryCycleBanner';
import { StockItemRow } from './components/StockItemRow';
import { LogEventModal } from './components/LogEventModal';
import { OrderView } from './components/OrderView';
import type { Cycle } from './schemas';

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; stock: Record<string, number>; cycle: Cycle | null; pakInstalledAt: string | null; pakSessions: number };

export default function Inventory() {
  const navigate = useNavigate();
  const [auth, setAuth] = useState<AuthSettings | null>(null);
  const [state, setState] = useState<State>({ status: 'loading' });
  const [modal, setModal] = useState<'log' | 'order' | 'delivery' | 'setup' | 'order_summary' | 'history' | null>(null);
  const [deliveryHistory, setDeliveryHistory] = useState<DeliveryEvent[] | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [setupDate, setSetupDate] = useState('');
  const [setupSaving, setSetupSaving] = useState(false);
  const [setupError, setSetupError] = useState<string | null>(null);

  // Initial load
  useEffect(() => {
    getAuth().then(a => {
      if (!a) { navigate('/setup', { replace: true }); return; }
      setAuth(a);
      return fetchInventory(a).then(data => {
        setState({ status: 'ready', stock: data.stock, cycle: data.cycle, pakInstalledAt: data.pak_installed_at, pakSessions: data.pak_sessions });
        // Auto-apply delivery if due
        if (data.cycle?.order_placed_at && !data.cycle.delivery_applied_at) {
          const today = new Date().toISOString().slice(0, 10);
          if (data.cycle.delivery_date <= today) {
            applyDelivery(a).then(() =>
              fetchInventory(a).then(d =>
                setState({ status: 'ready', stock: d.stock, cycle: d.cycle, pakInstalledAt: d.pak_installed_at, pakSessions: d.pak_sessions })
              )
            ).catch(() => {});
          }
        }
      });
    }).catch(err => setState({ status: 'error', message: String(err) }));
  }, [navigate]);

  async function handleAdjust(code: string, delta: number) {
    if (!auth || state.status !== 'ready') return;
    setState(s => s.status !== 'ready' ? s : {
      ...s,
      stock: { ...s.stock, [code]: (s.stock[code] ?? 0) + delta },
    });
    await logEvent(auth, 'manual', { [code]: delta });
  }

  async function handleLogEvent(
    type: 'manual' | 'stock_count',
    deltas: Record<string, number>,
    note?: string,
  ) {
    if (!auth || state.status !== 'ready') return;
    if (type === 'stock_count') {
      setState(s => s.status !== 'ready' ? s : { ...s, stock: { ...s.stock, ...deltas } });
    } else {
      const next = { ...(state.stock) };
      for (const [code, delta] of Object.entries(deltas)) next[code] = (next[code] ?? 0) + delta;
      setState(s => s.status !== 'ready' ? s : { ...s, stock: next });
    }
    await logEvent(auth, type, deltas, note);
    // Refresh to get server-authoritative state
    const fresh = await fetchInventory(auth);
    setState(s => s.status !== 'ready' ? s : { ...s, stock: fresh.stock });
  }

  async function handleStockCount(deltas: Record<string, number>) {
    await handleLogEvent('stock_count', deltas, 'monthly stock count');
  }

  async function handleConfirmOrder(callDate: string, order: Record<string, number>) {
    if (!auth) return;
    await confirmOrder(auth, callDate, order);
    const fresh = await fetchInventory(auth);
    setState(s => s.status !== 'ready' ? s : { ...s, cycle: fresh.cycle });
  }

  async function handleApplyDelivery(adjustments?: Record<string, number>) {
    if (!auth) return;
    await applyDelivery(auth, adjustments);
    const fresh = await fetchInventory(auth);
    setState({ status: 'ready', stock: fresh.stock, cycle: fresh.cycle, pakInstalledAt: fresh.pak_installed_at, pakSessions: fresh.pak_sessions });
  }

  async function handleOpenHistory() {
    if (!auth) return;
    setModal('history');
    if (deliveryHistory !== null) return;
    setHistoryLoading(true);
    try {
      const data = await fetchDeliveries(auth);
      setDeliveryHistory(data.deliveries);
    } catch { setDeliveryHistory([]); }
    finally { setHistoryLoading(false); }
  }

  async function handleSetPakInstall(installedAt: string) {
    if (!auth) return;
    await setPakInstall(auth, installedAt);
    const fresh = await fetchInventory(auth);
    setState(s => s.status !== 'ready' ? s : { ...s, pakInstalledAt: fresh.pak_installed_at, pakSessions: fresh.pak_sessions });
  }

  async function handleSetupCycle() {
    if (!auth || !setupDate) return;
    setSetupSaving(true);
    setSetupError(null);
    try {
      await initCycle(auth, setupDate);
      const fresh = await fetchInventory(auth);
      setState(s => s.status !== 'ready' ? s : { ...s, cycle: fresh.cycle });
      setModal(null);
    } catch { setSetupError('Save failed — please try again.'); }
    finally { setSetupSaving(false); }
  }

  if (state.status === 'loading') return <div className="p-4 text-slate-400">Loading…</div>;
  if (state.status === 'error') return <div className="p-4 text-red-400">Error: {state.message}</div>;

  const { stock, cycle, pakInstalledAt, pakSessions } = state;
  const callDate = cycle?.call_date ?? new Date().toISOString().slice(0, 10);

  const nxstageItems = ITEMS.filter(i => i.section === 'nxstage');
  const hospitalItems = ITEMS.filter(i => i.section === 'hospital');
  const allEntries = ITEMS.map(i => ({ code: i.code, qty: stock[i.code] ?? 0 }));
  const sorted = sortStock(allEntries);
  const sortedNxstage = sorted.filter(e => nxstageItems.find(i => i.code === e.code));
  const sortedHospital = sorted.filter(e => hospitalItems.find(i => i.code === e.code));

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-bold inline-flex items-center gap-2">
        <Package size={20} className="text-accent" /> Inventory
      </h1>

      <DeliveryCycleBanner
        cycle={cycle}
        onSetupCycle={() => setModal('setup')}
        onOpenOrder={() => setModal(cycle?.order_placed_at ? 'delivery' : 'order')}
        onViewOrder={() => setModal('order_summary')}
      />

      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => setModal('log')}
          className="flex-1 border border-slate-600 text-slate-300 rounded-lg py-2 text-sm"
        >
          + Log event
        </button>
        <button
          type="button"
          onClick={handleOpenHistory}
          className="border border-slate-600 text-slate-400 rounded-lg py-2 px-4 text-sm"
        >
          Deliveries
        </button>
      </div>

      {/* NxStage supplies */}
      <section>
        <h2 className="text-xs uppercase text-slate-500 tracking-wider mb-2">NxStage Supplies</h2>
        <div className="bg-panel border border-slate-700 rounded-lg divide-y divide-slate-700/50 px-3">
          {sortedNxstage.map(({ code, qty }) => {
            const item = nxstageItems.find(i => i.code === code)!;
            return (
              <StockItemRow
                key={code}
                item={item}
                qty={qty}
                onAdjust={delta => handleAdjust(code, delta)}
                pakInstalledAt={code === 'PAK-001' ? pakInstalledAt : undefined}
                pakSessions={code === 'PAK-001' ? pakSessions : undefined}
              />
            );
          })}
        </div>
      </section>

      {/* Hospital prescriptions */}
      <section>
        <h2 className="text-xs uppercase text-slate-500 tracking-wider mb-2">Hospital Prescriptions</h2>
        <div className="bg-panel border border-slate-700 rounded-lg divide-y divide-slate-700/50 px-3">
          {sortedHospital.map(({ code, qty }) => {
            const item = hospitalItems.find(i => i.code === code)!;
            return (
              <StockItemRow
                key={code}
                item={item}
                qty={qty}
                onAdjust={delta => handleAdjust(code, delta)}
              />
            );
          })}
        </div>
      </section>

      {/* Setup cycle modal */}
      {modal === 'setup' && (
        <div className="kb-overlay fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
          <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-xs p-4 space-y-3">
            <h2 className="font-semibold text-slate-200">Set first call date</h2>
            <input
              type="date"
              value={setupDate}
              onChange={e => setSetupDate(e.target.value)}
              className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
            />
            {setupError && <p className="text-red-400 text-sm">{setupError}</p>}
            <div className="flex gap-2">
              <button type="button" onClick={() => setModal(null)} className="flex-1 border border-slate-600 text-slate-300 rounded-lg py-2 text-sm">Cancel</button>
              <button type="button" onClick={handleSetupCycle} disabled={!setupDate || setupSaving} className="flex-1 bg-accent text-bg font-semibold rounded-lg py-2 text-sm disabled:opacity-40">
                {setupSaving ? 'Saving…' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}

      {modal === 'log' && (
        <LogEventModal
          stock={stock}
          onLogEvent={handleLogEvent}
          onSetPakInstall={handleSetPakInstall}
          onClose={() => setModal(null)}
        />
      )}

      {modal === 'history' && (
        <div className="kb-overlay fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
          <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between px-4 pt-4 pb-3 flex-shrink-0">
              <span className="font-semibold text-slate-200">Delivery history</span>
              <button type="button" onClick={() => setModal(null)} className="text-slate-500 hover:text-slate-300">
                <X size={18} />
              </button>
            </div>
            <div className="overflow-y-auto flex-1 px-4 pb-4">
              {historyLoading && <p className="text-sm text-slate-400 py-4 text-center">Loading…</p>}
              {!historyLoading && deliveryHistory?.length === 0 && (
                <p className="text-sm text-slate-400 py-4 text-center">No deliveries applied yet.</p>
              )}
              {!historyLoading && deliveryHistory && deliveryHistory.length > 0 && (
                <div className="space-y-4">
                  {deliveryHistory.map((d, i) => {
                    const date = new Date(d.timestamp).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
                    const items = Object.entries(d.deltas).filter(([, qty]) => qty > 0);
                    return (
                      <div key={i} className="border-t border-slate-800 pt-3 first:border-0 first:pt-0">
                        <p className="text-xs text-slate-500 mb-1">{date}</p>
                        {items.map(([code, qty]) => {
                          const item = ITEMS.find(it => it.code === code);
                          const label = item?.label ?? code;
                          const boxes = item ? Math.round(qty / item.boxSize) : qty;
                          const boxLabel = item ? (boxes === 1 ? item.boxLabel : item.boxLabel + 's') : 'units';
                          return (
                            <div key={code} className="flex justify-between text-sm py-0.5">
                              <span className="text-slate-300">{label}</span>
                              <span className="text-accent font-semibold">+{boxes} {boxLabel}</span>
                            </div>
                          );
                        })}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {modal === 'order_summary' && cycle?.order && (
        <div className="kb-overlay fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
          <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm">
            <div className="flex items-center justify-between px-4 pt-4 pb-3">
              <div>
                <span className="font-semibold text-slate-200">Placed order</span>
                {cycle.order_placed_at && (
                  <span className="ml-2 text-xs text-slate-500">
                    {new Date(cycle.order_placed_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
                  </span>
                )}
              </div>
              <button type="button" onClick={() => setModal(null)} className="text-slate-500 hover:text-slate-300">
                <X size={18} />
              </button>
            </div>
            <div className="px-4 pb-4 space-y-1">
              {Object.entries(cycle.order).filter(([, qty]) => qty > 0).map(([code, qty]) => {
                const item = ITEMS.find(i => i.code === code);
                const label = item?.label ?? code;
                const boxes = item ? Math.round(qty / item.boxSize) : qty;
                const boxLabel = item ? (boxes === 1 ? item.boxLabel : item.boxLabel + 's') : 'units';
                return (
                  <div key={code} className="flex items-center justify-between py-1 border-t border-slate-800 first:border-0">
                    <span className="text-sm text-slate-300">{label}</span>
                    <span className="text-sm font-semibold text-accent">{boxes} {boxLabel}</span>
                  </div>
                );
              })}
              <p className="text-xs text-slate-500 pt-2">
                Delivery expected {new Date(cycle.delivery_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
              </p>
            </div>
          </div>
        </div>
      )}

      {(modal === 'order' || modal === 'delivery') && (
        <OrderView
          stock={stock}
          callDate={callDate}
          cycleOrder={cycle?.order}
          onStockCount={handleStockCount}
          onConfirmOrder={handleConfirmOrder}
          onApplyDelivery={handleApplyDelivery}
          mode={modal === 'delivery' ? 'delivery' : 'order'}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}
