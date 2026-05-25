# Blood Test Dashboard Implementation Plan

> **Status: Completed (2026-05-22 → 2026-05-25) and Superseded by `2026-05-25-homehd-unified-app-design.md`.** This plan ran to completion — see commits `cda5433` (repo restructure) through `a1d8dd3` (mark dashboard live). The resulting code now ports into the unified app per the new spec's Phase 2. Retained as build history.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal blood-test analytics dashboard (panel-grouped scorecard + single-marker trend chart) plus an authenticated query endpoint, as a second app inside the `treatment_tracker` repo.

**Architecture:** Restructure the repo into `pwa/` (the existing app, moved) + `dashboard/` (new). The dashboard is a Vite + React static site on Cloudflare Pages. A build script converts `blood_tests.csv` to JSON, which is bundled into a Cloudflare Pages Function (`GET /api/blood-tests`) — the single, key-authenticated data gateway for both the dashboard and any external notebook. All UI filtering is client-side over the in-memory dataset.

**Tech Stack:** Vite, React 18, TypeScript (strict), Tailwind CSS, Recharts, zod, vitest, Cloudflare Pages Functions, csv-parse, tsx.

**Spec:** `docs/superpowers/specs/2026-05-22-blood-test-dashboard-design.md`

---

## Pre-task note

The PWA currently has **uncommitted changes** (the 2026-05-15 live-session fixes in `src/`, `backend/Code.gs`, `README.md`). Commit those on `main` **before** starting Task 1, so the restructure commit is a pure file move with no behavioural changes mixed in.

## File structure

```
treatment_tracker/
├── pwa/                              # MOVED: all existing PWA files
├── dashboard/                        # NEW
│   ├── index.html
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── tailwind.config.ts
│   ├── postcss.config.js
│   ├── vitest.config.ts
│   ├── src/
│   │   ├── main.tsx
│   │   ├── index.css
│   │   ├── App.tsx                   # key-entry / loading / error / ready state machine
│   │   ├── schemas.ts                # zod row + response schemas, BloodTestRow type
│   │   ├── storage.ts                # localStorage: access key only
│   │   ├── api.ts                    # GET /api/blood-tests, typed ApiError
│   │   ├── markers.ts                # marker→panel map, display names
│   │   ├── lib/
│   │   │   ├── queryFilter.ts        # pure filtering — shared by endpoint + client
│   │   │   └── scorecard.ts          # pure scorecard derivations
│   │   ├── screens/
│   │   │   ├── KeyEntry.tsx
│   │   │   └── Dashboard.tsx         # filter bar + Scorecard/Trend tabs
│   │   └── components/
│   │       ├── FilterBar.tsx
│   │       ├── Scorecard.tsx
│   │       ├── ScorecardTile.tsx
│   │       └── TrendChart.tsx
│   ├── functions/api/
│   │   └── blood-tests.ts            # Cloudflare Pages Function
│   ├── scripts/
│   │   ├── csv.ts                    # pure csvToRows()
│   │   └── build-data.ts             # runner: CSV file → data/blood_tests.json
│   └── data/blood_tests.json         # generated, gitignored
├── scripts/pkb_backfill/             # unchanged
├── docs/                             # unchanged (specs/, plans/)
├── README.md                         # rewritten for two apps
└── .gitignore                         # health-data entries added
```

---

### Task 1: Restructure repo — move the PWA into `pwa/`

**Files:**
- Move: every existing PWA file/dir into `pwa/`
- Keep at root: `LICENSE`, `docs/`, `scripts/`, `.gitignore`, `README.md`

- [ ] **Step 1: Guard health data in `.gitignore` first**

Before any `git add`, ensure the untracked health-data files under `scripts/pkb_backfill/` can never be staged. Append to the root `.gitignore`:
```
# Personal health data — never commit (repo is open-source-bound)
scripts/pkb_backfill/blood_tests.csv
scripts/pkb_backfill/pastes/
scripts/pkb_backfill/*.txt
```

- [ ] **Step 2: Create the folder and move source files**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
mkdir pwa
git mv src public backend index.html package.json package-lock.json \
       vite.config.ts tsconfig.json tsconfig.node.json tsconfig.test.json \
       tailwind.config.ts postcss.config.js vitest.config.ts README.md pwa/
```

- [ ] **Step 3: Move untracked generated/config artifacts and clean up**

```bash
# generated files git doesn't track — move or delete (they regenerate)
rm -f vite.config.js vite.config.d.ts vitest.config.js vitest.config.d.ts \
      tsconfig.tsbuildinfo tsconfig.node.tsbuildinfo
rm -rf node_modules dist .wrangler
```

- [ ] **Step 4: Reinstall and verify the PWA still builds**

```bash
cd pwa && npm install && npm run build
```
Expected: `dist/` is produced with no TypeScript errors.

- [ ] **Step 5: Verify the PWA test suite still passes**

Run: `cd pwa && npm test`
Expected: the existing `sessionId` test passes (5/5).

- [ ] **Step 6: Commit**

`git add -A` is now safe — the health-data files are ignored as of Step 1.
```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add -A
git commit -m "refactor: move PWA into pwa/ ahead of dashboard subfolder"
```

---

### Task 2: Scaffold the `dashboard/` Vite app and update `.gitignore`

**Files:**
- Create: `dashboard/package.json`, `dashboard/index.html`, `dashboard/vite.config.ts`, `dashboard/tsconfig.json`, `dashboard/tailwind.config.ts`, `dashboard/postcss.config.js`, `dashboard/vitest.config.ts`, `dashboard/src/main.tsx`, `dashboard/src/index.css`, `dashboard/src/App.tsx` (placeholder)
- Modify: `.gitignore`

- [ ] **Step 1: Add dashboard entries to the root `.gitignore`**

The `scripts/pkb_backfill/` health-data entries were already added in Task 1. Append the dashboard entries (`dashboard/data/` holds the generated health-data JSON):
```
# Dashboard — generated data and build artifacts
dashboard/data/
dashboard/node_modules/
dashboard/dist/
dashboard/.wrangler/
dashboard/.dev.vars
```

- [ ] **Step 2: Create `dashboard/package.json`**

```json
{
  "name": "blood-test-dashboard",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "build-data": "tsx scripts/build-data.ts",
    "predev": "npm run build-data",
    "dev": "vite",
    "prebuild": "npm run build-data",
    "build": "tsc -b && vite build",
    "preview": "wrangler pages dev dist",
    "test": "vitest run",
    "typecheck": "tsc -b --noEmit"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.13.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20240000.0",
    "@types/node": "^22.0.0",
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.3",
    "autoprefixer": "^10.5.0",
    "csv-parse": "^5.5.6",
    "postcss": "^8.5.14",
    "tailwindcss": "^3.4.19",
    "tsx": "^4.19.0",
    "typescript": "^5.6.3",
    "vite": "^5.4.10",
    "vitest": "^2.1.4",
    "wrangler": "^4.90.0"
  }
}
```

- [ ] **Step 3: Create the config files**

`dashboard/index.html`:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Blood Test Dashboard</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

`dashboard/vite.config.ts`:
```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({ plugins: [react()] });
```

`dashboard/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noEmit": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "types": ["@cloudflare/workers-types", "vitest/globals", "node"]
  },
  "include": ["src", "functions", "scripts"]
}
```

`dashboard/tailwind.config.ts`:
```ts
import type { Config } from 'tailwindcss';
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: { extend: {} },
  plugins: [],
} satisfies Config;
```

`dashboard/postcss.config.js`:
```js
export default { plugins: { tailwindcss: {}, autoprefixer: {} } };
```

`dashboard/vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { globals: true, environment: 'node' } });
```

- [ ] **Step 4: Create the entry files**

`dashboard/src/index.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

