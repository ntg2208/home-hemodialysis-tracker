import { getDb } from '../firestore.js';

/// Average session count of the patient's last 6 replaced PAKs, sorted by
/// recency — null when there's no history yet (client falls back to a default).
export function averagePakLifespan(
  docs: { data: () => { sessions?: number; replaced_at?: string } }[],
): number | null {
  const lifespans = docs
    .map((d) => d.data())
    .filter(
      (d): d is { sessions: number; replaced_at: string } =>
        typeof d.sessions === 'number' && d.sessions > 0 && typeof d.replaced_at === 'string',
    )
    .sort((a, b) => b.replaced_at.localeCompare(a.replaced_at))
    .slice(0, 6)
    .map((d) => d.sessions);
  if (lifespans.length === 0) return null;
  return lifespans.reduce((a, b) => a + b, 0) / lifespans.length;
}

export async function getInventory() {
  const db = getDb();
  const [stockSnap, cycleDoc, pakDoc, pakHistorySnap] = await Promise.all([
    db.collection('inventory_stock').get(),
    db.collection('inventory_config').doc('cycle').get(),
    db.collection('inventory_config').doc('pak').get(),
    db.collection('pak_history').get(),
  ]);

  const stock: Record<string, number> = {};
  for (const doc of stockSnap.docs) {
    const d = doc.data() as { qty: number };
    if (typeof d.qty === 'number') stock[doc.id] = d.qty;
  }

  const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;
  const pakData = pakDoc.exists ? (pakDoc.data() as { installed_at?: string }) : null;
  const pak_installed_at = pakData?.installed_at ?? null;

  let pak_sessions = 0;
  if (pak_installed_at) {
    const sessionsSnap = await db.collection('treatment_sessions')
      .where('date', '>=', pak_installed_at)
      .get();
    pak_sessions = sessionsSnap.docs.length;
  }

  const pak_avg_sessions = averagePakLifespan(pakHistorySnap.docs);
  return { stock, cycle, pak_installed_at, pak_sessions, pak_avg_sessions };
}
