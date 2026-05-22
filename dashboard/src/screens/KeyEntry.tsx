import { useState } from 'react';

type Props = {
  message?: string;
  onSubmit: (key: string) => void;
};

export function KeyEntry({ message, onSubmit }: Props) {
  const [value, setValue] = useState('');

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-900 p-6">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const trimmed = value.trim();
          if (trimmed) onSubmit(trimmed);
        }}
        className="w-full max-w-sm space-y-4"
      >
        <h1 className="text-xl font-semibold text-slate-100">Blood Test Dashboard</h1>
        {message && <p className="text-amber-400 text-sm">{message}</p>}
        <input
          type="password"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="Access key"
          autoFocus
          className="w-full rounded bg-slate-800 px-3 py-2 text-slate-100 outline-none
                     focus:ring-2 focus:ring-cyan-500"
        />
        <button
          type="button"
          onClick={() => {
            const trimmed = value.trim();
            if (trimmed) onSubmit(trimmed);
          }}
          className="w-full rounded bg-cyan-600 px-3 py-2 font-medium text-white
                     hover:bg-cyan-500 disabled:opacity-40"
          disabled={!value.trim()}
        >
          Open dashboard
        </button>
      </form>
    </div>
  );
}
