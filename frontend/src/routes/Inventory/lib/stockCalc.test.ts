import { describe, it, expect } from 'vitest';
import {
  sessionsRemaining,
  stockStatus,
  needsOrdering,
  orderUnits,
  orderBoxes,
  sortStock,
} from './stockCalc';

describe('sessionsRemaining', () => {
  it('returns qty for 1:1 items (SAK, cartridge, saline)', () => {
    expect(sessionsRemaining('SAK-303', 12)).toBe(12);
    expect(sessionsRemaining('CAR-172-C', 6)).toBe(6);
    expect(sessionsRemaining('UK00000880', 10)).toBe(10);
  });

  it('divides by 2 for needles (2 per session)', () => {
    expect(sessionsRemaining('P00012326', 20)).toBe(10);
    expect(sessionsRemaining('P00012326', 5)).toBe(2);
  });

  it('multiplies by 10 for PAK (1 per 10 sessions)', () => {
    expect(sessionsRemaining('PAK-001', 2)).toBe(20);
    expect(sessionsRemaining('PAK-001', 0)).toBe(0);
  });

  it('returns null for hospital items', () => {
    expect(sessionsRemaining('heparin', 5)).toBeNull();
    expect(sessionsRemaining('epo', 3)).toBeNull();
  });

  it('returns null for unknown code', () => {
    expect(sessionsRemaining('UNKNOWN', 5)).toBeNull();
  });
});

describe('stockStatus', () => {
  it('returns red when sessions remaining < 8', () => {
    expect(stockStatus('SAK-303', 7)).toBe('red');
    expect(stockStatus('SAK-303', 0)).toBe('red');
  });

  it('returns amber when sessions remaining 8–15', () => {
    expect(stockStatus('SAK-303', 8)).toBe('amber');
    expect(stockStatus('SAK-303', 15)).toBe('amber');
  });

  it('returns green when sessions remaining >= 16', () => {
    expect(stockStatus('SAK-303', 16)).toBe('green');
    expect(stockStatus('SAK-303', 24)).toBe('green');
  });

  it('returns green for hospital items with stock > 1', () => {
    expect(stockStatus('heparin', 4)).toBe('green');
  });

  it('returns red for hospital items with 0 stock', () => {
    expect(stockStatus('heparin', 0)).toBe('red');
  });

  it('returns amber for hospital items with 1 unit', () => {
    expect(stockStatus('heparin', 1)).toBe('amber');
  });
});

describe('needsOrdering', () => {
  it('returns true when stock below target', () => {
    expect(needsOrdering('SAK-303', 10)).toBe(true);   // target = 24
  });

  it('returns false when stock at or above target', () => {
    expect(needsOrdering('SAK-303', 24)).toBe(false);
    expect(needsOrdering('SAK-303', 30)).toBe(false);
  });

  it('always returns false for hospital items', () => {
    expect(needsOrdering('heparin', 0)).toBe(false);
    expect(needsOrdering('epo', 0)).toBe(false);
  });
});

describe('orderBoxes', () => {
  it('calculates boxes needed for SAK (boxSize=2)', () => {
    // target=24 bags, have 10 → need 14 → ceil(14/2) = 7 boxes
    expect(orderBoxes('SAK-303', 10)).toBe(7);
  });

  it('calculates boxes needed for cartridges (boxSize=6)', () => {
    // target=24, have 6 → need 18 → ceil(18/6) = 3 boxes
    expect(orderBoxes('CAR-172-C', 6)).toBe(3);
  });

  it('returns 0 when stock meets or exceeds target', () => {
    expect(orderBoxes('SAK-303', 24)).toBe(0);
    expect(orderBoxes('SAK-303', 30)).toBe(0);
  });
});

describe('sortStock', () => {
  it('puts needs-ordering items first', () => {
    const entries = [
      { code: 'SAK-303', qty: 30 },         // green, no order
      { code: 'CAR-172-C', qty: 5 },        // red, needs order
    ];
    const sorted = sortStock(entries);
    expect(sorted[0].code).toBe('CAR-172-C');
  });

  it('sorts by priority within the same needs-ordering group', () => {
    const entries = [
      { code: 'PAK-001', qty: 0 },       // needs ordering, priority 4
      { code: 'SAK-303', qty: 0 },       // needs ordering, priority 1
    ];
    const sorted = sortStock(entries);
    expect(sorted[0].code).toBe('SAK-303');
  });

  it('places hospital items after all nxstage items', () => {
    const entries = [
      { code: 'heparin', qty: 0 },
      { code: 'SAK-303', qty: 0 },
    ];
    const sorted = sortStock(entries);
    expect(sorted[sorted.length - 1].code).toBe('heparin');
  });
});
