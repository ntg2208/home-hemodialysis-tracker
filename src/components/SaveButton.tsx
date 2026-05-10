import type { ReactNode } from 'react';

interface SaveButtonProps {
  saving: boolean;
  error: string | null;
  onClick: () => void;
  children: ReactNode;
  disabled?: boolean;
}

export function SaveButton({ saving, error, onClick, children, disabled }: SaveButtonProps) {
  return (
    <div className="space-y-2">
      <button
        type="button"
        onClick={onClick}
        disabled={saving || disabled}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 text-lg disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {saving ? 'Saving…' : children}
      </button>
      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
          {error} <button className="underline ml-2" onClick={onClick}>Retry</button>
        </div>
      )}
    </div>
  );
}