`dashboard/src/main.tsx`:
```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

`dashboard/src/App.tsx` (placeholder, replaced in Task 11):
```tsx
export default function App() {
  return <div className="p-8 text-slate-100">Blood Test Dashboard</div>;
}
```

- [ ] **Step 5: Install and verify the scaffold builds**

```bash
cd dashboard && npm install
```
Note: `npm run build` is not expected to pass yet — `build-data.ts` does not exist (Task 4). `npx vite build` alone should succeed.
Run: `cd dashboard && npx vite build`
Expected: `dist/` produced, no errors.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add .gitignore dashboard/
git commit -m "feat(dashboard): scaffold Vite app, gitignore health data"
```

---

### Task 3: Define the data schema (`schemas.ts`)

**Files:**
- Create: `dashboard/src/schemas.ts`
- Test: `dashboard/src/schemas.test.ts`

- [ ] **Step 1: Write the failing test**

`dashboard/src/schemas.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { BloodTestRowSchema, ApiResponseSchema } from './schemas';

const validRow = {
  marker: 'creatinine', datetime: '2026-05-18T14:18:00', value: 1073,
  unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre',
  note: '', source: 'imperial-pkb', lab_id: '99261284417',
  phase: 'home-hd', created_at: '2026-05-22T10:00:00', qualitative: false,
};

describe('BloodTestRowSchema', () => {
  it('accepts a valid row', () => {
    expect(BloodTestRowSchema.parse(validRow).marker).toBe('creatinine');
  });
  it('accepts null reference bounds', () => {
    expect(BloodTestRowSchema.parse({ ...validRow, ref_low: null, ref_high: null }).ref_low).toBeNull();
  });
  it('rejects an unknown phase', () => {
    expect(BloodTestRowSchema.safeParse({ ...validRow, phase: 'outpatient' }).success).toBe(false);
  });
});

describe('ApiResponseSchema', () => {
  it('accepts a response with count and rows', () => {
    expect(ApiResponseSchema.parse({ count: 1, rows: [validRow] }).count).toBe(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard && npx vitest run src/schemas.test.ts`
Expected: FAIL — `Cannot find module './schemas'`.

- [ ] **Step 3: Write `schemas.ts`**

```ts
import { z } from 'zod';

export const PHASES = ['admission', 'in-center-hd', 'home-hd'] as const;

export const BloodTestRowSchema = z.object({
  marker: z.string().min(1),
  datetime: z.string().min(1),
  value: z.number(),
  unit: z.string(),
  ref_low: z.number().nullable(),
  ref_high: z.number().nullable(),
  timing: z.enum(['pre', 'post', '']),
  note: z.string(),
  source: z.string(),
  lab_id: z.string(),
  phase: z.enum(PHASES),
  created_at: z.string(),
  qualitative: z.boolean(),
});

export type BloodTestRow = z.infer<typeof BloodTestRowSchema>;

export const ApiResponseSchema = z.object({
  count: z.number(),
  rows: z.array(BloodTestRowSchema),
});

export type ApiResponse = z.infer<typeof ApiResponseSchema>;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard && npx vitest run src/schemas.test.ts`
Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/schemas.ts dashboard/src/schemas.test.ts
git commit -m "feat(dashboard): add blood test row + response schemas"
```

---

### Task 4: CSV → JSON converter (`scripts/csv.ts` + `build-data.ts`)

**Files:**
- Create: `dashboard/scripts/csv.ts`, `dashboard/scripts/build-data.ts`
- Test: `dashboard/scripts/csv.test.ts`

- [ ] **Step 1: Write the failing test**

`dashboard/scripts/csv.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { csvToRows } from './csv';

const HEADER =
  'marker,datetime,value,unit,ref_low,ref_high,timing,note,source,lab_id,phase,created_at';

