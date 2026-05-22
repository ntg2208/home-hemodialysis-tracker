import data from '../../data/blood_tests.json';
import { filterRows, isValidBound, type QueryParams } from '../../src/lib/queryFilter';
import { PHASES, type BloodTestRow } from '../../src/schemas';

interface Env {
  DASHBOARD_KEY: string;
}

const rows = data as BloodTestRow[];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const onRequestGet: PagesFunction<Env> = (context) => {
  const { request, env } = context;

  const auth = request.headers.get('Authorization');
  if (!env.DASHBOARD_KEY || auth !== `Bearer ${env.DASHBOARD_KEY}`) {
    return json({ error: 'unauthorized' }, 401);
  }

  const params = new URL(request.url).searchParams;
  const p: QueryParams = {};

  const marker = params.get('marker');
  if (marker) p.marker = marker.split(',').map((s) => s.trim()).filter(Boolean);

  const phase = params.get('phase');
  if (phase) {
    p.phase = phase.split(',').map((s) => s.trim()).filter(Boolean);
    if (p.phase.some((x) => !(PHASES as readonly string[]).includes(x))) {
      return json({ error: 'invalid phase param' }, 400);
    }
  }

  const from = params.get('from');
  if (from) {
    if (!isValidBound(from)) return json({ error: 'invalid from param' }, 400);
    p.from = from;
  }

  const to = params.get('to');
  if (to) {
    if (!isValidBound(to)) return json({ error: 'invalid to param' }, 400);
    p.to = to;
  }

  const result = filterRows(rows, p);
  return json({ count: result.length, rows: result });
};
