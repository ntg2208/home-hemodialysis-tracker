import { useState } from 'react';
import { X } from 'lucide-react';
import { ITEMS } from '../constants';

type Tab = 'pak' | 'manual' | 'count';

interface Props {
  stock: Record<string, number>;
  onLogEvent: (
    type: 'manual' | 'stock_count',
    deltas: Record<string, number>,
    note?: string,
  ) => Promise<void>;
  onSetPakInstall?: (installedAt: string) => Promise<void>;
  onClose: () => void;
}

export function LogEventModal({ stock, onLogEvent, onSetPakInstall, onClose }: Props) {
  const [tab, setTab] = useState<Tab>('pak');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // PAK tab
  const todayIso = new Date().toISOString().slice(0, 10);
  const [pakInstallDate, setPakInstallDate] = useState(todayIso);
  async function handlePakChange() {
    setSaving(true);
    setError(null);
    try {
      await onLogEvent('manual', { 'PAK-001': -1 }, 'PAK change');
      if (onSetPakInstall && pakInstallDate) {
        await onSetPakInstall(pakInstallDate);
      }
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Manual use tab
  const [manualCode, setManualCode] = useState('');
  const [manualDelta, setManualDelta] = useState('');
  async function handleManualUse() {
    if (!manualCode || !manualDelta) return;
    setSaving(true);
    setError(null);
    try {
      await onLogEvent('manual', { [manualCode]: -Math.abs(Number(manualDelta)) });
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Stock count tab
  const [counts, setCounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(ITEMS.map(i => [i.code, String(stock[i.code] ?? 0)]))
  );
  async function handleStockCount() {
    setSaving(true);
    setError(null);
    try {
      const deltas: Record<string, number> = {};
      for (const [code, val] of Object.entries(counts)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) deltas[code] = n;
      }
      await onLogEvent('stock_count', deltas, 'monthly stock count');
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  const tabClass = (t: Tab) =>
    `px-3 py-1.5 text-sm rounded-t border-b-2 transition-colors ${
      tab === t ? 'border-accent text-accent' : 'border-transparent text-slate-400 hover:text-slate-200'
    }`;

  return (
    <div className="kb-overlay fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
      <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm">
        <div className="flex items-center justify-between px-4 pt-4">
          <span className="font-semibold text-slate-200">Log event</span>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-slate-300">
            <X size={18} />
          </button>
        </div>

        <div className="flex px-4 pt-3 gap-1 border-b border-slate-700">
          <button type="button" className={tabClass('pak')} onClick={() => setTab('pak')}>PAK change</button>
          <button type="button" className={tabClass('manual')} onClick={() => setTab('manual')}>Manual use</button>
          <button type="button" className={tabClass('count')} onClick={() => setTab('count')}>Stock count</button>
        </div>

        <div className="p-4 space-y-3">
          {tab === 'pak' && (
            <div className="space-y-3">
              <p className="text-sm text-slate-400">Records −1 PAK from stock and resets the session counter.</p>
              <div className="flex items-center gap-3">
                <label className="text-sm text-slate-300 shrink-0">Install date</label>
                <input
                  type="date"
                  value={pakInstallDate}
                  onChange={e => setPakInstallDate(e.target.value)}
                  className="flex-1 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200"
                />
              </div>
              <button
                type="button"
                onClick={handlePakChange}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Confirm PAK change'}
              </button>
            </div>
          )}

          {tab === 'manual' && (
            <div className="space-y-3">
              <select
                value={manualCode}
                onChange={e => setManualCode(e.target.value)}
                className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
              >
                <option value="">Select item…</option>
                {ITEMS.filter(i => i.section === 'nxstage').map(i => (
                  <option key={i.code} value={i.code}>{i.label}</option>
                ))}
              </select>
              <input
                type="number"
                min="1"
                inputMode="numeric"
                value={manualDelta}
                onChange={e => setManualDelta(e.target.value)}
                placeholder="Qty used"
                className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
              />
              <button
                type="button"
                onClick={handleManualUse}
                disabled={saving || !manualCode || !manualDelta}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2 disabled:opacity-40"
              >
                {saving ? 'Saving…' : 'Log use'}
              </button>
            </div>
          )}

          {tab === 'count' && (
            <div className="space-y-2">
              <p className="text-xs text-slate-500">Enter actual quantities on hand. This overwrites the running estimate.</p>
              <div className="max-h-64 overflow-y-auto space-y-2 pr-1">
                {ITEMS.map(i => (
                  <div key={i.code} className="flex items-center gap-3">
                    <label className="flex-1 text-sm text-slate-300 truncate">{i.label}</label>
                    <span className="text-xs text-slate-500 shrink-0">{i.unit}</span>
                    <input
                      type="number"
                      min="0"
                      inputMode="numeric"
                      value={counts[i.code] ?? '0'}
                      onChange={e => setCounts(c => ({ ...c, [i.code]: e.target.value }))}
                      className="w-16 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right"
                    />
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={handleStockCount}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Save stock count'}
              </button>
            </div>
          )}

          {error && <p className="text-red-400 text-sm">{error}</p>}
        </div>
      </div>
    </div>
  );
}
