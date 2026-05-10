import type { Session } from '../schemas';

interface Props { session: Session; }

export function SessionListItem({ session }: Props) {
  const preBp = session.pre_bp_sys && session.pre_bp_dia ? `${session.pre_bp_sys}/${session.pre_bp_dia}` : '—';
  const postBp = session.post_bp_sys && session.post_bp_dia ? `${session.post_bp_sys}/${session.post_bp_dia}` : '—';
  const totalUf = session.total_uf != null ? `${session.total_uf} L` : '—';

  return (
    <div className="bg-panel border border-slate-700 rounded-lg px-4 py-3 flex items-center justify-between">
      <div>
        <div className="font-mono text-sm text-slate-300">{session.session_id}</div>
        <div className="text-xs text-slate-500">BP {preBp} → {postBp}</div>
      </div>
      <div className="text-sm text-slate-400">{totalUf}</div>
    </div>
  );
}
