import { ITEMS, getItem } from '../constants';

const RED_THRESHOLD = 8;    // < 2 weeks of sessions
const AMBER_THRESHOLD = 16; // < 4 weeks of sessions

export function sessionsRemaining(code: string, qty: number): number | null {
  if (code === 'PAK-001') return qty * 10;
  if (code === 'P00012326') return Math.floor(qty / 2);
  const item = getItem(code);
  if (!item || item.section === 'hospital') return null;
  if (item.perSession && item.perSession > 0) return Math.floor(qty / item.perSession);
  return null;
}

export type StockStatus = 'red' | 'amber' | 'green';

export function stockStatus(code: string, qty: number): StockStatus {
  const item = getItem(code);
  if (!item) return qty > 0 ? 'green' : 'red';

  if (item.section === 'hospital') {
    if (qty <= 0) return 'red';
    if (qty <= 1) return 'amber';
    return 'green';
  }

  const sr = sessionsRemaining(code, qty);
  if (sr === null) return qty <= 0 ? 'red' : qty <= 1 ? 'amber' : 'green';
  if (sr < RED_THRESHOLD) return 'red';
  if (sr < AMBER_THRESHOLD) return 'amber';
  return 'green';
}

export function needsOrdering(code: string, qty: number): boolean {
  const item = getItem(code);
  if (!item || item.section === 'hospital') return false;
  return qty < item.targetQty;
}

export function orderUnits(code: string, currentQty: number): number {
  const item = getItem(code);
  if (!item || item.section === 'hospital') return 0;
  return Math.max(0, item.targetQty - currentQty);
}

export function orderBoxes(code: string, currentQty: number): number {
  const item = getItem(code);
  if (!item) return 0;
  return Math.ceil(orderUnits(code, currentQty) / item.boxSize);
}

export interface StockEntry { code: string; qty: number; }

export function sortStock(entries: StockEntry[]): StockEntry[] {
  const nxstage = entries.filter(e => getItem(e.code)?.section === 'nxstage');
  const hospital = entries.filter(e => getItem(e.code)?.section === 'hospital');
  const unknowns = entries.filter(e => !getItem(e.code));

  function sortGroup(group: StockEntry[]): StockEntry[] {
    return [...group].sort((a, b) => {
      const aNeedsOrder = needsOrdering(a.code, a.qty);
      const bNeedsOrder = needsOrdering(b.code, b.qty);
      if (aNeedsOrder !== bNeedsOrder) return aNeedsOrder ? -1 : 1;
      return (getItem(a.code)?.priority ?? 99) - (getItem(b.code)?.priority ?? 99);
    });
  }

  return [...sortGroup(nxstage), ...sortGroup(hospital), ...unknowns];
}
