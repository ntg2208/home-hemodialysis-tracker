# Material You Light Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current dark navy/cyan theme with M3 light mode: white surfaces, deep-teal primary, scale-fade screen transitions, tonal pill nav indicator, outline icons, bottom-sheet modal.

**Architecture:** Tailwind config gets 13 M3 tokens replacing the 3 existing ones. CSS adds three keyframe animations. Every screen component gains a `screen-enter` class that fires automatically on mount. No new runtime dependencies.

**Tech Stack:** React 18, TypeScript, Tailwind CSS, Vite, lucide-react, Vitest

**Spec:** `docs/superpowers/2026-06-03-material-you-light-mode.md`

**Working directory for all commands:** `frontend/`

---

## Task 1: Color tokens

**Files:**
- Modify: `frontend/tailwind.config.js`

- [ ] **Replace the three existing color tokens with 13 M3 tokens**

```js
// frontend/tailwind.config.js
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg:                    '#fafdfe',
        panel:                 '#ffffff',
        'surface-container':   '#e8f7f9',
        primary:               '#006874',
        'primary-container':   '#97f0ff',
        'on-primary':          '#ffffff',
        'on-primary-container':'#001f24',
        'on-surface':          '#191c1d',
        'on-surface-variant':  '#3f484a',
        outline:               '#6f797a',
        'outline-variant':     '#dbe4e6',
        tertiary:              '#2e7d32',
        warning:               '#e65100',
        error:                 '#b71c1c',
      },
    },
  },
  plugins: [],
};
```

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

