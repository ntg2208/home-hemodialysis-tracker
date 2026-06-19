import { getDb } from '../firestore.js';

export type SessionParams = { from?: string; to?: string; limit?: number };
export type SessionWithReadings = Record<string, unknown> & {
  readings: Record<string, unknown>[];
};

/** Pure: join readings onto sessions, filter by date prefix, newest first, limit. */
export function joinSessions(
  sessions: Record<string, unknown>[],
  readings: Record<string, unknown>[],
  p: SessionParams,
): SessionWithReadings[] {
  const bySession = new Map<string, Record<string, unknown>[]>();
  for (const r of readings) {
    const sid = String(r['session_id']);
    if (!bySession.has(sid)) bySession.set(sid, []);
    bySession.get(sid)!.push(r);
  }
  for (const rs of bySession.values()) {
    rs.sort((a, b) => Number(a['seq'] ?? 0) - Number(b['seq'] ?? 0));
  }

  let out = sessions
    .filter((s) => {
      const date = String(s['date'] ?? '');
      if (p.from && date < p.from) return false;
      if (p.to && date > p.to) return false;
      return true;
    })
    .sort((a, b) => String(b['date'] ?? '').localeCompare(String(a['date'] ?? '')))
    .map((s) => ({ ...s, readings: bySession.get(String(s['session_id'])) ?? [] }));

  if (p.limit != null) out = out.slice(0, p.limit);
  return out;
}

/** I/O: read sessions + readings, then join. */
export async function getSessions(p: SessionParams): Promise<SessionWithReadings[]> {
  const db = getDb();
  const [sessSnap, readSnap] = await Promise.all([
    db.collection('treatment_sessions').get(),
    db.collection('treatment_readings').get(),
  ]);
  const sessions = sessSnap.docs.map((d) => d.data());
  const readings = readSnap.docs.map((d) => d.data());
  return joinSessions(sessions, readings, p);
}
