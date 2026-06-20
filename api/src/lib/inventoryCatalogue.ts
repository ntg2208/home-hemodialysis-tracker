// Inventory item catalogue + supply math for the API.
// Port of flutter/lib/features/inventory/constants.dart (items) and
// stock_calc.dart (sessionsRemaining / stockStatus / consumedUnits).
//
// Computed from STATIC DEFAULTS only — on-device rate-overrides (Hive
// `supply_rates`) are not visible to the server, so this intentionally omits
// the `rates` parameter the Flutter functions take.

export interface ItemDef {
  code: string;
  label: string;
  unit: string;
  boxSize: number;
  boxLabel: string;
  perSession: number | null;
  targetQty: number;
  section: 'nxstage' | 'hospital';
  priority: number;
}

export const items: ItemDef[] = [
  // NxStage supplies
  { code: 'SAK-303', label: 'SAK Dialysate', unit: 'bag', boxSize: 2, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 1 },
  { code: 'CAR-172-C', label: 'Cartridges', unit: 'cartridge', boxSize: 6, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 2 },
  { code: 'UK00000880', label: 'Saline 1L', unit: 'bag', boxSize: 10, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 3 },
  { code: 'PAK-001', label: 'PAK', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 3, section: 'nxstage', priority: 4 },
  { code: 'P00012326', label: 'Buttonhole Needles', unit: 'needle', boxSize: 50, boxLabel: 'box', perSession: null, targetQty: 48, section: 'nxstage', priority: 5 },
  { code: 'UK00000774', label: 'On/Off Pack', unit: 'pack', boxSize: 60, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 6 },
  { code: 'F00010983', label: 'Chlorine Strips', unit: 'strip', boxSize: 100, boxLabel: 'pack', perSession: 1, targetQty: 24, section: 'nxstage', priority: 7 },
  { code: 'UK00000830', label: 'Sani-Cloth AF', unit: 'box', boxSize: 1, boxLabel: 'box', perSession: null, targetQty: 1, section: 'nxstage', priority: 8 },
  { code: '1990134', label: 'Spirigel Hand Gel', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 1, section: 'nxstage', priority: 9 },
  { code: 'UK00000832', label: 'Sharps Bin', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 1, section: 'nxstage', priority: 10 },
  { code: 'UK00000172', label: 'Micropore Tape', unit: 'roll', boxSize: 12, boxLabel: 'box', perSession: null, targetQty: 4, section: 'nxstage', priority: 11 },
  // Hospital prescriptions
  { code: 'heparin', label: 'Heparin', unit: 'unit', boxSize: 1, boxLabel: 'unit', perSession: null, targetQty: 8, section: 'hospital', priority: 1 },
  { code: 'epo', label: 'EPO', unit: 'unit', boxSize: 1, boxLabel: 'unit', perSession: null, targetQty: 4, section: 'hospital', priority: 2 },
];

const byCode = new Map(items.map((i) => [i.code, i]));

export function getItem(code: string): ItemDef | undefined {
  return byCode.get(code);
}

const RED_THRESHOLD = 8; // < ~2 weeks of sessions
const AMBER_THRESHOLD = 16; // < ~4 weeks of sessions

export type StockStatus = 'red' | 'amber' | 'green';

/**
 * Effective per-session rate used by the supply math, including the special
 * cases not expressed by `ItemDef.perSession`. Null = no session-based rate
 * (hospital items, sundries). Reported in `get_inventory` so clients can
 * reconcile `sessions_remaining`.
 */
export function effectivePerSession(code: string): number | null {
  if (code === 'P00012326') return 2; // needles: 2 per session
  const item = getItem(code);
  if (!item || item.section === 'hospital') return null;
  return item.perSession;
}

/** Sessions of supply remaining, or null for hospital/unknown/no-rate items. */
export function sessionsRemaining(code: string, qty: number): number | null {
  if (code === 'PAK-001') return qty * 10; // a PAK lasts ~10 sessions
  if (code === 'P00012326') return Math.floor(qty / 2); // needles: 2 per session
  const item = getItem(code);
  if (!item || item.section === 'hospital') return null;
  if (item.perSession != null && item.perSession > 0) {
    return Math.floor(qty / item.perSession);
  }
  return null;
}

export function stockStatus(code: string, qty: number): StockStatus {
  const item = getItem(code);
  if (!item) return qty > 0 ? 'green' : 'red';

  if (item.section === 'hospital') {
    if (qty <= 0) return 'red';
    if (qty <= 1) return 'amber';
    return 'green';
  }

  const sr = sessionsRemaining(code, qty);
  if (sr == null) {
    return qty <= 0 ? 'red' : qty <= 1 ? 'amber' : 'green';
  }
  if (sr < RED_THRESHOLD) return 'red';
  if (sr < AMBER_THRESHOLD) return 'amber';
  return 'green';
}

/** Units consumed over `sessions` sessions (inverse of sessionsRemaining). */
export function consumedUnits(code: string, sessions: number): number {
  if (code === 'PAK-001') return Math.ceil(sessions / 10);
  if (code === 'P00012326') return sessions * 2;
  const item = getItem(code);
  if (!item || item.perSession == null || item.perSession <= 0) return 0;
  return sessions * item.perSession;
}

/** Whole boxes a unit quantity represents (ceil), 1 for unknown codes. */
export function boxesFor(code: string, qty: number): number {
  const size = getItem(code)?.boxSize ?? 1;
  return Math.ceil(qty / size);
}
