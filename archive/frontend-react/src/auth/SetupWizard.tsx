import { useState } from 'react';
import { Activity, KeyRound, Save } from 'lucide-react';
import { saveAuth } from './storage';
import type { AuthSettings } from './storage';
import { signInWithCustomToken } from 'firebase/auth';
import { firebaseAuth } from '../lib/firebaseClient';

interface Props {
  onSaved: () => void;
  message?: string;
}

export function SetupWizard({ onSaved, message }: Props) {
  const [mainKey, setMainKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!mainKey.trim()) { setError('Main API key must not be empty.'); return; }

    setBusy(true);
    try {
      // 1. Verify mainKey against /api/health
      const healthRes = await fetch('/api/health', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (healthRes.status === 401) throw new Error('Main API key rejected — check the value and try again.');
      if (!healthRes.ok) throw new Error(`API health check failed (${healthRes.status}).`);

      // 2. Fetch Firebase custom token
      const tokenRes = await fetch('/api/treatment/token', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (tokenRes.status === 401) throw new Error('Main API key rejected by treatment endpoint.');
      if (!tokenRes.ok) throw new Error(`Failed to fetch treatment token (${tokenRes.status}).`);
      const { token, expires_at } = await tokenRes.json() as { token: string; expires_at: number };

      // 3. Sign into Firebase
      await signInWithCustomToken(firebaseAuth, token);

      // 4. Save auth to IndexedDB
      const settings: AuthSettings = {
        mainKey: mainKey.trim(),
        treatmentToken: token,
        treatmentTokenExpiresAt: expires_at,
      };
      await saveAuth(settings);
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-2xl font-bold inline-flex items-center gap-2">
        <Activity size={22} className="text-accent" /> Setup
      </h1>
      {message && (
        <div className="bg-amber-900/40 border border-amber-700 text-amber-200 rounded-lg px-3 py-2 text-sm">
          {message}
        </div>
      )}
      <p className="text-sm text-slate-400">Enter your API key. It is stored on this device only.</p>

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <KeyRound size={14} /> Main API key
        </span>
        <input
          type="password"
          value={mainKey}
          onChange={e => setMainKey(e.target.value)}
          placeholder="long-random-string"
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="none"
          spellCheck={false}
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <button
        type="button"
        onClick={submit}
        disabled={busy}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 disabled:opacity-50 inline-flex items-center justify-center gap-2"
      >
        <Save size={18} /> {busy ? 'Verifying…' : 'Save and continue'}
      </button>

      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
          {error}
        </div>
      )}
    </div>
  );
}
