interface NumberFieldProps {
  label: string;
  value: number | '' | undefined;
  onChange: (v: number | undefined) => void;
  step?: string;
  min?: number;
  required?: boolean;
}

export function NumberField({ label, value, onChange, step = 'any', min, required }: NumberFieldProps) {
  return (
    <label className="block">
      <span className="block text-sm text-slate-400 mb-1">
        {label}{required && <span className="text-red-400"> *</span>}
      </span>
      <input
        type="number"
        inputMode="decimal"
        step={step}
        min={min}
        required={required}
        value={value ?? ''}
        onChange={e => {
          const raw = e.target.value;
          if (raw === '') onChange(undefined);
          else {
            const n = Number(raw);
            onChange(Number.isFinite(n) ? n : undefined);
          }
        }}
        className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-lg focus:border-accent focus:outline-none"
      />
    </label>
  );
}
