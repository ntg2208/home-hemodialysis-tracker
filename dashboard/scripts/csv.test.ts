import { describe, it, expect } from 'vitest';
import { csvToRows } from './csv';

const HEADER =
  'marker,datetime,value,unit,ref_low,ref_high,timing,note,source,lab_id,phase,created_at';

describe('csvToRows', () => {
  it('parses a numeric row and sorts by datetime', () => {
    const csv = [
      HEADER,
      'urea,2026-05-18T14:18:00,19.7,mmol/L,2.5,7.8,pre,,imperial-pkb,1,home-hd,2026-05-22T10:00:00',
      'urea,2026-04-15T12:00:00,1.9,mmol/L,2.5,7.8,post,,imperial-pkb,2,home-hd,2026-05-22T10:00:00',
    ].join('\n');
    const rows = csvToRows(csv);
    expect(rows.map((r) => r.datetime)).toEqual([
      '2026-04-15T12:00:00', '2026-05-18T14:18:00',
    ]);
    expect(rows[1].value).toBe(19.7);
    expect(rows[1].qualitative).toBe(false);
  });

  it('treats blank reference bounds as null', () => {
    const csv = [HEADER, 'mcv,2026-05-18T14:18:00,88,fL,,,,,lnw-pkb,3,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)[0].ref_low).toBeNull();
  });

  it('flags a qualitative result (value 0) and keeps the text unit', () => {
    const csv = [HEADER, 'mrsa_screen,2026-05-18T14:18:00,0,Not detected,,,,,lnw-pkb,4,home-hd,2026-05-22T10:00:00'].join('\n');
    const row = csvToRows(csv)[0];
    expect(row.qualitative).toBe(true);
    expect(row.unit).toBe('Not detected');
  });

  it('strips thousands commas from values', () => {
    const csv = [HEADER, '"creatinine",2026-05-18T14:18:00,"1,073",umol/L,64,104,pre,,imperial-pkb,5,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)[0].value).toBe(1073);
  });

  it('drops rows with no marker or datetime', () => {
    const csv = [HEADER, ',,,,,,,,,,,', 'urea,2026-05-18T14:18:00,5,mmol/L,2.5,7.8,,,imperial-pkb,6,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)).toHaveLength(1);
  });
});
