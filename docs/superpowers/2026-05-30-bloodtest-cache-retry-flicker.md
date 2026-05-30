# Blood Tests cache + range sync, Cloud Run retry, Treatment input flicker

<!-- 2026-05-30 -->

Spec + implementation plan for three independent changes. Planned while a treatment
session was running (no app changes allowed at the time). Nothing here has been
implemented yet — this is the design of record to execute later.

## Problem statement

1. **Intermittent "Failed to fetch" on the Blood Tests tab.** Investigated against
   the live `homehd-personal` GCP project (read-only) on 2026-05-30:
   - Warm path is healthy (direct curl to `/api/blood-tests` → 401 in ~40–65ms).
   - `/api/blood-tests` logged **zero 5xx / 503 / 504 / OOM** over 7 days — only a
     normal 401. The only 500s were `/api/fitness/sync`, unrelated.
   - The service **scales to zero and cold-starts ~hourly** (`Starting new instance.
     Reason: AUTOSCALING … no existing capacity`). Config: `homehd-api`,
     **min-instances = 0**, 256Mi, 30s timeout, europe-west2.
   - A browser `TypeError: Failed to fetch` is thrown **only when no HTTP response is
     received** at the transport layer (a 5xx would resolve with a readable Response).
   - **Conclusion:** the failing requests die in the gap between "request sent" and
     "first response" during a scale-from-zero cold start, with no server-side trace.
     Worsened because the Blood Tests read currently downloads the **full dataset**.

2. **No client cache + no range request.** `fetchAll(auth)` calls `/api/blood-tests`
   with **no params**, downloading every row on every tab open. The server already
   supports `from` / `to` / `marker` / `phase` (`api/src/handlers/bloodTests.ts`,
   `api/src/lib/queryFilter.ts`) — the client simply never passes them.

3. **No retry.** `cloudGet` / `cloudPost` (`frontend/src/api/cloudRun.ts`) throw a
   `network` error on the **first** failed `fetch`. A transient cold-start blip is not
   retried, so it surfaces straight to the user.

4. **Treatment input flicker on phone.** When entering values in the Treatment tab and
   tapping the keyboard's "Next" to move to the next box, the UI flicks slightly.
   **Hypothesis (unverified):** `useKeyboardAvoidance` (mounted app-wide in
   `AppShell`) runs on every input `focusin` → `setTimeout(300ms)` →
   `scrollIntoView({ block: 'nearest', behavior: 'smooth' })`. Box-to-box focus
   movement fires a smooth-scroll animation each time even when the field is already
   visible — the flick.

## Design decisions (from discussion)

- **Cache-first reads.** Render from local cache immediately; revalidate in the
  background. Common case (open tab, look at trends) becomes **zero-network**, so the
  cold start isn't on the path → the "Failed to fetch" symptom can't occur there.
- **Default cached window: last 6 months.** ~6 tests × ~20 markers ≈ ~120 rows vs the
  full ~2.4k. Smaller payload, faster load, smaller cold-start window.
- **Download only the selected range**, fetching only the **uncovered** slice on range
  change (cache-first per range), merging into the cache.
- **Manual Sync button** re-fetches the **currently selected range** and overwrites
  those rows. This deliberately replaces automatic change-detection: it also picks up
  **in-place edits** (e.g. the manual `timing` corrections) that a `(count, max date)`
  check would miss. Single writer (you) → no version-counter machinery needed.
- **Keep min-instances = 0** (£0). Caching + retry remove the need for an always-on
  instance.
- **Do not optimize the server now.** The handler does `collection.get()` then filters
  in memory, so range params cut payload but not Firestore read count. Acceptable at
  current volume (most data is the baked static JSON; Firestore holds only recent
  rows). Noted, not actioned.

## Repo facts (verified 2026-05-30)

- Structure is `frontend/` + `api/` (not the `pwa/` + `dashboard/` named in the vault note).
- `frontend/src/api/cloudRun.ts` — shared `cloudGet` / `cloudPost`, `CloudRunError`
  with codes `unauthorized | network | bad_data | server`. **Single place to add retry.**
- `frontend/src/routes/BloodTests/api.ts` — `fetchAll` (no params today).
- `frontend/src/routes/BloodTests/index.tsx` — hard `loading → fetch → error` flow,
  no cache.
- `frontend/src/routes/BloodTests/components/FilterBar.tsx` — month/year From/To
  selects; `FilterState` already has `from`/`to` as `YYYY-MM`.