describe('csvToRows', () => {
  it('parses a numeric row and sorts by datetime', () => {
    const csv = [
      HEADER,
      'urea,2026-05-18T14:18:00,19.7,mmol/L,2.5,7.8,pre,,imperial-pkb,1,home-hd,2026-05-22T10:00:00',
      'urea,2026-04-15T12:00:00,1.9,mmol/L,2.5,7.8,post,,imperial-pkb,2,home-hd,2026-05-22T10:00:00',
    ].join('\n');
    const rows = csvToRows(csv);
    expect(rows.map((r) => r.datetime)).toEqual([
      '2026-04-15T12:00:00', '2026-05-18T14:18:00',
    ]);
    expect(rows[1].value).toBe(19.7);
    expect(rows[1].qualitative).toBe(false);
  });

  it('treats blank reference bounds as null', () => {
    const csv = [HEADER, 'mcv,2026-05-18T14:18:00,88,fL,,,,,lnw-pkb,3,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)[0].ref_low).toBeNull();
  });

  it('flags a qualitative result (value 0) and keeps the text unit', () => {
    const csv = [HEADER, 'mrsa_screen,2026-05-18T14:18:00,0,Not detected,,,,,lnw-pkb,4,home-hd,2026-05-22T10:00:00'].join('\n');
    const row = csvToRows(csv)[0];
    expect(row.qualitative).toBe(true);
    expect(row.unit).toBe('Not detected');
  });

  it('strips thousands commas from values', () => {
    const csv = [HEADER, '"creatinine",2026-05-18T14:18:00,"1,073",umol/L,64,104,pre,,imperial-pkb,5,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)[0].value).toBe(1073);
  });

  it('drops rows with no marker or datetime', () => {
    const csv = [HEADER, ',,,,,,,,,,,', 'urea,2026-05-18T14:18:00,5,mmol/L,2.5,7.8,,,imperial-pkb,6,home-hd,2026-05-22T10:00:00'].join('\n');
    expect(csvToRows(csv)).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard && npx vitest run scripts/csv.test.ts`
Expected: FAIL — `Cannot find module './csv'`.

- [ ] **Step 3: Write `scripts/csv.ts`**

```ts
import { parse } from 'csv-parse/sync';
import type { BloodTestRow } from '../src/schemas';

function num(v: string | undefined): number | null {
  const t = (v ?? '').trim();
  if (t === '') return null;
  const n = Number(t.replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

export function csvToRows(csvText: string): BloodTestRow[] {
  const records = parse(csvText, {
    columns: true,
    skip_empty_lines: true,
    relax_column_count: true,
  }) as Record<string, string>[];

  const rows: BloodTestRow[] = [];
  for (const r of records) {
    const marker = (r.marker ?? '').trim();
    const datetime = (r.datetime ?? '').trim();
    if (!marker || !datetime) continue;
    const value = num(r.value) ?? 0;
    const timing = (r.timing ?? '').trim();
    rows.push({
      marker,
      datetime,
      value,
      unit: (r.unit ?? '').trim(),
      ref_low: num(r.ref_low),
      ref_high: num(r.ref_high),
      timing: timing === 'pre' || timing === 'post' ? timing : '',
      note: (r.note ?? '').trim(),
      source: (r.source ?? '').trim(),
      lab_id: (r.lab_id ?? '').trim(),
      phase: (r.phase ?? '').trim() as BloodTestRow['phase'],
      created_at: (r.created_at ?? '').trim(),
      qualitative: value === 0,
    });
  }
  rows.sort((a, b) => a.datetime.localeCompare(b.datetime));
  return rows;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard && npx vitest run scripts/csv.test.ts`
Expected: PASS (5/5).

- [ ] **Step 5: Write the runner `scripts/build-data.ts`**

```ts
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { csvToRows } from './csv';

const here = dirname(fileURLToPath(import.meta.url));
const csvPath = resolve(here, '../../scripts/pkb_backfill/blood_tests.csv');
const outPath = resolve(here, '../data/blood_tests.json');

const rows = csvToRows(readFileSync(csvPath, 'utf8'));
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(rows));
console.log(`build-data: wrote ${rows.length} rows to ${outPath}`);
```

- [ ] **Step 6: Run the converter and verify output**

Run: `cd dashboard && npm run build-data`
Expected: `build-data: wrote 2391 rows to .../dashboard/data/blood_tests.json` (row count matches `blood_tests.csv` minus the header; the exact number may differ as the CSV grows).

- [ ] **Step 7: Commit**

```bash
git add dashboard/scripts/csv.ts dashboard/scripts/csv.test.ts dashboard/scripts/build-data.ts
git commit -m "feat(dashboard): CSV to JSON converter with prebuild hook"
```

---

### Task 5: Pure query-filter logic (`lib/queryFilter.ts`)

**Files:**
- Create: `dashboard/src/lib/queryFilter.ts`
- Test: `dashboard/src/lib/queryFilter.test.ts`

- [ ] **Step 1: Write the failing test**

`dashboard/src/lib/queryFilter.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { filterRows, isValidBound } from './queryFilter';
import type { BloodTestRow } from '../schemas';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

const rows: BloodTestRow[] = [
  row({ marker: 'urea', datetime: '2026-01-10T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2026-04-15T09:00:00', phase: 'home-hd' }),
  row({ marker: 'creatinine', datetime: '2026-04-20T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2025-06-01T09:00:00', phase: 'in-center-hd' }),
];

describe('isValidBound', () => {
  it('accepts YYYY-MM and YYYY-MM-DD', () => {
    expect(isValidBound('2026-04')).toBe(true);
    expect(isValidBound('2026-04-15')).toBe(true);
  });
  it('rejects malformed bounds', () => {
    expect(isValidBound('2026')).toBe(false);
    expect(isValidBound('April')).toBe(false);
  });
});

describe('filterRows', () => {
  it('filters by marker', () => {
    expect(filterRows(rows, { marker: ['creatinine'] })).toHaveLength(1);
  });
  it('filters by phase', () => {
    expect(filterRows(rows, { phase: ['in-center-hd'] })).toHaveLength(1);
  });
  it('month-granularity `to` keeps the whole month', () => {
    const r = filterRows(rows, { to: '2026-04' });
    expect(r.map((x) => x.datetime).sort()).toEqual([
      '2025-06-01T09:00:00', '2026-01-10T09:00:00', '2026-04-15T09:00:00', '2026-04-20T09:00:00',
    ]);
  });
  it('month range from/to is inclusive on both ends', () => {
    const r = filterRows(rows, { from: '2026-01', to: '2026-04' });
    expect(r).toHaveLength(3);
  });
  it('day-granularity bounds work', () => {
    const r = filterRows(rows, { from: '2026-04-16', to: '2026-04-20' });
    expect(r.map((x) => x.marker)).toEqual(['creatinine']);
  });
  it('combines marker + phase + range', () => {
    const r = filterRows(rows, { marker: ['urea'], phase: ['home-hd'], from: '2026-02' });
    expect(r.map((x) => x.datetime)).toEqual(['2026-04-15T09:00:00']);
  });
  it('empty params returns everything', () => {
    expect(filterRows(rows, {})).toHaveLength(4);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard && npx vitest run src/lib/queryFilter.test.ts`
Expected: FAIL — `Cannot find module './queryFilter'`.

- [ ] **Step 3: Write `lib/queryFilter.ts`**

```ts
import type { BloodTestRow } from '../schemas';

export type QueryParams = {
  marker?: string[];
  phase?: string[];
  from?: string; // YYYY-MM or YYYY-MM-DD
  to?: string;
};

const BOUND_RE = /^\d{4}-\d{2}(-\d{2})?$/;

export function isValidBound(s: string): boolean {
  return BOUND_RE.test(s);
}

// Compare a row's datetime against a bound at the bound's own granularity.
// e.g. to='2026-04' compares the row's 'YYYY-MM' prefix, so all of April matches.
export function matchesFrom(datetime: string, from: string): boolean {
  return datetime.slice(0, from.length) >= from;
}

export function matchesTo(datetime: string, to: string): boolean {
  return datetime.slice(0, to.length) <= to;
}

export function filterRows(rows: BloodTestRow[], p: QueryParams): BloodTestRow[] {
  return rows.filter((r) => {
    if (p.marker?.length && !p.marker.includes(r.marker)) return false;
    if (p.phase?.length && !p.phase.includes(r.phase)) return false;
    if (p.from && !matchesFrom(r.datetime, p.from)) return false;
    if (p.to && !matchesTo(r.datetime, p.to)) return false;
    return true;
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard && npx vitest run src/lib/queryFilter.test.ts`
Expected: PASS (9/9).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/lib/queryFilter.ts dashboard/src/lib/queryFilter.test.ts
git commit -m "feat(dashboard): pure query-filter logic with month/date granularity"
```

---

### Task 6: The endpoint (`functions/api/blood-tests.ts`)

**Files:**
- Create: `dashboard/functions/api/blood-tests.ts`

No unit test — the filtering logic is already covered by Task 5; this task wires it into a Pages Function. Verified manually in Step 3.

- [ ] **Step 1: Write the Pages Function**

`dashboard/functions/api/blood-tests.ts`:
```ts
import data from '../../data/blood_tests.json';
import { filterRows, isValidBound, type QueryParams } from '../../src/lib/queryFilter';
import { PHASES, type BloodTestRow } from '../../src/schemas';

interface Env {
  DASHBOARD_KEY: string;
}

const rows = data as BloodTestRow[];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const onRequestGet: PagesFunction<Env> = (context) => {
  const { request, env } = context;

  const auth = request.headers.get('Authorization');
  if (!env.DASHBOARD_KEY || auth !== `Bearer ${env.DASHBOARD_KEY}`) {
    return json({ error: 'unauthorized' }, 401);
  }

  const params = new URL(request.url).searchParams;
  const p: QueryParams = {};

  const marker = params.get('marker');
  if (marker) p.marker = marker.split(',').map((s) => s.trim()).filter(Boolean);

  const phase = params.get('phase');
  if (phase) {
    p.phase = phase.split(',').map((s) => s.trim()).filter(Boolean);
    if (p.phase.some((x) => !(PHASES as readonly string[]).includes(x))) {
      return json({ error: 'invalid phase param' }, 400);
    }
  }

  const from = params.get('from');
  if (from) {
    if (!isValidBound(from)) return json({ error: 'invalid from param' }, 400);
    p.from = from;
  }

  const to = params.get('to');
  if (to) {
    if (!isValidBound(to)) return json({ error: 'invalid to param' }, 400);
    p.to = to;
  }

  const result = filterRows(rows, p);
  return json({ count: result.length, rows: result });
};
```

Note: Pages Functions automatically return `405` for non-GET requests when only `onRequestGet` is exported — no extra handler needed.

- [ ] **Step 2: Build the dashboard (regenerates data, bundles the function)**

```bash
cd dashboard && npm run build
```
Expected: build succeeds; `data/blood_tests.json` regenerated by the prebuild hook.

- [ ] **Step 3: Smoke-test the endpoint locally with Wrangler**

```bash
cd dashboard
echo 'DASHBOARD_KEY=test-key-123' > .dev.vars   # gitignored; wrangler loads it automatically
npx wrangler pages dev dist
```
In a second terminal:
```bash
# 401 — no key
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8788/api/blood-tests
# 200 — with key, all rows
curl -s -H 'Authorization: Bearer test-key-123' 'http://localhost:8788/api/blood-tests' | head -c 120
# 200 — filtered
curl -s -H 'Authorization: Bearer test-key-123' 'http://localhost:8788/api/blood-tests?marker=urea&from=2026-01&to=2026-05' | python3 -c 'import sys,json; print(json.load(sys.stdin)["count"])'
# 400 — bad date
curl -s -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer test-key-123' 'http://localhost:8788/api/blood-tests?from=2026'
```
Expected: `401`, then a JSON body starting `{"count":`, then a small integer, then `400`.

- [ ] **Step 4: Commit**

```bash
git add dashboard/functions/
git commit -m "feat(dashboard): key-authed blood-tests query endpoint"
```

---

### Task 7: Scorecard derivations (`lib/scorecard.ts`)

**Files:**
- Create: `dashboard/src/lib/scorecard.ts`
- Test: `dashboard/src/lib/scorecard.test.ts`

- [ ] **Step 1: Write the failing test**

`dashboard/src/lib/scorecard.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { summarize } from './scorecard';
import type { BloodTestRow } from '../schemas';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

describe('summarize', () => {
  it('picks the latest numeric row and computes the delta', () => {
    const s = summarize('urea', [
      row({ datetime: '2026-03-01T09:00:00', value: 6 }),
      row({ datetime: '2026-04-01T09:00:00', value: 8 }),
    ]);
    expect(s.latest?.value).toBe(8);
    expect(s.delta).toBe(2);
    expect(s.direction).toBe('up');
  });

  it('marks an out-of-range latest value', () => {
    const s = summarize('urea', [row({ value: 9, ref_low: 2.5, ref_high: 7.8 })]);
    expect(s.status).toBe('out');
  });

  it('marks an in-range latest value', () => {
    const s = summarize('urea', [row({ value: 5 })]);
    expect(s.status).toBe('in');
  });

  it('returns unknown status when the reference range is missing', () => {
    const s = summarize('mcv', [row({ ref_low: null, ref_high: null })]);
    expect(s.status).toBe('unknown');
  });

  it('ignores qualitative rows when choosing latest', () => {
    const s = summarize('urea', [
      row({ datetime: '2026-04-01T09:00:00', value: 7 }),
      row({ datetime: '2026-05-01T09:00:00', value: 0, qualitative: true }),
    ]);
    expect(s.latest?.value).toBe(7);
  });

  it('has null delta and direction with only one reading', () => {
    const s = summarize('urea', [row({ value: 5 })]);
    expect(s.delta).toBeNull();
    expect(s.direction).toBeNull();
  });

  it('returns an empty summary for no rows', () => {
    const s = summarize('urea', []);
    expect(s.latest).toBeNull();
    expect(s.status).toBe('unknown');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard && npx vitest run src/lib/scorecard.test.ts`
Expected: FAIL — `Cannot find module './scorecard'`.

- [ ] **Step 3: Write `lib/scorecard.ts`**

```ts
import type { BloodTestRow } from '../schemas';

export type MarkerSummary = {
  marker: string;
  latest: BloodTestRow | null;
  previous: BloodTestRow | null;
  delta: number | null;
  direction: 'up' | 'down' | 'flat' | null;
  status: 'in' | 'out' | 'unknown';
};

export function summarize(marker: string, rows: BloodTestRow[]): MarkerSummary {
  const numeric = rows
    .filter((r) => !r.qualitative)
    .sort((a, b) => a.datetime.localeCompare(b.datetime));

  const latest = numeric[numeric.length - 1] ?? null;
  const previous = numeric[numeric.length - 2] ?? null;

  let delta: number | null = null;
  let direction: MarkerSummary['direction'] = null;
  if (latest && previous) {
    delta = Number((latest.value - previous.value).toFixed(4));
    direction = delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat';
  }

  let status: MarkerSummary['status'] = 'unknown';
  if (latest && latest.ref_low != null && latest.ref_high != null) {
    status = latest.value >= latest.ref_low && latest.value <= latest.ref_high ? 'in' : 'out';
  }

  return { marker, latest, previous, delta, direction, status };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard && npx vitest run src/lib/scorecard.test.ts`
Expected: PASS (7/7).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/lib/scorecard.ts dashboard/src/lib/scorecard.test.ts
git commit -m "feat(dashboard): scorecard latest/delta/in-range derivations"
```

---

### Task 8: Marker metadata (`markers.ts`)

**Files:**
- Create: `dashboard/src/markers.ts`
- Test: `dashboard/src/markers.test.ts`

- [ ] **Step 1: Write the failing test**

`dashboard/src/markers.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { panelFor, displayName, PANELS } from './markers';

describe('panelFor', () => {
  it('maps known markers to their panel', () => {
    expect(panelFor('creatinine')).toBe('Renal');
    expect(panelFor('alt')).toBe('Liver');
    expect(panelFor('haemoglobin')).toBe('Haematology');
  });
  it('falls back to Other for unmapped markers', () => {
    expect(panelFor('some_rare_marker')).toBe('Other');
  });
});

describe('displayName', () => {
  it('uses overrides for acronyms', () => {
    expect(displayName('egfr')).toBe('eGFR');
    expect(displayName('hba1c')).toBe('HbA1c');
  });
  it('title-cases snake_case names by default', () => {
    expect(displayName('adjusted_calcium')).toBe('Adjusted Calcium');
  });
});

describe('PANELS', () => {
  it('ends with Other', () => {
    expect(PANELS[PANELS.length - 1]).toBe('Other');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard && npx vitest run src/markers.test.ts`
Expected: FAIL — `Cannot find module './markers'`.

- [ ] **Step 3: Write `markers.ts`**

The map below covers the common renal/liver/bone/haematology markers. Any marker not listed falls to `Other` — which is acceptable for v1. Extend `PANEL_MAP` against the marker list in `blood_tests.csv` as desired.

```ts
export const PANELS = ['Renal', 'Liver', 'Bone', 'Haematology', 'Other'] as const;
export type Panel = (typeof PANELS)[number];

const PANEL_MAP: Record<string, Panel> = {
  creatinine: 'Renal', urea: 'Renal', egfr: 'Renal', sodium: 'Renal',
  potassium: 'Renal', chloride: 'Renal', bicarbonate: 'Renal',
  alt: 'Liver', ast: 'Liver', ggt: 'Liver', alkaline_phosphatase: 'Liver',
  bilirubin: 'Liver', albumin: 'Liver', total_protein: 'Liver',
  adjusted_calcium: 'Bone', calcium: 'Bone', phosphate: 'Bone',
  pth: 'Bone', vitamin_d: 'Bone', magnesium: 'Bone',
  haemoglobin: 'Haematology', haematocrit: 'Haematology', wbc: 'Haematology',
  rbc: 'Haematology', platelets: 'Haematology', mcv: 'Haematology',
  mch: 'Haematology', mchc: 'Haematology', ferritin: 'Haematology',
  rdw: 'Haematology', neutrophils: 'Haematology', lymphocytes: 'Haematology',
};

const DISPLAY_OVERRIDES: Record<string, string> = {
  egfr: 'eGFR', pth: 'PTH', alt: 'ALT', ast: 'AST', ggt: 'GGT',
  wbc: 'WBC', rbc: 'RBC', mcv: 'MCV', mch: 'MCH', mchc: 'MCHC',
  rdw: 'RDW', hba1c: 'HbA1c', crp: 'CRP',
};

export function panelFor(marker: string): Panel {
  return PANEL_MAP[marker] ?? 'Other';
}

export function displayName(marker: string): string {
  return (
    DISPLAY_OVERRIDES[marker] ??
    marker.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard && npx vitest run src/markers.test.ts`
Expected: PASS (5/5).

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/markers.ts dashboard/src/markers.test.ts
git commit -m "feat(dashboard): marker panel map and display names"
```

---

### Task 9: Access-key storage and API client (`storage.ts`, `api.ts`)

**Files:**
- Create: `dashboard/src/storage.ts`, `dashboard/src/api.ts`

No unit test — `storage.ts` is a thin localStorage wrapper and `api.ts` is network glue; both are exercised by the manual smoke test in Task 16.

- [ ] **Step 1: Write `storage.ts`**

```ts
const KEY = 'blood-dashboard-access-key';

export function getKey(): string | null {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function setKey(value: string): void {
  try {
    localStorage.setItem(KEY, value);
  } catch {
    /* storage unavailable — key simply won't persist */
  }
}

export function clearKey(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* no-op */
  }
}
```

- [ ] **Step 2: Write `api.ts`**

```ts
import { ApiResponseSchema, type ApiResponse } from './schemas';

export type ApiErrorCode = 'unauthorized' | 'network' | 'bad_data' | 'server';

export class ApiError extends Error {
  constructor(public code: ApiErrorCode, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export async function fetchAll(key: string): Promise<ApiResponse> {
  let res: Response;
  try {
    res = await fetch('/api/blood-tests', {
      headers: { Authorization: `Bearer ${key}` },
    });
  } catch {
    throw new ApiError('network', 'Could not reach the server.');
  }

  if (res.status === 401) throw new ApiError('unauthorized', 'Access key rejected.');
  if (!res.ok) throw new ApiError('server', `Server error (${res.status}).`);

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new ApiError('bad_data', 'Server returned an invalid response.');
  }

  const parsed = ApiResponseSchema.safeParse(body);
  if (!parsed.success) {
    throw new ApiError('bad_data', 'Response did not match the expected shape.');
  }
  return parsed.data;
}
```

- [ ] **Step 3: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard/src/storage.ts dashboard/src/api.ts
git commit -m "feat(dashboard): access-key storage and API client"
```

---

### Task 10: Key-entry screen (`screens/KeyEntry.tsx`)

**Files:**
- Create: `dashboard/src/screens/KeyEntry.tsx`

- [ ] **Step 1: Write `KeyEntry.tsx`**

```tsx
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
```

Note: the submit button is `type="button"` with an explicit handler (the form's `onSubmit` covers Enter); this avoids the implicit-submit footgun noted in the PWA work.

- [ ] **Step 2: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/screens/KeyEntry.tsx
git commit -m "feat(dashboard): key-entry screen"
```

---

### Task 11: App state machine (`App.tsx`)

**Files:**
- Modify: `dashboard/src/App.tsx` (replace the Task 2 placeholder)

- [ ] **Step 1: Write `App.tsx`**

```tsx
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
```

- [ ] **Step 2: Create a temporary `Dashboard.tsx` stub**

So the tree type-checks cleanly now and every later task commits green. Task 15 replaces this stub with the real screen.

`dashboard/src/screens/Dashboard.tsx`:
```tsx
import type { BloodTestRow } from '../schemas';

export function Dashboard({ rows }: { rows: BloodTestRow[] }) {
  return (
    <div className="min-h-screen bg-slate-900 p-8 text-slate-100">
      {rows.length} rows loaded
    </div>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard/src/App.tsx dashboard/src/screens/Dashboard.tsx
git commit -m "feat(dashboard): app state machine with Dashboard stub"
```

---

### Task 12: Filter bar (`components/FilterBar.tsx`)

**Files:**
- Create: `dashboard/src/components/FilterBar.tsx`

- [ ] **Step 1: Write `FilterBar.tsx`**

```tsx
import { PHASES } from '../schemas';

export type Granularity = 'month' | 'date';

export type FilterState = {
  phases: string[];
  from: string;
  to: string;
  granularity: Granularity;
  marker: string;
};

type Props = {
  filter: FilterState;
  markers: string[];
  onChange: (next: FilterState) => void;
};

export function FilterBar({ filter, markers, onChange }: Props) {
  const set = (patch: Partial<FilterState>) => onChange({ ...filter, ...patch });
  const inputType = filter.granularity === 'month' ? 'month' : 'date';

  return (
    <div className="flex flex-wrap items-end gap-3 border-b border-slate-700 bg-slate-800 p-3">
      <label className="flex flex-col text-xs text-slate-400">
        Phase
        <select
          value={filter.phases[0] ?? 'all'}
          onChange={(e) =>
            set({ phases: e.target.value === 'all' ? [] : [e.target.value] })
          }
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          <option value="all">All phases</option>
          {PHASES.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        Granularity
        <select
          value={filter.granularity}
          onChange={(e) => set({ granularity: e.target.value as Granularity })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          <option value="month">Month</option>
          <option value="date">Date</option>
        </select>
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        From
        <input
          type={inputType}
          value={filter.from}
          onChange={(e) => set({ from: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        />
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        To
        <input
          type={inputType}
          value={filter.to}
          onChange={(e) => set({ to: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        />
      </label>

      <label className="flex flex-col text-xs text-slate-400">
        Marker (trend)
        <select
          value={filter.marker}
          onChange={(e) => set({ marker: e.target.value })}
          className="mt-1 rounded bg-slate-700 px-2 py-1 text-sm text-slate-100"
        >
          {markers.map((m) => (
            <option key={m} value={m}>{m}</option>
          ))}
        </select>
      </label>
    </div>
  );
}
```

Note: a native `<input type="month">` yields `YYYY-MM` and `<input type="date">` yields `YYYY-MM-DD` — both already valid bounds for `filterRows`. An empty string means "no bound".

- [ ] **Step 2: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/components/FilterBar.tsx
git commit -m "feat(dashboard): filter bar (phase, range, granularity, marker)"
```

---

### Task 13: Scorecard tile and grid (`components/ScorecardTile.tsx`, `Scorecard.tsx`)

**Files:**
- Create: `dashboard/src/components/ScorecardTile.tsx`, `dashboard/src/components/Scorecard.tsx`

- [ ] **Step 1: Write `ScorecardTile.tsx`**

```tsx
import type { MarkerSummary } from '../lib/scorecard';
import { displayName } from '../markers';

const STATUS_STYLE: Record<MarkerSummary['status'], string> = {
  in: 'border-emerald-600 bg-emerald-950',
  out: 'border-red-600 bg-red-950',
  unknown: 'border-slate-600 bg-slate-800',
};

const ARROW: Record<NonNullable<MarkerSummary['direction']>, string> = {
  up: '↑', down: '↓', flat: '→',
};

type Props = {
  summary: MarkerSummary;
  onSelect: (marker: string) => void;
};

export function ScorecardTile({ summary, onSelect }: Props) {
  const { marker, latest, delta, direction, status } = summary;
  return (
    <button
      type="button"
      onClick={() => onSelect(marker)}
      className={`flex flex-col rounded border p-3 text-left ${STATUS_STYLE[status]}
                  hover:brightness-125`}
    >
      <span className="text-xs text-slate-400">{displayName(marker)}</span>
      <span className="text-lg font-semibold text-slate-100">
        {latest ? `${latest.value} ${latest.unit}` : '—'}
      </span>
      {delta != null && direction && (
        <span className="text-xs text-slate-400">
          {ARROW[direction]} {Math.abs(delta)}
        </span>
      )}
    </button>
  );
}
```

- [ ] **Step 2: Write `Scorecard.tsx`**

```tsx
import type { BloodTestRow } from '../schemas';
import { summarize } from '../lib/scorecard';
import { panelFor, PANELS, type Panel } from '../markers';
import { ScorecardTile } from './ScorecardTile';

type Props = {
  rows: BloodTestRow[]; // already filtered to phase + date range
  onSelectMarker: (marker: string) => void;
};

export function Scorecard({ rows, onSelectMarker }: Props) {
  if (rows.length === 0) {
    return <p className="p-6 text-slate-400">No results for these filters.</p>;
  }

  const byMarker = new Map<string, BloodTestRow[]>();
  for (const r of rows) {
    const list = byMarker.get(r.marker) ?? [];
    list.push(r);
    byMarker.set(r.marker, list);
  }

  const summaries = [...byMarker.entries()]
    .map(([marker, markerRows]) => summarize(marker, markerRows))
    .sort((a, b) => a.marker.localeCompare(b.marker));

  const byPanel = new Map<Panel, typeof summaries>();
  for (const s of summaries) {
    const panel = panelFor(s.marker);
    const list = byPanel.get(panel) ?? [];
    list.push(s);
    byPanel.set(panel, list);
  }

  return (
    <div className="space-y-6 p-4">
      {PANELS.filter((p) => byPanel.has(p)).map((panel) => (
        <section key={panel}>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400">
            {panel}
          </h2>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
            {byPanel.get(panel)!.map((s) => (
              <ScorecardTile key={s.marker} summary={s} onSelect={onSelectMarker} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard/src/components/ScorecardTile.tsx dashboard/src/components/Scorecard.tsx
git commit -m "feat(dashboard): panel-grouped scorecard"
```

---

### Task 14: Trend chart (`components/TrendChart.tsx`)

**Files:**
- Create: `dashboard/src/components/TrendChart.tsx`

- [ ] **Step 1: Write `TrendChart.tsx`**

```tsx
import {
  ComposedChart, Line, Area, XAxis, YAxis, Tooltip, CartesianGrid,
  ReferenceLine, Brush, ResponsiveContainer,
} from 'recharts';
import type { BloodTestRow } from '../schemas';
import { displayName } from '../markers';

type Props = {
  marker: string;
  rows: BloodTestRow[]; // already filtered to this marker + phase + range
};

type Point = {
  datetime: string;
  pre: number | null;
  post: number | null;
  plain: number | null;
  range: [number, number] | null;
};

// Phase boundary dates (from the spec's data model).
const PHASE_BOUNDARIES = ['2023-10-16', '2026-02-01'];

function toPoints(rows: BloodTestRow[]): Point[] {
  return rows
    .filter((r) => !r.qualitative)
    .slice()
    .sort((a, b) => a.datetime.localeCompare(b.datetime))
    .map((r) => ({
      datetime: r.datetime,
      pre: r.timing === 'pre' ? r.value : null,
      post: r.timing === 'post' ? r.value : null,
      plain: r.timing === '' ? r.value : null,
      range:
        r.ref_low != null && r.ref_high != null ? [r.ref_low, r.ref_high] : null,
    }));
}

export function TrendChart({ marker, rows }: Props) {
  const data = toPoints(rows);

  if (data.length === 0) {
    return <p className="p-6 text-slate-400">No numeric readings for {displayName(marker)} in this range.</p>;
  }

  const hasPrePost = data.some((d) => d.pre != null || d.post != null);

  return (
    <div className="p-4">
      <h2 className="mb-2 text-sm font-semibold text-slate-200">{displayName(marker)}</h2>
      <ResponsiveContainer width="100%" height={360}>
        <ComposedChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 0 }}>
          <CartesianGrid stroke="#334155" strokeDasharray="3 3" />
          <XAxis dataKey="datetime" tick={{ fontSize: 11, fill: '#94a3b8' }} minTickGap={32} />
          <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} />
          <Tooltip
            contentStyle={{ background: '#1e293b', border: '1px solid #334155', fontSize: 12 }}
          />
          <Area
            dataKey="range"
            type="stepAfter"
            stroke="none"
            fill="#22d3ee"
            fillOpacity={0.12}
            connectNulls
            isAnimationActive={false}
          />
          {PHASE_BOUNDARIES.map((d) => (
            <ReferenceLine key={d} x={data.find((p) => p.datetime.slice(0, 10) >= d)?.datetime}
              stroke="#64748b" strokeDasharray="4 4" />
          ))}
          {hasPrePost ? (
            <>
              <Line dataKey="pre" name="Pre" stroke="#22d3ee" dot connectNulls
                isAnimationActive={false} />
              <Line dataKey="post" name="Post" stroke="#f59e0b" dot connectNulls
                isAnimationActive={false} />
            </>
          ) : (
            <Line dataKey="plain" name={displayName(marker)} stroke="#22d3ee" dot
              connectNulls isAnimationActive={false} />
          )}
          <Brush dataKey="datetime" height={20} stroke="#475569" fill="#0f172a" />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
```

Note: the reference band is a Recharts range `<Area>` (its `dataKey` resolves to a `[low, high]` tuple) drawn with `type="stepAfter"`, so it visibly steps where the reference range drifts. `connectNulls` lets the band span points whose range is missing.

- [ ] **Step 2: Type-check**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard/src/components/TrendChart.tsx
git commit -m "feat(dashboard): single-marker trend chart with stepped reference band"
```

---

### Task 15: Dashboard screen wiring (`screens/Dashboard.tsx`)

**Files:**
- Modify: `dashboard/src/screens/Dashboard.tsx` (replace the Task 11 stub)

- [ ] **Step 1: Replace the `Dashboard.tsx` stub with the real screen**

```tsx
import { useMemo, useState } from 'react';
import type { BloodTestRow } from '../schemas';
import { filterRows } from '../lib/queryFilter';
import { FilterBar, type FilterState } from '../components/FilterBar';
import { Scorecard } from '../components/Scorecard';
import { TrendChart } from '../components/TrendChart';

type Props = { rows: BloodTestRow[] };
type Tab = 'scorecard' | 'trend';

export function Dashboard({ rows }: Props) {
  const markers = useMemo(
    () => [...new Set(rows.map((r) => r.marker))].sort(),
    [rows],
  );

  const [tab, setTab] = useState<Tab>('scorecard');
  const [filter, setFilter] = useState<FilterState>({
    phases: ['home-hd'],
    from: '',
    to: '',
    granularity: 'month',
    marker: markers[0] ?? '',
  });

  const scoped = useMemo(
    () =>
      filterRows(rows, {
        phase: filter.phases,
        from: filter.from || undefined,
        to: filter.to || undefined,
      }),
    [rows, filter.phases, filter.from, filter.to],
  );

  const trendRows = useMemo(
    () => scoped.filter((r) => r.marker === filter.marker),
    [scoped, filter.marker],
  );

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      <FilterBar filter={filter} markers={markers} onChange={setFilter} />

      <div className="flex gap-2 border-b border-slate-700 bg-slate-800 px-3">
        {(['scorecard', 'trend'] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm capitalize ${
              tab === t ? 'border-b-2 border-cyan-400 text-cyan-300' : 'text-slate-400'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'scorecard' ? (
        <Scorecard
          rows={scoped}
          onSelectMarker={(marker) => {
            setFilter((f) => ({ ...f, marker }));
            setTab('trend');
          }}
        />
      ) : (
        <>
          <TrendChart marker={filter.marker} rows={trendRows} />
          <ResultsTable rows={trendRows} />
        </>
      )}
    </div>
  );
}

function ResultsTable({ rows }: { rows: BloodTestRow[] }) {
  if (rows.length === 0) return null;
  const sorted = [...rows].sort((a, b) => b.datetime.localeCompare(a.datetime));
  return (
    <table className="m-4 w-[calc(100%-2rem)] text-left text-sm">
      <thead className="text-xs uppercase text-slate-400">
        <tr>
          <th className="py-1 pr-4">Date</th>
          <th className="py-1 pr-4">Value</th>
          <th className="py-1 pr-4">Range</th>
          <th className="py-1 pr-4">Timing</th>
          <th className="py-1">Note</th>
        </tr>
      </thead>
      <tbody className="text-slate-300">
        {sorted.map((r) => (
          <tr key={`${r.marker}-${r.lab_id}`} className="border-t border-slate-800">
            <td className="py-1 pr-4">{r.datetime.slice(0, 16).replace('T', ' ')}</td>
            <td className="py-1 pr-4">
              {r.qualitative ? r.unit : `${r.value} ${r.unit}`}
            </td>
            <td className="py-1 pr-4">
              {r.ref_low != null && r.ref_high != null ? `${r.ref_low}–${r.ref_high}` : '—'}
            </td>
            <td className="py-1 pr-4">{r.timing || '—'}</td>
            <td className="py-1">{r.note || '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

Note: qualitative rows (`value === 0`, text unit) are excluded from the chart line by `TrendChart` and appear in `ResultsTable` showing `r.unit` (the result text) instead of a numeric value.

- [ ] **Step 2: Full type-check (now everything exists)**

Run: `cd dashboard && npm run typecheck`
Expected: no errors.

- [ ] **Step 3: Run the full test suite**

Run: `cd dashboard && npm test`
Expected: all suites pass (schemas, csv, queryFilter, scorecard, markers).

- [ ] **Step 4: Production build**

Run: `cd dashboard && npm run build`
Expected: `dist/` produced, no errors.

- [ ] **Step 5: Commit**

```bash
git add dashboard/src/screens/Dashboard.tsx
git commit -m "feat(dashboard): dashboard screen, tabs, results table"
```

---

### Task 16: README, deploy setup, and end-to-end verification

**Files:**
- Create: `README.md` (repo root — replaces the PWA README moved to `pwa/`)

- [ ] **Step 1: Write the root `README.md`**

```markdown
# treatment_tracker

Two apps supporting home haemodialysis:

- **`pwa/`** — Home HD session tracker (Android PWA). See `pwa/README.md`.
- **`dashboard/`** — Blood test analytics dashboard + query endpoint.

## Dashboard

Design: `docs/superpowers/specs/2026-05-22-blood-test-dashboard-design.md`

### Develop
```bash
cd dashboard
npm install
npm run dev          # regenerates data/blood_tests.json, then starts Vite
```

### Test the endpoint locally
```bash
cd dashboard
npm run build
echo 'DASHBOARD_KEY=<dev-key>' > .dev.vars   # gitignored
npx wrangler pages dev dist
```

### Deploy
One-time:
```bash
cd dashboard
npx wrangler pages project create treatment-dashboard --production-branch=main
npx wrangler pages secret put DASHBOARD_KEY --project-name=treatment-dashboard
```
Each deploy:
```bash
cd dashboard
npm run build
npx wrangler pages deploy dist --project-name=treatment-dashboard --branch=main --commit-dirty=true
```

The monthly data refresh is: edit `scripts/pkb_backfill/blood_tests.csv`, then redeploy.
```

- [ ] **Step 2: Deploy the dashboard (run by the user)**

This step needs the user's Cloudflare account. The user runs the one-time setup and first deploy from `dashboard/` per the README. Confirm the production URL is reachable and returns the dashboard.

- [ ] **Step 3: End-to-end smoke test**

Against the deployed URL:
1. Open the dashboard → key-entry screen appears.
2. Enter the wrong key → expect "Access key rejected" and return to key entry.
3. Enter the correct `DASHBOARD_KEY` → dashboard loads.
4. Scorecard tab → markers grouped under Renal / Liver / Bone / Haematology / Other; tiles show value + delta + in/out-of-range color.
5. Click a tile → switches to Trend tab for that marker; line chart renders with a stepped reference band.
6. Change phase to "All phases" → phase boundary lines appear; admission-era data is visible.
7. Set a month range in the filter bar → scorecard and trend both narrow.
8. `curl -H 'Authorization: Bearer <key>' '<url>/api/blood-tests?marker=creatinine&from=2026-01'` → JSON with `count` and `rows`.

- [ ] **Step 4: PWA regression check**

```bash
cd pwa && npm run build && npm test
```
Expected: PWA still builds and its test passes — confirms the Task 1 move did not break it.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add README.md
git commit -m "docs: root README for the two-app repo"
```

---

## Self-review notes

- **Spec coverage:** repo restructure (T1–2), gitignore safeguard (T2), data pipeline + baked JSON (T4, T6), endpoint with `marker`/`from`/`to`/`phase` + auth + errors (T5–6), key-entry/loading/error/ready states (T9–11), filter bar with phase + granularity (T12), panel-grouped scorecard (T7–8, T13), trend chart with stepped band + pre/post + phase lines + brush (T14), results table with qualitative handling (T15), testing + PWA regression (T15–16). Compare view is correctly absent (v2).
- **No placeholders:** the `PANEL_MAP` is a complete, working function with a starter map; unmapped markers resolve to `Other` by design — not a placeholder.
- **Type consistency:** `BloodTestRow` is defined once in `schemas.ts` and imported everywhere; `QueryParams`, `FilterState`, `MarkerSummary`, `ApiError` names are used consistently across tasks.
- **Clean commits:** every task ends with a green typecheck — T11 ships a one-line `Dashboard.tsx` stub so Tasks 12–14 type-check cleanly, and T15 replaces the stub with the real screen.
