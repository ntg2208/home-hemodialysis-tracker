const KEY = 'blood-dashboard-access-key';

export function getKey(): string | null {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function setKey(value: string): void {
  try {
    localStorage.setItem(KEY, value);
  } catch {
    /* storage unavailable — key simply won't persist */
  }
}

export function clearKey(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* no-op */
  }
}
