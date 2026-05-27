import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import { filterRows, isValidBound, type QueryParams } from '../lib/queryFilter.js';
import { PHASES, type BloodTestRow } from '../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const rows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../data/blood_tests.json'), 'utf8'),
);

export const bloodTests = new Hono().get('/', (c) => {
  const params = c.req.query();
  const p: QueryParams = {};

  const marker = params['marker'];
  if (marker) p.marker = marker.split(',').map((s) => s.trim()).filter(Boolean);

  const phase = params['phase'];
  if (phase) {
    p.phase = phase.split(',').map((s) => s.trim()).filter(Boolean);
    if (p.phase.some((x) => !(PHASES as readonly string[]).includes(x))) {
      return c.json({ error: 'invalid phase param' }, 400);
    }
  }

  const from = params['from'];
  if (from) {
    if (!isValidBound(from)) return c.json({ error: 'invalid from param' }, 400);
    p.from = from;
  }

  const to = params['to'];
  if (to) {
    if (!isValidBound(to)) return c.json({ error: 'invalid to param' }, 400);
    p.to = to;
  }

  const result = filterRows(rows, p);
  return c.json({ count: result.length, rows: result });
});
