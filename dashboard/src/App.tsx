import { useEffect, useState } from 'react';
import { getKey, setKey, clearKey } from './storage';
import { fetchAll, ApiError } from './api';
import type { BloodTestRow } from './schemas';
import { KeyEntry } from './screens/KeyEntry';
import { Dashboard } from './screens/Dashboard';

type State =
  | { status: 'key-entry'; message?: string }
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; rows: BloodTestRow[] };

export default function App() {
  const [state, setState] = useState<State>(
    getKey() ? { status: 'loading' } : { status: 'key-entry' },
  );

  async function load() {
    const key = getKey();
    if (!key) {
      setState({ status: 'key-entry' });
      return;
    }
    setState({ status: 'loading' });
    try {
      const { rows } = await fetchAll(key);
      setState({ status: 'ready', rows });
    } catch (e) {
      if (e instanceof ApiError && e.code === 'unauthorized') {
        clearKey();
        setState({ status: 'key-entry', message: 'Access key rejected — please re-enter.' });
      } else {
        setState({ status: 'error', message: e instanceof Error ? e.message : 'Unknown error.' });
      }
    }
  }

  useEffect(() => {
    if (getKey()) void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (state.status === 'key-entry') {
    return (
      <KeyEntry
        message={state.message}
        onSubmit={(k) => {
          setKey(k);
          void load();
        }}
      />
    );
  }

  if (state.status === 'loading') {
    return <div className="min-h-screen bg-slate-900 p-8 text-slate-400">Loading…</div>;
  }

  if (state.status === 'error') {
    return (
      <div className="min-h-screen bg-slate-900 p-8 text-center">
        <p className="mb-4 text-red-400">{state.message}</p>
        <button
          type="button"
          onClick={() => void load()}
          className="rounded bg-cyan-600 px-4 py-2 font-medium text-white hover:bg-cyan-500"
        >
          Retry
        </button>
      </div>
    );
  }

  return <Dashboard rows={state.rows} />;
}
