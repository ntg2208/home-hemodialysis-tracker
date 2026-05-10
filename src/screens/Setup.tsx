import { useState } from 'react';
import { probe, ApiError } from '../api';
import { saveSettings } from '../storage';
import { Settings } from '../schemas';

interface Props { onSaved: (s: Settings) => void; }

export function Setup({ onSaved }: Props) {
  const [url, setUrl] = useState('');
  const [secret, setSecret] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    const parsed = Settings.safeParse({ script_url: url.trim(), shared_secret: secret });
    if (!parsed.success) {
      setError('URL must be a valid URL and secret must not be empty.');
      return;
    }
    setBusy(true);
    try {
      await probe(parsed.data);
      await saveSettings(parsed.data);
      onSaved(parsed.data);
    } catch (e) {
      setError(e instanceof ApiError ? `Probe failed: ${e.code}` : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-2xl font-bold">Setup</h1>
      <p className="text-sm text-slate-400">Paste your Apps Script /exec URL and the shared secret. They are stored on this device only.</p>

      <label className="block">
        <span className="block text-sm text-slate-400 mb-1">Script URL</span>
        <input
          type="url"
          value={url}
          onChange={e => setUrl(e.target.value)}
          placeholder="https://script.google.com/macros/s/.../exec"
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <label className="block">
        <span className="block text-sm text-slate-400 mb-1">Shared secret</span>
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
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 disabled:opacity-50"
      >
        {busy ? 'Verifying…' : 'Save and continue'}
      </button>

      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">{error}</div>
      )}
    </div>
  );
}
