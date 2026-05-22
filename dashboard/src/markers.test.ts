import { describe, it, expect } from 'vitest';
import { panelFor, displayName, PANELS } from './markers';

describe('panelFor', () => {
  it('maps known markers to their panel', () => {
    expect(panelFor('creatinine')).toBe('Renal');
    expect(panelFor('alt')).toBe('Liver');
    expect(panelFor('haemoglobin')).toBe('Haematology');
  });
  it('falls back to Other for unmapped markers', () => {
    expect(panelFor('some_rare_marker')).toBe('Other');
  });
});

describe('displayName', () => {
  it('uses overrides for acronyms', () => {
    expect(displayName('egfr')).toBe('eGFR');
    expect(displayName('hba1c')).toBe('HbA1c');
  });
  it('title-cases snake_case names by default', () => {
    expect(displayName('adjusted_calcium')).toBe('Adjusted Calcium');
  });
});

describe('PANELS', () => {
  it('ends with Other', () => {
    expect(PANELS[PANELS.length - 1]).toBe('Other');
  });
});
