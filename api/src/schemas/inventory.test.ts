import { describe, it, expect } from 'vitest';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
  StockGetResponseSchema,
} from './inventory.js';

describe('EventBodySchema', () => {
  it('accepts a valid session event', () => {
    const r = EventBodySchema.safeParse({
      type: 'session',
      deltas: { 'SAK-303': -1, 'CAR-172-C': -1 },
    });
    expect(r.success).toBe(true);
  });

  it('accepts a stock_count event with absolute values', () => {
    const r = EventBodySchema.safeParse({
      type: 'stock_count',
      deltas: { 'SAK-303': 12 },
      note: 'monthly count',
    });
    expect(r.success).toBe(true);
  });

  it('rejects unknown type', () => {
    const r = EventBodySchema.safeParse({ type: 'unknown', deltas: {} });
    expect(r.success).toBe(false);
  });
});

describe('ConfirmOrderBodySchema', () => {
  it('accepts valid call_date and order', () => {
    const r = ConfirmOrderBodySchema.safeParse({
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(r.success).toBe(true);
  });

  it('accepts empty order for initial setup', () => {
    const r = ConfirmOrderBodySchema.safeParse({ call_date: '2026-06-23', order: {} });
    expect(r.success).toBe(true);
  });

  it('rejects malformed call_date', () => {
    const r = ConfirmOrderBodySchema.safeParse({ call_date: '23-06-2026', order: {} });
    expect(r.success).toBe(false);
  });

  it('rejects negative order values', () => {
    const r = ConfirmOrderBodySchema.safeParse({
      call_date: '2026-06-23',
      order: { 'SAK-303': -1 },
    });
    expect(r.success).toBe(false);
  });
});

describe('ApplyDeliveryBodySchema', () => {
  it('accepts empty body', () => {
    const r = ApplyDeliveryBodySchema.safeParse({});
    expect(r.success).toBe(true);
  });

  it('accepts adjustments', () => {
    const r = ApplyDeliveryBodySchema.safeParse({ adjustments: { 'SAK-303': 14 } });
    expect(r.success).toBe(true);
  });

  it('rejects float adjustments', () => {
    const r = ApplyDeliveryBodySchema.safeParse({ adjustments: { 'SAK-303': 2.5 } });
    expect(r.success).toBe(false);
  });
});

describe('StockGetResponseSchema', () => {
  it('accepts valid response with null cycle', () => {
    const r = StockGetResponseSchema.safeParse({ stock: { 'SAK-303': 12 }, cycle: null });
    expect(r.success).toBe(true);
  });

  it('accepts valid response with a cycle', () => {
    const r = StockGetResponseSchema.safeParse({
      stock: {},
      cycle: {
        call_date: '2026-06-23',
        delivery_date: '2026-06-30',
        order: { 'SAK-303': 16 },
        order_placed_at: '2026-06-23T10:00:00Z',
        delivery_applied_at: null,
      },
    });
    expect(r.success).toBe(true);
  });
});
