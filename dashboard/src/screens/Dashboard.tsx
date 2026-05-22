import type { BloodTestRow } from '../schemas';

export function Dashboard({ rows }: { rows: BloodTestRow[] }) {
  return (
    <div className="min-h-screen bg-slate-900 p-8 text-slate-100">
      {rows.length} rows loaded
    </div>
  );
}
