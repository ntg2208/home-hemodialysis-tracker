import type { ReactNode } from 'react';
import { Loader2 } from 'lucide-react';

interface SaveButtonProps {
  saving: boolean;
  error: string | null;
  onClick: () => void;
  children: ReactNode;
  disabled?: boolean;
  icon?: ReactNode;
}

export function SaveButton({ saving, error, onClick, children, disabled, icon }: SaveButtonProps) {
  return (
    <div className="space-y-2">
      <button
        type="button"
        onClick={onClick}
        disabled={saving || disabled}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 text-lg disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
      >
        {saving ? <><Loader2 size={20} className="animate-spin" /> Saving…</> : <>{icon}{children}</>}
      </button>
      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
          {error} <button type="button" className="underline ml-2" onClick={onClick}>Retry</button>
        </div>
      )}
    </div>
  );
}