- `frontend/src/routes/Treatment/storage.ts` — clean IndexedDB KV pattern (DB
  `hd-tracker`, store `kv`) to mirror for the Blood Tests cache. **Reuse the same DB.**
- `frontend/src/hooks/useKeyboardAvoidance.ts` — the flicker suspect.
- Server range support already present and validated (`isValidBound`, `from`/`to`).

---

## Part A — Blood Tests: cache + range + sync button

**A1. Range-aware fetch.** Replace `fetchAll(auth)` with `fetchRange(auth, { from, to })`
that passes `from`/`to` (format `YYYY-MM`, already what `FilterState` uses) to the
existing server params. Keep the zod `ApiResponseSchema` validation.

**A2. Cache module** — new `frontend/src/routes/BloodTests/storage.ts`, mirroring
`Treatment/storage.ts`, reusing DB `hd-tracker`:
- `getCachedRows()` / `mergeCachedRows(rows)` — keyed by `${lab_id}_${marker}`
  (matches the server doc id and the table `key` already used in `index.tsx`).
- `getCoverage()` / `setCoverage({ from, to })` — the cached date span.
- `getLastSynced()` / `setLastSynced(ts)`.

**A3. Cache-first flow** in `index.tsx`:
1. On mount, load cache; if non-empty, render immediately (no spinner).
2. If cache empty → auto-fetch last 6 months once, populate cache.
3. On range change → compute the uncovered slice vs `coverage`; fetch only that;
   merge; extend coverage.

**A4. Sync button** (in `FilterBar` or the tab header): re-fetch the currently
selected range, overwrite those rows in cache, update `last_synced`. Show a small
"last synced …" label.

**A5. Graceful background-failure.** If a background/refresh fetch fails (cold start),
keep showing cached data and surface a small non-blocking notice — not the current
full-screen error. Full-screen error stays only for the genuine empty-cache + fetch-fail case.

**Tests (TDD where logic is pure):**
- Coverage math: given cached span + new selected range → correct uncovered slice(s).
- Merge: new rows overwrite same `${lab_id}_${marker}`; in-place edits replace.

---

## Part B — Cloud Run retry (covers Treatment writes + all reads)

**B1.** Add `withRetry` in `cloudRun.ts`: 2–3 attempts, backoff ~1s / 3s, retry **only**
on `CloudRunError.code === 'network'`. Never retry `unauthorized` / `bad_data` /
`server` (4xx/validation). Wrap both `cloudGet` and `cloudPost`.

**B2.** Add an `AbortController` timeout (~35s, above the server's 30s) so a hung
cold-start request fails cleanly as `network` instead of hanging the browser; a
timed-out attempt counts toward the retry budget.

Covers: Blood Tests reads, Treatment `saveSession` (PreTreatment), readings, post
update, and the inventory/heparin `cloudGet`.

**Tests:** mock `fetch` — network error then success → resolves; 401 → no retry,
throws immediately; all attempts fail → throws `network`.

---

## Part C — Treatment input flicker (verify-on-device FIRST)

Per systematic-debugging: this is an **unverified hypothesis**. Do **not** edit before
reproducing and confirming the cause on the actual phone.

**C0. Reproduce + confirm (required before any code change).**
- On the phone, Treatment → Pre-treatment, tap a NumberField, hit keyboard "Next".
- Confirm the flick coincides with the focus change.
- Confirm cause by instrumenting / observing: the `focusin` handler firing a
  `scrollIntoView({ behavior: 'smooth' })` on a field that is already fully visible.
- If the cause is something else (e.g. `--kb` var driving layout, re-render), STOP and
  re-plan — do not apply the fix below blindly.

**C1. Smallest fix (only after C0 confirms):** in `useKeyboardAvoidance`'s `onFocusIn`,
scroll **only if the focused input is actually obscured** by the keyboard — compare its
`getBoundingClientRect().bottom` against `visualViewport.height`; skip entirely when
already visible (the box-to-box "Next" case). 

**C2. If still janky:** change `behavior: 'smooth'` → `'auto'` (instant), removing the
animation.

**Verify:** re-test the Next-key flow on device; confirm no flick and that genuinely
off-screen fields still scroll into view.

---

## Sequencing

1. **Part B** (retry) — tiny, self-contained, immediate reliability win.
2. **Part C** — do C0 (reproduce/verify) first; C1/C2 only if confirmed.
3. **Part A** (cache + range + sync) — the bulk; independent of B/C.

All three are independent and can ship separately. None require touching the server or
changing `min-instances`.
