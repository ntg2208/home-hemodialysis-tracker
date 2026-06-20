import { describe, it, expect } from 'vitest';
import {
  averagePakLifespan,
  enrichStock,
  enrichOrderItems,
  buildCurrentOrder,
  buildOrders,
} from './inventoryReads.js';

const doc = (sessions: number, replaced_at: string) => ({ data: () => ({ sessions, replaced_at }) });

describe('averagePakLifespan', () => {
  it('returns null with no history', () => {
    expect(averagePakLifespan([])).toBeNull();
  });
  it('averages the 6 most recent valid lifespans', () => {
    const docs = [
      doc(10, '2026-01-01'), doc(20, '2026-02-01'), doc(30, '2026-03-01'),
      doc(40, '2026-04-01'), doc(50, '2026-05-01'), doc(60, '2026-06-01'),
      doc(999, '2025-01-01'), // older than the most recent 6 → excluded
    ];
    expect(averagePakLifespan(docs)).toBe(35); // (10+20+30+40+50+60)/6
  });
});

describe('enrichStock', () => {
  it('joins catalogue metadata + supply math, sorts nxstage→hospital→unknown', () => {
    const out = enrichStock({ heparin: 8, 'CAR-172-C': 24, ZZZ: 3, 'P00012326': 52 });
    expect(out.map((i) => i.code)).toEqual(['CAR-172-C', 'P00012326', 'heparin', 'ZZZ']);

    const car = out.find((i) => i.code === 'CAR-172-C')!;
    expect(car).toMatchObject({
      label: 'Cartridges', qty: 24, unit: 'cartridge', box_size: 6, per_session: 1,
      target_qty: 24, section: 'nxstage', sessions_remaining: 24, status: 'green',
    });

    const needles = out.find((i) => i.code === 'P00012326')!;
    expect(needles).toMatchObject({ per_session: 2, sessions_remaining: 26, status: 'green' });

    const hep = out.find((i) => i.code === 'heparin')!;
    expect(hep).toMatchObject({ section: 'hospital', per_session: null, sessions_remaining: null });
  });

  it('passes unknown codes through with null metadata + qty-based status', () => {
    const [u] = enrichStock({ ZZZ: 0 });
    expect(u).toMatchObject({ code: 'ZZZ', label: null, per_session: null, sessions_remaining: null, status: 'red' });
  });

  it('applies rate overrides to per_session, target, sessions_remaining, status', () => {
    const rates = { 'CAR-172-C': { perSession: 2, targetQty: 30 } };
    const [car] = enrichStock({ 'CAR-172-C': 24 }, rates);
    expect(car).toMatchObject({
      per_session: 2, target_qty: 30, sessions_remaining: 12, status: 'amber',
    });
  });
});

describe('enrichOrderItems', () => {
  it('adds label + box count', () => {
    expect(enrichOrderItems({ 'SAK-303': 24, ZZZ: 3 })).toEqual([
      { code: 'SAK-303', label: 'SAK Dialysate', qty: 24, boxes: 12 },
      { code: 'ZZZ', label: null, qty: 3, boxes: 3 },
    ]);
  });
});

describe('buildCurrentOrder', () => {
  it('null when no cycle or no order placed', () => {
    expect(buildCurrentOrder(null)).toBeNull();
    expect(buildCurrentOrder({ call_date: '2026-06-15', order: { 'SAK-303': 2 } })).toBeNull();
  });
  it('builds the open order with applied flag', () => {
    const co = buildCurrentOrder({
      call_date: '2026-06-15', delivery_date: '2026-06-22',
      order: { 'SAK-303': 24 }, order_placed_at: '2026-06-15T09:00:00Z',
      delivery_applied_at: null,
    });
    expect(co).toEqual({
      call_date: '2026-06-15', delivery_date: '2026-06-22', placed_at: '2026-06-15T09:00:00Z',
      applied: false, items: [{ code: 'SAK-303', label: 'SAK Dialysate', qty: 24, boxes: 12 }],
    });
  });
});

describe('buildOrders', () => {
  const deliveries = [
    { timestamp: '2026-05-25T10:00:00Z', deltas: { 'CAR-172-C': 24 }, note: 'delivery applied' },
    { timestamp: '2026-04-25T10:00:00Z', deltas: { 'SAK-303': 24 }, note: '' },
  ];
  it('maps history newest-first with enriched items', () => {
    const { history } = buildOrders(null, deliveries);
    expect(history).toEqual([
      { date: '2026-05-25T10:00:00Z', note: 'delivery applied', items: [{ code: 'CAR-172-C', label: 'Cartridges', qty: 24, boxes: 4 }] },
      { date: '2026-04-25T10:00:00Z', note: '', items: [{ code: 'SAK-303', label: 'SAK Dialysate', qty: 24, boxes: 12 }] },
    ]);
  });
  it('caps history with limit and includes current_order', () => {
    const cycle = { order: { 'SAK-303': 24 }, order_placed_at: '2026-06-15T09:00:00Z' };
    const out = buildOrders(cycle, deliveries, { limit: 1 });
    expect(out.history).toHaveLength(1);
    expect(out.history[0].date).toBe('2026-05-25T10:00:00Z');
    expect(out.current_order?.placed_at).toBe('2026-06-15T09:00:00Z');
  });
});
