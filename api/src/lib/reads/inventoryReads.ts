import { getDb } from '../firestore.js';
import {
  getItem,
  effectivePerSession,
  sessionsRemaining,
  stockStatus,
  boxesFor,
  type StockStatus,
} from '../inventoryCatalogue.js';

export interface EnrichedItem {
  code: string;
  label: string | null;
  qty: number;
  unit: string | null;
  box_size: number | null;
  box_label: string | null;
  per_session: number | null;
  target_qty: number | null;
  section: string | null;
  sessions_remaining: number | null;
  status: StockStatus;
}

const sectionRank = (s: string | null): number =>
  s === 'nxstage' ? 0 : s === 'hospital' ? 1 : 2;

/** Pure: enrich a raw `{ code: qty }` stock map with catalogue metadata and
 * server-computed supply math. Unknown codes pass through with null metadata
 * and qty-based status. Sorted nxstage → hospital → unknown, then by priority. */
export function enrichStock(stock: Record<string, number>): EnrichedItem[] {
  return Object.entries(stock)
    .map(([code, qty]): EnrichedItem => {
      const item = getItem(code);
      return {
        code,
        label: item?.label ?? null,
        qty,
        unit: item?.unit ?? null,
        box_size: item?.boxSize ?? null,
        box_label: item?.boxLabel ?? null,
        per_session: effectivePerSession(code),
        target_qty: item?.targetQty ?? null,
        section: item?.section ?? null,
        sessions_remaining: sessionsRemaining(code, qty),
        status: stockStatus(code, qty),
      };
    })
    .sort((a, b) => {
      const r = sectionRank(a.section) - sectionRank(b.section);
      if (r !== 0) return r;
      const pa = getItem(a.code)?.priority ?? 99;
      const pb = getItem(b.code)?.priority ?? 99;
      if (pa !== pb) return pa - pb;
      return a.code.localeCompare(b.code);
    });
}

export interface OrderItem {
  code: string;
  label: string | null;
  qty: number;
  boxes: number;
}

/** Pure: enrich an order/delivery `{ code: qty }` map with label + box count. */
export function enrichOrderItems(map: Record<string, number>): OrderItem[] {
  return Object.entries(map).map(([code, qty]) => ({
    code,
    label: getItem(code)?.label ?? null,
    qty,
    boxes: boxesFor(code, qty),
  }));
}

export interface CurrentOrder {
  call_date: string | null;
  delivery_date: string | null;
  placed_at: string;
  applied: boolean;
  items: OrderItem[];
}

export interface DeliveryRecord {
  date: string;
  note: string;
  items: OrderItem[];
}

export interface DeliveryRow {
  timestamp: string;
  deltas: Record<string, number>;
  note: string;
}

/** Pure: the open order for the current cycle, or null if none placed. */
export function buildCurrentOrder(
  cycle: Record<string, unknown> | null,
): CurrentOrder | null {
  if (!cycle || !cycle.order_placed_at) return null;
  return {
    call_date: (cycle.call_date as string | undefined) ?? null,
    delivery_date: (cycle.delivery_date as string | undefined) ?? null,
    placed_at: cycle.order_placed_at as string,
    applied: cycle.delivery_applied_at != null,
    items: enrichOrderItems((cycle.order as Record<string, number>) ?? {}),
  };
}

/** Pure: assemble the get_orders payload from a cycle doc + delivery rows
 * (rows expected newest-first). `limit` caps the history length. */
export function buildOrders(
  cycle: Record<string, unknown> | null,
  deliveries: DeliveryRow[],
  opts: { limit?: number } = {},
): { current_order: CurrentOrder | null; history: DeliveryRecord[] } {
  let history: DeliveryRecord[] = deliveries.map((d) => ({
    date: d.timestamp,
    note: d.note ?? '',
    items: enrichOrderItems(d.deltas ?? {}),
  }));
  if (opts.limit != null) history = history.slice(0, opts.limit);
  return { current_order: buildCurrentOrder(cycle), history };
}

/// Average session count of the patient's last 6 replaced PAKs, sorted by
/// recency — null when there's no history yet (client falls back to a default).
export function averagePakLifespan(
  docs: { data: () => { sessions?: number; replaced_at?: string } }[],
): number | null {
  const lifespans = docs
    .map((d) => d.data())
    .filter(
      (d): d is { sessions: number; replaced_at: string } =>
        typeof d.sessions === 'number' && d.sessions > 0 && typeof d.replaced_at === 'string',
    )
    .sort((a, b) => b.replaced_at.localeCompare(a.replaced_at))
    .slice(0, 6)
    .map((d) => d.sessions);
  if (lifespans.length === 0) return null;
  return lifespans.reduce((a, b) => a + b, 0) / lifespans.length;
}

export async function getInventory() {
  const db = getDb();
  const [stockSnap, cycleDoc, pakDoc, pakHistorySnap] = await Promise.all([
    db.collection('inventory_stock').get(),
    db.collection('inventory_config').doc('cycle').get(),
    db.collection('inventory_config').doc('pak').get(),
    db.collection('pak_history').get(),
  ]);

  const stock: Record<string, number> = {};
  for (const doc of stockSnap.docs) {
    const d = doc.data() as { qty: number };
    if (typeof d.qty === 'number') stock[doc.id] = d.qty;
  }

  const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;
  const pakData = pakDoc.exists ? (pakDoc.data() as { installed_at?: string }) : null;
  const pak_installed_at = pakData?.installed_at ?? null;

  let pak_sessions = 0;
  if (pak_installed_at) {
    const sessionsSnap = await db.collection('treatment_sessions')
      .where('date', '>=', pak_installed_at)
      .get();
    pak_sessions = sessionsSnap.docs.length;
  }

  const pak_avg_sessions = averagePakLifespan(pakHistorySnap.docs);
  return { stock, cycle, pak_installed_at, pak_sessions, pak_avg_sessions };
}

/** Delivery events (fulfilled orders), newest first, optionally date-windowed
 * on the YYYY-MM-DD prefix of the ISO timestamp. Shared by the REST
 * /deliveries route and the MCP get_orders tool. */
export async function getDeliveries(
  range: { from?: string; to?: string } = {},
): Promise<DeliveryRow[]> {
  const snap = await getDb()
    .collection('inventory_events')
    .where('type', '==', 'delivery')
    .get();
  let rows = snap.docs.map((d) => {
    const x = d.data() as Partial<DeliveryRow>;
    return { timestamp: x.timestamp ?? '', deltas: x.deltas ?? {}, note: x.note ?? '' };
  });
  if (range.from) rows = rows.filter((r) => r.timestamp.slice(0, 10) >= range.from!);
  if (range.to) rows = rows.filter((r) => r.timestamp.slice(0, 10) <= range.to!);
  return rows.sort((a, b) => b.timestamp.localeCompare(a.timestamp));
}

/** Recent orders: the current open order (from the cycle doc) plus delivery
 * history. Date window + limit applied to the history. */
export async function getOrders(
  opts: { from?: string; to?: string; limit?: number } = {},
): Promise<{ current_order: CurrentOrder | null; history: DeliveryRecord[] }> {
  const db = getDb();
  const [cycleDoc, deliveries] = await Promise.all([
    db.collection('inventory_config').doc('cycle').get(),
    getDeliveries({ from: opts.from, to: opts.to }),
  ]);
  const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;
  return buildOrders(cycle, deliveries, { limit: opts.limit });
}