Expected: no errors (class names don't affect TypeScript).

- [ ] **Commit**

```bash
git add frontend/tailwind.config.js
git commit -m "feat: replace dark color tokens with M3 light palette"
```

---

## Task 2: CSS keyframes + body

**Files:**
- Modify: `frontend/src/index.css`

- [ ] **Replace the file contents**

```css
/* frontend/src/index.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --kb: 0px;
}

body {
  @apply bg-bg text-on-surface min-h-screen;
}

/* Modal overlays: shrink to end at keyboard top */
.kb-overlay {
  bottom: var(--kb) !important;
}

/* Main scroll area */
.main-scroll {
  padding-bottom: max(4rem, var(--kb));
}
@media (min-width: 768px) {
  .main-scroll {
    padding-bottom: 0;
  }
}

/* ── Screen transition: scale-fade (M3 standard) ── */
@keyframes screen-enter-kf {
  from { opacity: 0; transform: scale(1.04); }
  to   { opacity: 1; transform: scale(1); }
}
.screen-enter {
  animation: screen-enter-kf 280ms cubic-bezier(0.2, 0, 0, 1) both;
}

/* ── Bottom sheet: slide up ── */
@keyframes sheet-up-kf {
  from { transform: translateY(100%); }
  to   { transform: translateY(0); }
}
.sheet-enter {
  animation: sheet-up-kf 300ms ease-out both;
}

/* ── Backdrop: fade in ── */
@keyframes backdrop-in-kf {
  from { opacity: 0; }
  to   { opacity: 1; }
}
.backdrop-enter {
  animation: backdrop-in-kf 250ms ease-out both;
}
```

- [ ] **Run typecheck + tests**

```bash
cd frontend && npm run typecheck && npm test
```

Expected: typecheck passes, all existing tests pass (tests cover logic, not class names).

- [ ] **Commit**

```bash
git add frontend/src/index.css
git commit -m "feat: add M3 screen-enter, sheet-up, backdrop-in keyframes"
```

---

## Task 3: AppShell — tonal nav pill

**Files:**
- Modify: `frontend/src/components/AppShell.tsx`

The bottom nav needs a tonal pill (`bg-primary-container`) behind the active icon. `NavLink`'s `children` accepts a render function that receives `{ isActive }`, which lets us conditionally render the pill without needing `useLocation`.

- [ ] **Replace AppShell.tsx**

```tsx
// frontend/src/components/AppShell.tsx
import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { Activity, FlaskConical, BookOpen, Package, Dumbbell, MessageSquare } from 'lucide-react';
import { clearAuth } from '../auth/storage';
import { useKeyboardAvoidance } from '../hooks/useKeyboardAvoidance';
import { ErrorBoundary } from './ErrorBoundary';

const TABS = [
  { to: '/treatment', label: 'Treatment', Icon: Activity },
  { to: '/blood-tests', label: 'Tests', Icon: FlaskConical },
  { to: '/kb', label: 'KB', Icon: BookOpen },
  { to: '/inventory', label: 'Inv', Icon: Package },
  { to: '/fitness', label: 'Fitness', Icon: Dumbbell },
  { to: '/chat', label: 'Chat', Icon: MessageSquare },
];

export function AppShell() {
  const navigate = useNavigate();
  useKeyboardAvoidance();

  async function handleResetAuth() {
    if (!confirm('Clear all saved credentials on this device?')) return;
    await clearAuth();
    navigate('/setup');
  }

  return (
    <div className="flex flex-col min-h-screen bg-bg">
      {/* Top bar (desktop) */}
      <nav className="hidden md:flex items-center border-b border-outline-variant bg-panel px-4 gap-1">
        <span className="text-sm font-semibold text-on-surface-variant mr-4">Home HD</span>
        {TABS.map(({ to, label }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              `px-3 py-2 text-xs transition-colors ${
                isActive ? 'text-primary font-semibold' : 'text-outline hover:text-on-surface-variant'
              }`
            }
          >
            {label}
          </NavLink>
        ))}
        <button
          type="button"
          onClick={handleResetAuth}
          className="ml-auto text-xs text-outline hover:text-on-surface-variant py-2"
        >
          Settings
        </button>
      </nav>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto main-scroll">
        <ErrorBoundary>
          <Outlet />
        </ErrorBoundary>
      </main>

      {/* Bottom tab bar (mobile) */}
      <nav className="fixed bottom-0 left-0 right-0 flex md:hidden border-t border-outline-variant bg-panel safe-area-inset-bottom">
        {TABS.map(({ to, label, Icon }) => (
          <NavLink
            key={to}
            to={to}
            className="flex-1 flex flex-col items-center gap-0.5 py-2 text-xs"
          >
            {({ isActive }) => (
              <>
                <span
                  className={`flex items-center justify-center w-10 h-6 rounded-xl transition-colors ${
                    isActive ? 'bg-primary-container' : ''
                  }`}
                >
                  <Icon
                    size={18}
                    className={isActive ? 'text-on-primary-container' : 'text-outline'}
                  />
                </span>
                <span className={isActive ? 'text-primary font-semibold' : 'text-outline'}>
                  {label}
                </span>
              </>
            )}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
```

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

Expected: no errors.

- [ ] **Commit**

```bash
git add frontend/src/components/AppShell.tsx
git commit -m "feat: M3 tonal pill on active nav tab"
```

---

## Task 4: Shared Treatment components

**Files:**
- Modify: `frontend/src/routes/Treatment/components/NumberField.tsx`
- Modify: `frontend/src/routes/Treatment/components/SaveButton.tsx`
- Modify: `frontend/src/routes/Treatment/components/SessionListItem.tsx`

- [ ] **Replace NumberField.tsx**

```tsx
// frontend/src/routes/Treatment/components/NumberField.tsx
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
      <span className="block text-xs font-semibold text-on-surface-variant mb-1">
        {label}{required && <span className="text-error"> *</span>}
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
        className="w-full bg-bg border border-outline rounded-xl px-3 py-2 text-lg text-on-surface focus:border-primary focus:outline-none"
      />
    </label>
  );
}
```

- [ ] **Replace SaveButton.tsx**

```tsx
// frontend/src/routes/Treatment/components/SaveButton.tsx
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
        className="w-full bg-primary text-on-primary font-semibold rounded-full py-3 text-base disabled:opacity-40 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
      >
        {saving ? <><Loader2 size={20} className="animate-spin" /> Saving…</> : <>{icon}{children}</>}
      </button>
      {error && (
        <div className="bg-red-50 border border-error text-error rounded-xl px-3 py-2 text-sm">
          {error} <button type="button" className="underline ml-2" onClick={onClick}>Retry</button>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Replace SessionListItem.tsx**

```tsx
// frontend/src/routes/Treatment/components/SessionListItem.tsx
import { CalendarDays, Droplets } from 'lucide-react';
import type { Session } from '../schemas';

interface Props { session: Session; }

export function SessionListItem({ session }: Props) {
  const preBp = session.pre_bp_sys && session.pre_bp_dia ? `${session.pre_bp_sys}/${session.pre_bp_dia}` : '—';
  const postBp = session.post_bp_sys && session.post_bp_dia ? `${session.post_bp_sys}/${session.post_bp_dia}` : '—';
  const totalUf = session.total_uf != null ? `${session.total_uf}` : '—';

  return (
    <div className="bg-panel border border-outline-variant rounded-2xl px-4 py-3 flex items-center justify-between gap-3 shadow-sm">
      <CalendarDays size={20} className="text-outline shrink-0" />
      <div className="flex-1 min-w-0">
        <div className="font-mono text-sm text-on-surface font-semibold">{session.session_id}</div>
        <div className="text-xs text-outline">BP {preBp} → {postBp}</div>
      </div>
      <div className="text-sm text-primary font-semibold inline-flex items-center gap-1">
        <Droplets size={14} /> {totalUf}
      </div>
    </div>
  );
}
```

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

- [ ] **Commit**

```bash
git add frontend/src/routes/Treatment/components/NumberField.tsx \
        frontend/src/routes/Treatment/components/SaveButton.tsx \
        frontend/src/routes/Treatment/components/SessionListItem.tsx
git commit -m "feat: M3 light mode styling for shared Treatment components"
```

---

## Task 5: AddReadingModal — bottom sheet

**Files:**
- Modify: `frontend/src/routes/Treatment/components/AddReadingModal.tsx`

The overlay switches from a centered dialog to a bottom sheet. The backdrop fades in (`backdrop-enter`). The panel slides up from the screen bottom (`sheet-enter`). A visual drag handle appears at the top of the sheet.

- [ ] **Replace AddReadingModal.tsx**

```tsx
// frontend/src/routes/Treatment/components/AddReadingModal.tsx
import { useState } from 'react';
import { X } from 'lucide-react';
import { NumberField } from './NumberField';
import { SaveButton } from './SaveButton';
import { ApiError } from '../api';
import type { Reading } from '../schemas';
import { nowHHMM } from '../sessionId';

interface Props {
  sessionId: string;
  seq: number;
  defaultBloodFlow?: number;
  onSave: (reading: Reading) => Promise<void>;
  onClose: () => void;
}

interface FormState {
  time: string;
  bp_sys?: number;
  bp_dia?: number;
  pulse?: number;
  blood_flow?: number;
  venous_pressure?: number;
  arterial_pressure?: number;
  note?: string;
}

export function AddReadingModal({ sessionId, seq, defaultBloodFlow, onSave, onClose }: Props) {
  // Lock seq at mount: nextSeq in the parent advances as soon as persist()
  // prepends the new reading, which would flip this header from #N to #N+1 mid-save.
  const [lockedSeq] = useState(seq);
  const [form, setForm] = useState<FormState>({ time: nowHHMM(), blood_flow: defaultBloodFlow });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  async function submit() {
    setError(null);
    setSaving(true);
    const reading: Reading = {
      reading_id: `${sessionId}-r${lockedSeq}`,
      session_id: sessionId,
      seq: lockedSeq,
      ...form,
    };
    try {
      await onSave(reading);
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="kb-overlay backdrop-enter fixed inset-0 bg-black/25 flex items-end z-50">
      <div className="sheet-enter bg-panel rounded-t-3xl w-full max-h-[85vh] overflow-y-auto px-4 pt-3 pb-8 space-y-3 shadow-xl">
        {/* Drag handle */}
        <div className="w-10 h-1 bg-outline-variant rounded-full mx-auto mb-2" />

        <header className="flex items-center justify-between">
          <h2 className="text-base font-bold text-on-surface">Reading #{lockedSeq}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-outline hover:text-on-surface-variant p-1"
          >
            <X size={20} />
          </button>
        </header>

        <label className="block">
          <span className="block text-xs font-semibold text-on-surface-variant mb-1">Time</span>
          <input
            type="time"
            value={form.time}
            onChange={e => update('time', e.target.value)}
            className="w-full bg-bg border border-outline rounded-xl px-3 py-2 text-lg text-on-surface focus:border-primary focus:outline-none"
          />
        </label>

        <div className="grid grid-cols-2 gap-3">
          <NumberField label="BP sys" value={form.bp_sys} onChange={v => update('bp_sys', v)} step="1" />
          <NumberField label="BP dia" value={form.bp_dia} onChange={v => update('bp_dia', v)} step="1" />
          <NumberField label="Pulse" value={form.pulse} onChange={v => update('pulse', v)} step="1" />
          <NumberField label="Blood flow" value={form.blood_flow} onChange={v => update('blood_flow', v)} step="1" />
          <NumberField label="VP" value={form.venous_pressure} onChange={v => update('venous_pressure', v)} step="1" />
          <NumberField label="AP" value={form.arterial_pressure} onChange={v => update('arterial_pressure', v)} step="1" />
        </div>

        <label className="block">
          <span className="block text-xs font-semibold text-on-surface-variant mb-1">Note</span>
          <input
            type="text"
            value={form.note ?? ''}
            onChange={e => update('note', e.target.value || undefined)}
            className="w-full bg-bg border border-outline rounded-xl px-3 py-2 text-base text-on-surface focus:border-primary focus:outline-none"
          />
        </label>

        <SaveButton saving={saving} error={error} onClick={submit}>Save reading</SaveButton>
      </div>
    </div>
  );
}
```

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

- [ ] **Commit**

```bash
git add frontend/src/routes/Treatment/components/AddReadingModal.tsx
git commit -m "feat: AddReadingModal becomes M3 bottom sheet"
```

---

## Task 6: Treatment screens

**Files:**
- Modify: `frontend/src/routes/Treatment/screens/Home.tsx`
- Modify: `frontend/src/routes/Treatment/screens/PreTreatment.tsx`
- Modify: `frontend/src/routes/Treatment/screens/ActiveSession.tsx`
- Modify: `frontend/src/routes/Treatment/screens/PostTreatment.tsx`

Each screen root div gets `screen-enter` so the scale-fade fires on every state transition. Fill is stripped from Play and Square icons. Color tokens updated throughout.

- [ ] **Replace Home.tsx**

```tsx
// frontend/src/routes/Treatment/screens/Home.tsx
import { useEffect, useState } from 'react';
import { Activity, CalendarDays, Check, Pencil, Play, RefreshCw, X } from 'lucide-react';
import { getAll, ApiError } from '../api';
import {
  getCachedSessions,
  getDriedWeight,
  saveCachedSessions,
  saveDriedWeight,
} from '../storage';
import type { Session } from '../schemas';
import { SessionListItem } from '../components/SessionListItem';

interface Props {
  onStartSession: (existingIds: string[]) => void;
}

export function Home({ onStartSession }: Props) {
  const [sessions, setSessions] = useState<Session[] | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [driedWeight, setDriedWeight] = useState<number | null>(null);
  const [editingDried, setEditingDried] = useState(false);
  const [driedDraft, setDriedDraft] = useState('');

  useEffect(() => {
    getDriedWeight().then(setDriedWeight).catch(() => setDriedWeight(59));
  }, []);

  function startEditDried() {
    setDriedDraft(driedWeight != null ? String(driedWeight) : '');
    setEditingDried(true);
  }

  async function commitDried() {
    const n = Number(driedDraft);
    if (!Number.isFinite(n) || n <= 0) { setEditingDried(false); return; }
    setDriedWeight(n);
    setEditingDried(false);
    saveDriedWeight(n).catch(() => {});
  }

  async function load() {
    setError(null);
    setRefreshing(true);
    try {
      const r = await getAll();
      const sorted = [...r.sessions].sort((a, b) => b.date.localeCompare(a.date));
      setSessions(sorted);
      saveCachedSessions(sorted).catch(() => {});
    } catch (e) {
      setError(e instanceof ApiError ? `Load failed: ${e.code}` : String(e));
    } finally {
      setRefreshing(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    getCachedSessions()
      .then(cached => { if (!cancelled && cached && sessions === null) setSessions(cached); })
      .catch(() => {})
      .finally(() => { if (!cancelled) load(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const ids = sessions?.map(s => s.session_id) ?? [];

  return (
    <div className="screen-enter p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold inline-flex items-center gap-2">
          <Activity size={24} className="text-primary" /> Treatment
        </h1>
      </header>

      <button
        type="button"
        onClick={() => onStartSession(ids)}
        disabled={sessions === null}
        className="w-full bg-primary text-on-primary font-semibold rounded-full py-4 text-lg disabled:opacity-40 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
      >
        <Play size={22} /> Start session
      </button>

      <div className="bg-panel border border-outline-variant rounded-2xl px-3 py-2 flex items-center justify-between gap-3 shadow-sm">
        <span className="text-sm text-on-surface-variant">Dried weight</span>
        {editingDried ? (
          <div className="flex items-center gap-2">
            <input
              type="number"
              inputMode="decimal"
              step="any"
              autoFocus
              value={driedDraft}
              onChange={e => setDriedDraft(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter') commitDried();
                if (e.key === 'Escape') setEditingDried(false);
              }}
              className="w-20 bg-bg border border-outline rounded-xl px-2 py-1 text-right text-on-surface focus:border-primary focus:outline-none"
            />
            <span className="text-sm text-outline">kg</span>
            <button type="button" onClick={commitDried} aria-label="Save" className="text-primary hover:opacity-80 p-1">
              <Check size={18} />
            </button>
            <button type="button" onClick={() => setEditingDried(false)} aria-label="Cancel" className="text-outline hover:text-on-surface-variant p-1">
              <X size={18} />
            </button>
          </div>
        ) : (
          <button type="button" onClick={startEditDried} className="inline-flex items-center gap-2 text-on-surface hover:text-primary">
            <span className="font-semibold">{driedWeight != null ? `${driedWeight} kg` : '—'}</span>
            <Pencil size={14} className="text-outline" />
          </button>
        )}
      </div>

      <section className="space-y-2">
        <h2 className="text-xs font-bold uppercase tracking-wide text-on-surface-variant inline-flex items-center justify-between w-full">
          <span className="inline-flex items-center gap-2">
            <CalendarDays size={14} /> Recent sessions
          </span>
          {refreshing && sessions !== null && (
            <span className="inline-flex items-center gap-1 normal-case tracking-normal text-outline">
              <RefreshCw size={12} className="animate-spin" /> refreshing
            </span>
          )}
        </h2>
        {error && (
          <div className="bg-red-50 border border-error text-error rounded-xl px-3 py-2 text-sm">
            {error} <button type="button" className="underline ml-2" onClick={load}>Retry</button>
          </div>
        )}
        {!sessions && !error && <div className="text-outline text-sm">Loading…</div>}
        {sessions && sessions.length === 0 && <div className="text-outline text-sm">No sessions yet.</div>}
        {sessions?.slice(0, 5).map(s => <SessionListItem key={s.session_id} session={s} />)}
      </section>
    </div>
  );
}
```

- [ ] **Replace PreTreatment.tsx**

```tsx
// frontend/src/routes/Treatment/screens/PreTreatment.tsx
import { useEffect, useState } from 'react';
import { ClipboardList, Play, X } from 'lucide-react';
import { ApiError, saveSession } from '../api';
import { getDriedWeight, getLastSession, saveLastSession } from '../storage';
import { nextSessionId, todayIso } from '../sessionId';
import { NumberField } from '../components/NumberField';
import { SaveButton } from '../components/SaveButton';
import { cloudGet } from '../../../api/cloudRun';
import type { Session } from '../schemas';
import type { AuthSettings } from '../../../auth/storage';

interface Props {
  auth: AuthSettings | null;
  existingIds: string[];
  onSaved: (session: Session, heparinUsed: boolean) => void;
  onCancel: () => void;
}

interface FormState {
  pre_weight?: number;
  uf_goal?: number;
  uf_rate?: number;
  pre_bp_sys?: number;
  pre_bp_dia?: number;
  pre_pulse?: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export function PreTreatment({ auth, existingIds, onSaved, onCancel }: Props) {
  const [form, setForm] = useState<FormState>({});
  const [goalTouched, setGoalTouched] = useState(false);
  const [rateTouched, setRateTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [driedWeight, setDriedWeight] = useState<number | null>(null);
  const [heparinUsed, setHeparinUsed] = useState(true);
  const [heparinStock, setHeparinStock] = useState<number | null>(null);

  useEffect(() => {
    getLastSession().catch(() => {});
    getDriedWeight().then(setDriedWeight).catch(() => setDriedWeight(59));
  }, []);

  useEffect(() => {
    if (!auth) return;
    cloudGet<{ stock: Record<string, number> }>(auth, '/api/inventory')
      .then(data => setHeparinStock(data.stock['heparin'] ?? 0))
      .catch(() => {});
  }, [auth]);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  const derivedGoal =
    form.pre_weight != null && driedWeight != null
      ? round2(form.pre_weight - driedWeight)
      : undefined;
  const effectiveGoal = goalTouched ? form.uf_goal : derivedGoal;
  const derivedRate =
    effectiveGoal != null ? round2(effectiveGoal / 0.004) : undefined;
  const effectiveRate = rateTouched ? form.uf_rate : derivedRate;

  const ready = form.pre_weight != null && effectiveGoal != null && form.pre_bp_sys != null && form.pre_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    const date = todayIso();
    const session_id = nextSessionId(date, existingIds);
    const session: Session = {
      session_id,
      date,
      ...form,
      uf_goal: effectiveGoal,
      uf_rate: effectiveRate,
    };
    try {
      await saveSession(session);
      saveLastSession(session).catch(() => {});
      onSaved(session, heparinUsed);
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="screen-enter p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold inline-flex items-center gap-2">
          <ClipboardList size={20} className="text-primary" /> Pre-treatment
        </h1>
        <button
          type="button"
          onClick={onCancel}
          aria-label="Cancel"
          className="text-outline hover:text-on-surface-variant p-1"
        >
          <X size={20} />
        </button>
      </header>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Weight (kg)" value={form.pre_weight} onChange={v => update('pre_weight', v)} required />
        <NumberField
          label="UF goal (L)"
          value={effectiveGoal}
          onChange={v => { setGoalTouched(v != null); update('uf_goal', v); }}
          required
        />
        <NumberField
          label="UF rate"
          value={effectiveRate}
          onChange={v => { setRateTouched(v != null); update('uf_rate', v); }}
        />
        <NumberField label="BP sys" value={form.pre_bp_sys} onChange={v => update('pre_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.pre_bp_dia} onChange={v => update('pre_bp_dia', v)} step="1" required />
        <NumberField label="Pulse" value={form.pre_pulse} onChange={v => update('pre_pulse', v)} step="1" />
      </div>

      <div className="flex items-center justify-between bg-panel border border-outline-variant rounded-2xl px-3 py-2 shadow-sm">
        <div>
          <span className="text-sm text-on-surface font-medium">Heparin</span>
          {heparinStock !== null && (
            <span className="ml-2 text-xs text-outline">{heparinStock} remaining</span>
          )}
        </div>
        <button
          type="button"
          onClick={() => setHeparinUsed(h => !h)}
          className={`px-3 py-1 rounded-full text-xs font-semibold transition-colors ${
            heparinUsed
              ? 'bg-primary-container text-on-primary-container'
              : 'bg-outline-variant text-outline'
          }`}
        >
          {heparinUsed ? 'Used' : 'Not used'}
        </button>
      </div>

      <SaveButton
        saving={saving}
        error={error}
        onClick={submit}
        disabled={!ready}
        icon={<Play size={20} />}
      >
        Start session
      </SaveButton>
    </div>
  );
}
```

- [ ] **Replace ActiveSession.tsx**

```tsx
// frontend/src/routes/Treatment/screens/ActiveSession.tsx
import { useEffect, useRef, useState } from 'react';
import { Activity, AlertCircle, Check, Droplets, Heart, Loader2, Pencil, Plus, Scale, Square, Timer, X } from 'lucide-react';
import { ApiError, saveReading } from '../api';
import { AddReadingModal } from '../components/AddReadingModal';
import type { PendingReading, Reading, Session } from '../schemas';
import type { SessionConsumed } from '../storage';

const DEFAULT_TARGET_MIN = 255;
const NOTIFY_AT_MINS = [120, 60, 5] as const;

interface Props {
  session: Session;
  initialReadings?: PendingReading[];
  initialCountdownStartedAt?: number;
  initialTargetMin?: number;
  onReadingsChange?: (rs: PendingReading[]) => void;
  onCountdownChange?: (startedAt: number | null, targetMin: number) => void;
  onEnd: (consumed: Omit<SessionConsumed, 'heparinUsed'>) => void;
}

function formatRemaining(remainingMs: number): string {
  const overtime = remainingMs < 0;
  const abs = Math.abs(remainingMs);
  const h = Math.floor(abs / 3_600_000);
  const m = Math.floor((abs % 3_600_000) / 60_000);
  const s = Math.floor((abs % 60_000) / 1_000);
  return `${overtime ? '+' : ''}${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatTarget(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function ActiveSession({
  session,
  initialReadings,
  initialCountdownStartedAt,
  initialTargetMin,
  onReadingsChange,
  onCountdownChange,
  onEnd,
}: Props) {
  const sessionId = session.session_id;
  const [readings, setReadings] = useState<PendingReading[]>(initialReadings ?? []);
  const [modalOpen, setModalOpen] = useState(false);
  const [needles, setNeedles] = useState(2);
  const [onOffPacks, setOnOffPacks] = useState(1);

  const [targetMin, setTargetMin] = useState(initialTargetMin ?? DEFAULT_TARGET_MIN);
  const [countdownStartedAt, setCountdownStartedAt] = useState<number | null>(initialCountdownStartedAt ?? null);
  const [editingTarget, setEditingTarget] = useState(false);
  const [editHours, setEditHours] = useState(Math.floor((initialTargetMin ?? DEFAULT_TARGET_MIN) / 60));
  const [editMins, setEditMins] = useState((initialTargetMin ?? DEFAULT_TARGET_MIN) % 60);
  const [inAppAlert, setInAppAlert] = useState<string | null>(null);
  const [, forceUpdate] = useState(0);

  const notifiedRef = useRef<Set<number>>((() => {
    const s = new Set<number>();
    if (initialCountdownStartedAt) {
      const remaining = (initialTargetMin ?? DEFAULT_TARGET_MIN) * 60_000 - (Date.now() - initialCountdownStartedAt);
      for (const mins of NOTIFY_AT_MINS) {
        if (remaining <= mins * 60_000) s.add(mins);
      }
    }
    return s;
  })());

  useEffect(() => {
    if (!countdownStartedAt) return;
    const id = setInterval(() => {
      forceUpdate(n => n + 1);
      const remaining = targetMin * 60_000 - (Date.now() - countdownStartedAt);
      for (const mins of NOTIFY_AT_MINS) {
        if (remaining <= mins * 60_000 && !notifiedRef.current.has(mins)) {
          notifiedRef.current.add(mins);
          const label = mins === 120 ? '2 hours' : mins === 60 ? '1 hour' : '5 minutes';
          triggerAlert(`${label} remaining`);
        }
      }
    }, 1_000);
    return () => clearInterval(id);
  }, [countdownStartedAt, targetMin]);

  useEffect(() => {
    if (!countdownStartedAt) return;
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {});
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [!!countdownStartedAt]);

  function triggerAlert(message: string) {
    setInAppAlert(message);
    if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
    if ('Notification' in window && Notification.permission === 'granted') {
      new Notification('HD Session', { body: message });
    }
  }

  function startEditTarget() {
    setEditHours(Math.floor(targetMin / 60));
    setEditMins(targetMin % 60);
    setEditingTarget(true);
  }

  function commitTarget() {
    const total = editHours * 60 + editMins;
    if (total > 0) setTargetMin(total);
    setEditingTarget(false);
  }

  const onCountdownChangeRef = useRef(onCountdownChange);
  onCountdownChangeRef.current = onCountdownChange;
  const prevCountdownKey = useRef<string>('');
  useEffect(() => {
    const key = `${countdownStartedAt}:${targetMin}`;
    if (key === prevCountdownKey.current) return;
    prevCountdownKey.current = key;
    onCountdownChangeRef.current?.(countdownStartedAt, targetMin);
  }, [countdownStartedAt, targetMin]);

  const firstRender = useRef(true);
  const onChangeRef = useRef(onReadingsChange);
  onChangeRef.current = onReadingsChange;
  useEffect(() => {
    if (firstRender.current) { firstRender.current = false; return; }
    onChangeRef.current?.(readings);
  }, [readings]);

  const nextSeq = readings.length === 0 ? 1 : Math.max(...readings.map(r => r.seq)) + 1;
  const lastBloodFlow = readings.find(r => r.blood_flow != null)?.blood_flow;

  async function persist(reading: Reading): Promise<void> {
    setReadings(rs => {
      const existing = rs.findIndex(r => r.reading_id === reading.reading_id);
      const next: PendingReading = { ...reading, status: 'pending' };
      if (existing >= 0) return rs.map((r, i) => i === existing ? next : r);
      return [next, ...rs];
    });
    if (countdownStartedAt === null) {
      setCountdownStartedAt(Date.now());
    }
    try {
      await saveReading(reading);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'saved' } : r));
    } catch (e) {
      const msg = e instanceof ApiError ? e.code : String(e);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'error', errorMsg: msg } : r));
      throw e;
    }
  }

  async function retry(reading: PendingReading) {
    setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'pending', errorMsg: undefined } : r));
    const { status: _s, errorMsg: _e, ...wire } = reading;
    void _s; void _e;
    try {
      await saveReading(wire);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'saved' } : r));
    } catch (e) {
      const msg = e instanceof ApiError ? e.code : String(e);
      setReadings(rs => rs.map(r => r.reading_id === reading.reading_id ? { ...r, status: 'error', errorMsg: msg } : r));
    }
  }

  const sorted = [...readings].sort((a, b) => b.seq - a.seq);

  const targetMs = targetMin * 60_000;
  const remainingMs = countdownStartedAt ? targetMs - (Date.now() - countdownStartedAt) : targetMs;
  const overtime = remainingMs < 0;
  const timerColor = !countdownStartedAt
    ? 'text-outline'
    : overtime
      ? 'text-warning'
      : remainingMs <= 5 * 60_000
        ? 'text-error'
        : remainingMs <= 10 * 60_000
          ? 'text-warning'
          : 'text-tertiary';

  return (
    <div className="screen-enter p-4 max-w-md mx-auto space-y-4">
      {/* In-app alert banner */}
      {inAppAlert && (
        <div className="fixed top-0 left-0 right-0 z-50 bg-amber-50 border-b border-amber-300 px-4 py-3 flex items-center justify-between">
          <span className="text-amber-800 text-sm font-semibold">{inAppAlert}</span>
          <button type="button" onClick={() => setInAppAlert(null)} className="text-amber-600 hover:text-amber-800 ml-4">
            <X size={16} />
          </button>
        </div>
      )}

      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold inline-flex items-center gap-2">
          <Activity size={20} className="text-primary" />
          Session <span className="font-mono text-base text-on-surface-variant">{sessionId}</span>
        </h1>
        <button
          type="button"
          onClick={() => onEnd({ needles, onOffPacks, durationMin: countdownStartedAt ? Math.round((Date.now() - countdownStartedAt) / 60_000) : undefined })}
          className="text-sm text-error font-semibold inline-flex items-center gap-1"
        >
          <Square size={14} /> End
        </button>
      </header>

      {/* Pre-values reference */}
      <div className="bg-surface-container border border-outline-variant rounded-2xl px-3 py-2 text-sm grid grid-cols-2 gap-x-4 gap-y-1">
        <div className="inline-flex items-center gap-2">
          <Scale size={14} className="text-outline" />
          <span className="text-on-surface-variant">Weight</span>
          <span className="text-on-surface font-semibold ml-auto">{session.pre_weight ?? '–'} kg</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Droplets size={14} className="text-primary" />
          <span className="text-on-surface-variant">UF goal</span>
          <span className="text-primary font-semibold ml-auto">{session.uf_goal ?? '–'} L</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Heart size={14} className="text-error" />
          <span className="text-on-surface-variant">BP</span>
          <span className="text-on-surface font-semibold ml-auto">{session.pre_bp_sys ?? '–'}/{session.pre_bp_dia ?? '–'}</span>
        </div>
        <div className="inline-flex items-center gap-2">
          <Activity size={14} className="text-tertiary" />
          <span className="text-on-surface-variant">Pulse</span>
          <span className="text-tertiary font-semibold ml-auto">{session.pre_pulse ?? '–'}</span>
        </div>
      </div>

      {/* Countdown */}
      <div className="bg-panel border border-outline-variant rounded-2xl px-3 py-2 flex items-center justify-between gap-3 shadow-sm">
        <div className="inline-flex items-center gap-2">
          <Timer size={16} className={timerColor} />
          {countdownStartedAt ? (
            <span className={`font-mono text-xl font-semibold ${timerColor}`}>
              {formatRemaining(remainingMs)}
            </span>
          ) : (
            <span className="text-outline text-sm">Waiting for first reading</span>
          )}
        </div>
        {editingTarget ? (
          <div className="inline-flex items-center gap-1">
            <input
              type="number"
              min="0"
              max="23"
              value={editHours}
              onChange={e => setEditHours(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-10 bg-bg border border-outline rounded-lg px-1 py-0.5 text-sm text-center text-on-surface focus:border-primary focus:outline-none"
            />
            <span className="text-on-surface-variant text-sm">h</span>
            <input
              type="number"
              min="0"
              max="59"
              value={editMins}
              onChange={e => setEditMins(Math.max(0, Math.min(59, parseInt(e.target.value, 10) || 0)))}
              className="w-10 bg-bg border border-outline rounded-lg px-1 py-0.5 text-sm text-center text-on-surface focus:border-primary focus:outline-none"
            />
            <span className="text-on-surface-variant text-sm">m</span>
            <button type="button" onClick={commitTarget} className="text-primary hover:opacity-80 p-1">
              <Check size={16} />
            </button>
            <button type="button" onClick={() => setEditingTarget(false)} className="text-outline hover:text-on-surface-variant p-1">
              <X size={16} />
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={startEditTarget}
            className="inline-flex items-center gap-1.5 text-on-surface-variant hover:text-on-surface"
          >
            <span className="text-sm font-mono">{formatTarget(targetMin)}</span>
            <Pencil size={12} className="text-outline" />
          </button>
        )}
      </div>

      <button
        type="button"
        onClick={() => setModalOpen(true)}
        className="w-full bg-primary text-on-primary font-semibold rounded-full py-3 text-lg inline-flex items-center justify-center gap-2"
      >
        <Plus size={22} /> Add reading
      </button>

      {/* Consumed this session */}
      <div className="bg-panel border border-outline-variant rounded-2xl px-3 py-2 shadow-sm">
        <p className="text-xs font-bold text-on-surface-variant uppercase tracking-wide mb-2">Consumed this session</p>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-semibold text-on-surface-variant block mb-1">Needles used</label>
            <input
              type="number"
              min="0"
              inputMode="numeric"
              value={needles}
              onChange={e => setNeedles(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-full bg-bg border border-outline rounded-xl px-2 py-1 text-sm text-on-surface text-center focus:border-primary focus:outline-none"
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-on-surface-variant block mb-1">On/Off packs</label>
            <input
              type="number"
              min="0"
              inputMode="numeric"
              value={onOffPacks}
              onChange={e => setOnOffPacks(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="w-full bg-bg border border-outline rounded-xl px-2 py-1 text-sm text-on-surface text-center focus:border-primary focus:outline-none"
            />
          </div>
        </div>
      </div>

      <ul className="space-y-2">
        {sorted.length === 0 && <li className="text-outline text-sm">No readings yet.</li>}
        {sorted.map(r => (
          <li key={r.reading_id} className="bg-panel border border-outline-variant rounded-2xl px-3 py-2 text-sm shadow-sm">
            <div className="flex justify-between">
              <span className="font-mono text-on-surface-variant font-semibold">{r.time}</span>
              <span className={
                'inline-flex items-center gap-1 ' + (
                  r.status === 'pending' ? 'text-outline' :
                  r.status === 'error'   ? 'text-error'   :
                                           'text-tertiary'
                )
              }>
                {r.status === 'pending' ? <><Loader2 size={14} className="animate-spin" /> saving…</> :
                 r.status === 'error'   ? <><AlertCircle size={14} /> error</> :
                                          <Check size={14} />}
              </span>
            </div>
            <div className="text-on-surface-variant mt-0.5">
              BP {r.bp_sys ?? '–'}/{r.bp_dia ?? '–'} · pulse {r.pulse ?? '–'} · BF {r.blood_flow ?? '–'} · VP {r.venous_pressure ?? '–'} · AP {r.arterial_pressure ?? '–'}
            </div>
            {r.note && <div className="text-outline italic mt-0.5">{r.note}</div>}
            {r.status === 'error' && (
              <div className="text-error text-xs mt-1">
                {r.errorMsg} <button type="button" className="underline ml-2" onClick={() => retry(r)}>Retry</button>
              </div>
            )}
          </li>
        ))}
      </ul>

      {modalOpen && (
        <AddReadingModal
          sessionId={sessionId}
          seq={nextSeq}
          defaultBloodFlow={lastBloodFlow}
          onSave={persist}
          onClose={() => setModalOpen(false)}
        />
      )}
    </div>
  );
}
```

- [ ] **Replace PostTreatment.tsx**

```tsx
// frontend/src/routes/Treatment/screens/PostTreatment.tsx
import { useEffect, useState } from 'react';
import { CheckCircle2 } from 'lucide-react';
import { ApiError, updateSession } from '../api';
import { NumberField } from '../components/NumberField';
import { SaveButton } from '../components/SaveButton';
import { cloudGet } from '../../../api/cloudRun';
import { logEvent } from '../../Inventory/api';
import { SESSION_FIXED_DELTAS } from '../../Inventory/constants';
import type { Session } from '../schemas';
import type { AuthSettings } from '../../../auth/storage';
import type { SessionConsumed } from '../storage';

interface Props {
  auth: AuthSettings | null;
  session: Session;
  consumed: SessionConsumed;
  onSaved: () => void;
}

interface FormState {
  post_weight?: number;
  post_bp_sys?: number;
  post_bp_dia?: number;
  post_pulse?: number;
  duration_min?: number;
  dialysate_volume?: number;
  total_uf?: number;
  blood_processed?: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

const DEFAULT_DURATION_MIN = 255;
const DEFAULT_DIALYSATE_VOLUME = 49;

export function PostTreatment({ auth, session, consumed, onSaved }: Props) {
  const sessionId = session.session_id;
  const [form, setForm] = useState<FormState>({
    duration_min: consumed.durationMin ?? DEFAULT_DURATION_MIN,
    dialysate_volume: DEFAULT_DIALYSATE_VOLUME,
  });
  const [totalUfTouched, setTotalUfTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [epoUsed, setEpoUsed] = useState(true);
  const [epoStock, setEpoStock] = useState<number | null>(null);

  useEffect(() => {
    if (!auth) return;
    cloudGet<{ stock: Record<string, number> }>(auth, '/api/inventory')
      .then(data => setEpoStock(data.stock['epo'] ?? 0))
      .catch(() => {});
  }, [auth]);

  function update<K extends keyof FormState>(k: K, v: FormState[K]) {
    setForm(f => ({ ...f, [k]: v }));
  }

  const derivedTotalUf =
    session.pre_weight != null && form.post_weight != null
      ? round2(session.pre_weight - form.post_weight)
      : undefined;
  const effectiveTotalUf = totalUfTouched ? form.total_uf : derivedTotalUf;

  const ready = form.post_weight != null && form.post_bp_sys != null && form.post_bp_dia != null;

  async function submit() {
    setError(null);
    setSaving(true);
    try {
      await updateSession({
        session_id: sessionId,
        ...form,
        total_uf: effectiveTotalUf,
      });

      if (auth) {
        const deltas: Record<string, number> = {
          ...SESSION_FIXED_DELTAS,
          'P00012326': -consumed.needles,
          'UK00000774': -consumed.onOffPacks,
        };
        if (consumed.heparinUsed) deltas['heparin'] = -1;
        if (epoUsed) deltas['epo'] = -1;
        logEvent(auth, 'session', deltas).catch(() => {});
      }

      onSaved();
    } catch (e) {
      setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="screen-enter p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-bold inline-flex items-center gap-2">
        <CheckCircle2 size={20} className="text-primary" /> Post-treatment
      </h1>
      <p className="text-sm text-outline font-mono">{sessionId}</p>

      <div className="grid grid-cols-2 gap-3">
        <NumberField label="Blood processed (L)" value={form.blood_processed} onChange={v => update('blood_processed', v)} />
        <NumberField label="BP sys" value={form.post_bp_sys} onChange={v => update('post_bp_sys', v)} step="1" required />
        <NumberField label="BP dia" value={form.post_bp_dia} onChange={v => update('post_bp_dia', v)} step="1" required />
        <NumberField label="Pulse" value={form.post_pulse} onChange={v => update('post_pulse', v)} step="1" />
        <NumberField label="Weight (kg)" value={form.post_weight} onChange={v => update('post_weight', v)} required />
        <NumberField label="Duration (min)" value={form.duration_min} onChange={v => update('duration_min', v)} step="1" />
        <NumberField label="Dialysate vol (L)" value={form.dialysate_volume} onChange={v => update('dialysate_volume', v)} />
        <NumberField
          label="Total UF (L)"
          value={effectiveTotalUf}
          onChange={v => { setTotalUfTouched(v != null); update('total_uf', v); }}
        />
      </div>

      <div className="flex items-center justify-between bg-panel border border-outline-variant rounded-2xl px-3 py-2 shadow-sm">
        <div>
          <span className="text-sm text-on-surface font-medium">EPO</span>
          {epoStock !== null && (
            <span className="ml-2 text-xs text-outline">{epoStock} remaining</span>
          )}
        </div>
        <button
          type="button"
          onClick={() => setEpoUsed(e => !e)}
          className={`px-3 py-1 rounded-full text-xs font-semibold transition-colors ${
            epoUsed
              ? 'bg-primary-container text-on-primary-container'
              : 'bg-outline-variant text-outline'
          }`}
        >
          {epoUsed ? 'Used' : 'Not used'}
        </button>
      </div>

      <SaveButton
        saving={saving}
        error={error}
        onClick={submit}
        disabled={!ready}
        icon={<CheckCircle2 size={20} />}
      >
        Finish session
      </SaveButton>
    </div>
  );
}
```

- [ ] **Run typecheck + tests**

```bash
cd frontend && npm run typecheck && npm test
```

Expected: all pass.

- [ ] **Smoke test in browser** — start dev server and check all 4 treatment screens visually

```bash
cd frontend && npm run dev
```

Open `http://localhost:5173`. Navigate to Treatment. Verify:
- White background, teal primary button with full-pill radius
- Scale-fade plays on every screen transition (Home → Pre → Active → Post)
- Pre-values stat cells have light-cyan background
- Timer shows in correct colour (teal while running, orange/red when low)
- End button is red/error colour (not teal)
- "Add reading" opens a bottom sheet that slides up
- Heparin/EPO toggle uses tonal chip (light cyan when active)

- [ ] **Commit**

```bash
git add frontend/src/routes/Treatment/screens/
git commit -m "feat: M3 light mode + screen-enter transitions for all Treatment screens"
```

---

## Task 7: SetupWizard

**Files:**
- Modify: `frontend/src/auth/SetupWizard.tsx`

- [ ] **Replace SetupWizard.tsx**

```tsx
// frontend/src/auth/SetupWizard.tsx
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
      const healthRes = await fetch('/api/health', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (healthRes.status === 401) throw new Error('Main API key rejected — check the value and try again.');
      if (!healthRes.ok) throw new Error(`API health check failed (${healthRes.status}).`);

      const tokenRes = await fetch('/api/treatment/token', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (tokenRes.status === 401) throw new Error('Main API key rejected by treatment endpoint.');
      if (!tokenRes.ok) throw new Error(`Failed to fetch treatment token (${tokenRes.status}).`);
      const { token, expires_at } = await tokenRes.json() as { token: string; expires_at: number };

      await signInWithCustomToken(firebaseAuth, token);

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
    <div className="screen-enter p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-2xl font-bold inline-flex items-center gap-2">
        <Activity size={22} className="text-primary" /> Setup
      </h1>
      {message && (
        <div className="bg-amber-50 border border-amber-300 text-amber-800 rounded-2xl px-3 py-2 text-sm">
          {message}
        </div>
      )}
      <p className="text-sm text-on-surface-variant">Enter your API key. It is stored on this device only.</p>

      <label className="block">
        <span className="text-xs font-semibold text-on-surface-variant mb-1 inline-flex items-center gap-1.5">
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
          className="w-full bg-bg border border-outline rounded-xl px-3 py-2 text-sm text-on-surface focus:border-primary focus:outline-none"
        />
      </label>

      <button
        type="button"
        onClick={submit}
        disabled={busy}
        className="w-full bg-primary text-on-primary font-semibold rounded-full py-3 disabled:opacity-40 inline-flex items-center justify-center gap-2"
      >
        <Save size={18} /> {busy ? 'Verifying…' : 'Save and continue'}
      </button>

      {error && (
        <div className="bg-red-50 border border-error text-error rounded-2xl px-3 py-2 text-sm">
          {error}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

- [ ] **Commit**

```bash
git add frontend/src/auth/SetupWizard.tsx
git commit -m "feat: M3 light mode for SetupWizard"
```

---

## Task 8: BloodTests structural colours

**Files:**
- Modify: `frontend/src/routes/BloodTests/index.tsx`
- Modify: `frontend/src/routes/BloodTests/components/FilterBar.tsx`
- Modify: `frontend/src/routes/BloodTests/components/ScorecardTile.tsx`
- Modify: `frontend/src/routes/BloodTests/components/Scorecard.tsx`

The BloodTests route uses hardcoded `bg-slate-900` / `bg-slate-800` etc. instead of the `bg-bg` / `bg-panel` tokens. These need to be replaced to match the new light theme.

- [ ] **Update index.tsx — swap hardcoded dark classes**

In `frontend/src/routes/BloodTests/index.tsx`, apply these substitutions:

| Old class | New class |
|---|---|
| `bg-slate-900` | `bg-bg` |
| `bg-slate-800` | `bg-panel` |
| `bg-slate-800/60` | `bg-surface-container` |
| `bg-slate-700/60` | `bg-outline-variant/40` |
| `bg-slate-700` (standalone) | `bg-outline-variant` |
| `border-slate-700` | `border-outline-variant` |
| `border-slate-800` | `border-outline-variant` |
| `divide-slate-700` | `divide-outline-variant` |
| `text-slate-100` | `text-on-surface` |
| `text-slate-200` | `text-on-surface` |
| `text-slate-300` | `text-on-surface` |
| `text-slate-400` | `text-on-surface-variant` |
| `text-slate-500` | `text-outline` |
| `text-cyan-400` | `text-primary` |
| `text-cyan-300` | `text-primary` |
| `border-b-2 border-cyan-400` | `border-b-2 border-primary` |
| `text-amber-400` | `text-warning` |

- [ ] **Update FilterBar.tsx**

In `frontend/src/routes/BloodTests/components/FilterBar.tsx`:

| Old | New |
|---|---|
| `bg-slate-700 px-2 py-1 text-sm text-slate-100` (selectCls) | `bg-bg border border-outline rounded-lg px-2 py-1 text-sm text-on-surface` |
| `border-b border-slate-700 bg-slate-800 p-3` | `border-b border-outline-variant bg-panel p-3` |
| `text-xs text-slate-400` (labels) | `text-xs text-on-surface-variant` |

- [ ] **Update ScorecardTile.tsx**

In `frontend/src/routes/BloodTests/components/ScorecardTile.tsx`:

| Old | New |
|---|---|
| `border-l-slate-600` | `border-l-outline` |
| `text-slate-100` (in:) | `text-on-surface` |
| `text-slate-300` (unknown:) | `text-on-surface-variant` |
| `bg-slate-800/60 ... hover:bg-slate-700/60 active:bg-slate-700` | `bg-surface-container ... hover:bg-outline-variant/30 active:bg-outline-variant/50` |
| `text-sm font-medium text-slate-200` | `text-sm font-medium text-on-surface` |
| `text-xs text-slate-500` | `text-xs text-outline` |
| `text-xs text-slate-600` | `text-xs text-outline` |
| `text-slate-600 hover:text-slate-400` (star) | `text-outline hover:text-on-surface-variant` |

- [ ] **Update Scorecard.tsx**

In `frontend/src/routes/BloodTests/components/Scorecard.tsx`:

| Old | New |
|---|---|
| `text-slate-400` | `text-on-surface-variant` |
| `text-sm font-semibold uppercase tracking-wide text-slate-400` | `text-sm font-semibold uppercase tracking-wide text-on-surface-variant` |

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

- [ ] **Commit**

```bash
git add frontend/src/routes/BloodTests/
git commit -m "feat: M3 light mode structural colours for BloodTests"
```

---

## Task 9: Inventory structural colours

**Files:**
- Modify: `frontend/src/routes/Inventory/index.tsx`
- Modify: `frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx`
- Modify: `frontend/src/routes/Inventory/components/StockItemRow.tsx`
- Modify: `frontend/src/routes/Inventory/components/LogEventModal.tsx`
- Modify: `frontend/src/routes/Inventory/components/OrderView.tsx`
- Modify: `frontend/src/routes/Inventory/components/EditOrderModal.tsx`

- [ ] **Apply class substitutions to all Inventory files**

For every file in `frontend/src/routes/Inventory/`, apply these substitutions:

| Old | New |
|---|---|
| `bg-slate-900` | `bg-bg` |
| `bg-slate-800` | `bg-panel` |
| `bg-slate-700` (background) | `bg-surface-container` |
| `border-slate-700` | `border-outline-variant` |
| `border-slate-600` | `border-outline` |
| `border-slate-800` | `border-outline-variant` |
| `divide-slate-700` | `divide-outline-variant` |
| `divide-y divide-slate-700/50` | `divide-y divide-outline-variant` |
| `text-slate-100` | `text-on-surface` |
| `text-slate-200` | `text-on-surface` |
| `text-slate-300` | `text-on-surface` |
| `text-slate-400` | `text-on-surface-variant` |
| `text-slate-500` | `text-outline` |
| `text-slate-600` | `text-outline` |
| `text-accent` | `text-primary` |
| `bg-accent text-bg` | `bg-primary text-on-primary` |
| `bg-accent` (standalone) | `bg-primary` |
| `border-accent` | `border-primary` |
| `focus:border-accent` | `focus:border-primary` |
| `hover:bg-slate-700/60` | `hover:bg-surface-container` |
| `hover:text-slate-300` | `hover:text-on-surface-variant` |
| `rounded-lg` (modals/cards) | `rounded-2xl` |
| `rounded-xl` (modals) | `rounded-2xl` |

- [ ] **Run typecheck**

```bash
cd frontend && npm run typecheck
```

- [ ] **Commit**

```bash
git add frontend/src/routes/Inventory/
git commit -m "feat: M3 light mode structural colours for Inventory"
```

---

## Task 10: Fitness, TrendChart, KB, Chat, and Treatment index error states

**Files:**
- Modify: `frontend/src/routes/Fitness/index.tsx`
- Modify: `frontend/src/routes/BloodTests/components/TrendChart.tsx`
- Modify: `frontend/src/routes/KB/index.tsx`
- Modify: `frontend/src/routes/Chat/index.tsx`
- Modify: `frontend/src/routes/Treatment/index.tsx`

- [ ] **Update Fitness/index.tsx — apply class substitutions**

`Fitness/index.tsx` uses hardcoded dark classes throughout. Apply these substitutions:

| Old | New |
|---|---|
| `text-slate-400` | `text-on-surface-variant` |
| `text-slate-300` | `text-on-surface` |
| `text-slate-100` | `text-on-surface` |
| `text-slate-500` | `text-outline` |
| `text-cyan-400` | `text-primary` |
| `bg-cyan-600 hover:bg-cyan-500` (sync button) | `bg-primary hover:bg-primary/90` |
| `text-emerald-400` | `text-tertiary` |
| `text-amber-400` | `text-warning` |
| `text-red-400` | `text-error` |
| `bg-slate-700 text-slate-100` (retry button) | `bg-surface-container text-on-surface border border-outline-variant` |
| `border-slate-700` | `border-outline-variant` |
| `border-slate-700/60` | `border-outline-variant` |
| `bg-slate-800/40` | `bg-panel` |
| `text-xs uppercase tracking-wide text-slate-500` | `text-xs uppercase tracking-wide text-on-surface-variant` |
| `rounded-lg bg-slate-700` (inline) | `rounded-2xl bg-surface-container border border-outline-variant` |

- [ ] **Update BloodTests/TrendChart.tsx — apply class substitutions**

| Old | New |
|---|---|
| `text-slate-400` | `text-on-surface-variant` |
| `text-slate-200` | `text-on-surface` |
| `text-slate-400` (labels) | `text-on-surface-variant` |

- [ ] **Update KB placeholder**

```tsx
// frontend/src/routes/KB/index.tsx
export default function KB() {
  return <div className="p-8 text-on-surface-variant text-center">NxStage error KB — coming soon.</div>;
}
```

- [ ] **Update Chat placeholder**

```tsx
// frontend/src/routes/Chat/index.tsx
export default function Chat() {
  return <div className="p-8 text-on-surface-variant text-center">RAG chatbot — coming soon.</div>;
}
```

- [ ] **Update Treatment/index.tsx loading and error states**

In `frontend/src/routes/Treatment/index.tsx`, apply these targeted edits:

Loading state (line ~122):
```tsx
// was:
return <div className="p-4 text-slate-400">Loading…</div>;
// becomes:
return <div className="p-4 text-on-surface-variant">Loading…</div>;
```

Error state (line ~128):
```tsx
// was:
<div className="p-8 text-center space-y-3">
  <AlertTriangle className="w-8 h-8 text-amber-400 mx-auto" />
  <p className="text-slate-300">Could not connect...
  <button ... className="flex items-center gap-2 mx-auto px-4 py-2 rounded-lg bg-slate-700 text-slate-100 text-sm">
// becomes:
<div className="p-8 text-center space-y-3">
  <AlertTriangle className="w-8 h-8 text-warning mx-auto" />
  <p className="text-on-surface-variant">Could not connect...
  <button ... className="flex items-center gap-2 mx-auto px-4 py-2 rounded-2xl bg-surface-container text-on-surface text-sm border border-outline-variant">
```

Also update the `Suspense` fallback divs throughout `App.tsx`:
```tsx
// was:
<div className="p-4 text-slate-400">Loading…</div>
// becomes:
<div className="p-4 text-on-surface-variant">Loading…</div>
```

- [ ] **Run typecheck + tests**

```bash
cd frontend && npm run typecheck && npm test
```

Expected: all pass.

- [ ] **Commit**

```bash
git add frontend/src/routes/KB/index.tsx \
        frontend/src/routes/Chat/index.tsx \
        frontend/src/routes/Treatment/index.tsx \
        frontend/src/App.tsx
git commit -m "feat: M3 light mode for remaining routes and loading states"
```

---

## Task 11: Full build + deploy

- [ ] **Run full build**

```bash
cd frontend && npm run build
```

Expected: exits 0, no TypeScript errors, `dist/` populated.

- [ ] **Run tests one final time**

```bash
cd frontend && npm test
```

Expected: all pass.

- [ ] **Visual check — full app walkthrough**

```bash
cd frontend && npm run preview
```

Open `http://localhost:4173`. Check every tab:
- **Treatment**: Home (white, teal CTA pill button), Pre (form inputs with outline borders), Active (stat cells tinted cyan, green timer, bottom sheet modal), Post (same pattern)
- **Tests**: white background, no dark surfaces
- **Inventory**: white cards, teal accent
- **KB / Chat**: white placeholder screens
- Tab bar: tonal cyan pill on active icon, outline icons everywhere, no filled icons

- [ ] **Deploy**

```bash
cd frontend && npm run build && npx wrangler pages deploy dist --project-name=treatment-tracker --branch=master --commit-dirty=true
```

Expected: `Deployment complete` with Production environment (verify with `wrangler pages deployment list --project-name=treatment-tracker` — `Environment` column must show `Production`).

- [ ] **On-device check**

Open `https://treatment-tracker.pages.dev` on Android. If the old dark PWA is still installed (different origin or cached service worker), go to Android Settings → Apps → Treatment tracker → Clear data, then reinstall from the URL. Run a test session start-to-finish.
