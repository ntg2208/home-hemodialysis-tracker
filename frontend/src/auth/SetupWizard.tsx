import { useState } from 'react';
import { Activity, KeyRound, Link2, Save } from 'lucide-react';
import { saveAuth } from './storage';
import type { AuthSettings } from './storage';

interface Props {
  onSaved: () => void;
  message?: string;
}

async function probeAppsScript(url: string, secret: string): Promise<void> {
  let res: Response;
  try {
    res = await fetch(`${url}?secret=${encodeURIComponent(secret)}`);
  } catch {
    throw new Error('Could not reach the Apps Script URL. Check the URL and try again.');
  }
  let body: unknown;
  try { body = await res.json(); } catch {
    throw new Error('Apps Script returned non-JSON. Check the deployment access setting (must be "Anyone").');
  }
  const b = body as Record<string, unknown>;
  if (b.ok === false) throw new Error(`Apps Script rejected the secret: ${String(b.error)}`);
  if (b.ok !== true) throw new Error('Apps Script returned an unexpected response.');
}

export function SetupWizard({ onSaved, message }: Props) {
  const [mainKey, setMainKey] = useState('');
  const [url, setUrl] = useState('');
  const [secret, setSecret] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!mainKey.trim()) { setError('Main API key must not be empty.'); return; }

    let parsedUrl: URL;
    try { parsedUrl = new URL(url.trim()); }
    catch { setError('Apps Script URL must be a valid URL.'); return; }
    if (!secret.trim()) { setError('Apps Script secret must not be empty.'); return; }

    setBusy(true);
    try {
      // Probe the main key against /api/blood-tests (cheap: returns 0 rows for a far-future to date)
      const apiRes = await fetch('/api/blood-tests?to=1900-01-01', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (apiRes.status === 401) throw new Error('Main API key rejected — check the value and try again.');
      if (!apiRes.ok) throw new Error(`/api/blood-tests returned ${apiRes.status}. Is the API running?`);

      // Probe the Apps Script
      await probeAppsScript(parsedUrl.toString(), secret.trim());

      const settings: AuthSettings = {
        mainKey: mainKey.trim(),
        appsScriptUrl: parsedUrl.toString(),
        appsScriptSecret: secret.trim(),
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
      <p className="text-sm text-slate-400">Enter three values. They are stored on this device only, never sent to any third party.</p>

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
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <Link2 size={14} /> Apps Script URL
        </span>
        <input
          type="url"
          value={url}
          onChange={e => setUrl(e.target.value)}
          placeholder="https://script.google.com/macros/s/.../exec"
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <KeyRound size={14} /> Apps Script secret
        </span>
        <input
          type="password"
          value={secret}
          onChange={e => setSecret(e.target.value)}
          autoComplete="off"
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
