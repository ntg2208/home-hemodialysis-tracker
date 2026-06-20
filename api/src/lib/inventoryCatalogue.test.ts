import { describe, it, expect } from 'vitest';
import {
  items,
  getItem,
  effectivePerSession,
  sessionsRemaining,
  stockStatus,
  consumedUnits,
  boxesFor,
} from './inventoryCatalogue.js';

describe('catalogue parity with constants.dart', () => {
  it('has all 13 items with unique codes', () => {
    expect(items).toHaveLength(13);
    expect(new Set(items.map((i) => i.code)).size).toBe(13);
  });

  it('spot-checks key item fields', () => {
    expect(getItem('CAR-172-C')).toMatchObject({
      label: 'Cartridges', unit: 'cartridge', boxSize: 6, perSession: 1, targetQty: 24, section: 'nxstage',
    });
    expect(getItem('P00012326')).toMatchObject({
      label: 'Buttonhole Needles', unit: 'needle', boxSize: 50, perSession: null, targetQty: 48,
    });
    expect(getItem('PAK-001')).toMatchObject({ perSession: null, targetQty: 3 });
    expect(getItem('heparin')).toMatchObject({ section: 'hospital', perSession: null });
  });
});

describe('effectivePerSession', () => {
  it('reports the rate the math actually uses', () => {
    expect(effectivePerSession('P00012326')).toBe(2); // needles
    expect(effectivePerSession('CAR-172-C')).toBe(1);
    expect(effectivePerSession('PAK-001')).toBeNull(); // lifespan-based, not per-session
    expect(effectivePerSession('heparin')).toBeNull(); // hospital
    expect(effectivePerSession('UNKNOWN')).toBeNull();
  });
});

describe('sessionsRemaining', () => {
  it('PAK = qty * 10', () => {
    expect(sessionsRemaining('PAK-001', 3)).toBe(30);
  });
  it('needles = floor(qty / 2)', () => {
    expect(sessionsRemaining('P00012326', 52)).toBe(26);
    expect(sessionsRemaining('P00012326', 5)).toBe(2);
  });
  it('per-session items = floor(qty / perSession)', () => {
    expect(sessionsRemaining('CAR-172-C', 24)).toBe(24);
    expect(sessionsRemaining('UK00000774', 60)).toBe(60); // on/off pack, perSession 1
  });
  it('null for hospital, sundry (no rate), and unknown', () => {
    expect(sessionsRemaining('heparin', 8)).toBeNull();
    expect(sessionsRemaining('UK00000832', 1)).toBeNull(); // sharps bin, perSession null
    expect(sessionsRemaining('UNKNOWN', 5)).toBeNull();
  });
});

describe('stockStatus (golden: red < 8, amber < 16, green)', () => {
  it('nxstage by sessions-remaining', () => {
    expect(stockStatus('CAR-172-C', 7)).toBe('red'); // sr 7
    expect(stockStatus('CAR-172-C', 8)).toBe('amber'); // sr 8
    expect(stockStatus('CAR-172-C', 15)).toBe('amber'); // sr 15
    expect(stockStatus('CAR-172-C', 16)).toBe('green'); // sr 16
    expect(stockStatus('P00012326', 52)).toBe('green'); // sr 26
  });
  it('nxstage sundry (no sr) falls back to qty', () => {
    expect(stockStatus('UK00000832', 0)).toBe('red');
    expect(stockStatus('UK00000832', 1)).toBe('amber');
    expect(stockStatus('UK00000832', 2)).toBe('green');
  });
  it('hospital items are qty-based', () => {
    expect(stockStatus('heparin', 0)).toBe('red');
    expect(stockStatus('heparin', 1)).toBe('amber');
    expect(stockStatus('epo', 4)).toBe('green');
  });
  it('unknown code by qty', () => {
    expect(stockStatus('UNKNOWN', 0)).toBe('red');
    expect(stockStatus('UNKNOWN', 5)).toBe('green');
  });
});

describe('consumedUnits', () => {
  it('inverse of the per-session rates', () => {
    expect(consumedUnits('PAK-001', 25)).toBe(3); // ceil(25/10)
    expect(consumedUnits('P00012326', 10)).toBe(20); // needles 2/session
    expect(consumedUnits('CAR-172-C', 12)).toBe(12);
    expect(consumedUnits('UK00000832', 12)).toBe(0); // no rate
  });
});

describe('boxesFor', () => {
  it('ceil(qty / boxSize), 1 for unknown', () => {
    expect(boxesFor('SAK-303', 24)).toBe(12); // box size 2
    expect(boxesFor('CAR-172-C', 24)).toBe(4); // box size 6
    expect(boxesFor('P00012326', 50)).toBe(1); // box size 50
    expect(boxesFor('UNKNOWN', 3)).toBe(3); // size 1 fallback
  });
});
