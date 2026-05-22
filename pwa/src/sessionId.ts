export function nextSessionId(date: string, existingIds: readonly string[]): string {
  const sameDay = existingIds.filter(id => id === date || id.startsWith(`${date}-`));
  if (sameDay.length === 0) return date;

  let maxN = 1;
  for (const id of sameDay) {
    if (id === date) {
      maxN = Math.max(maxN, 1);
    } else {
      const suffix = id.slice(date.length + 1);
      const n = parseInt(suffix, 10);
      if (Number.isFinite(n)) maxN = Math.max(maxN, n);
    }
  }
  return `${date}-${maxN + 1}`;
}

export function todayIso(now: Date = new Date()): string {
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

export function nowHHMM(now: Date = new Date()): string {
  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}
