# Fitness Tab Redesign — Insight Tiles (Sleep, HRV, RHR, Respiratory)

<!-- combined spec + implementation plan — PLAN ONLY, build deferred -->

Date: 2026-06-20
Status: **IMPLEMENTED + backend live** (rev homehd-api-00040-mcq, 2026-06-20). Flutter
app rebuild/deploy (web + APK) is the only remaining step to surface it in the deployed app.
Related: `2026-05-27-fitness-gcs-ingest.md`, `2026-05-31-fitness-summary-screen.md`

## Summary

Replace the current Fitness screen — a sync/pipeline **diagnostics dashboard** (latest-reading
grid + per-type pipeline status + GCS bytes) — with a **Google-Health-style insight view**: a
2-column grid of metric tiles, each showing a headline number, that expand on tap to a detail
screen with charts. First tiles: **Sleep, HRV, Resting HR, Respiratory rate**. The design is a
**pluggable metric registry** so adding a tile later (Steps, SpO₂, …) is one entry.

The current `/api/fitness/summary` only returns the *latest* value per type, so charts need two
new read-only history endpoints. Flutter has no GCS credentials, so all data stays behind the
existing bearer-guarded `/api/fitness/*` surface.

## Goals

1. Fitness screen = 2-column tile grid of insight tiles; the old diagnostics view is **removed**.
2. Each tile: icon, label, headline value, and (where meaningful) a direction arrow vs the
   patient's personal baseline. Tap → detail screen with a chart.
3. Sleep tile headline = **total sleep time**; detail = stage breakdown + night hypnogram +
   nightly trend.
4. HRV / RHR / Respiratory tiles: headline + arrow vs trailing baseline; detail = trend line.
5. Adding a future metric is trivial (registry entry + extraction config).

## Non-goals (YAGNI)

- Steps & SpO₂ tiles (deferrable later via the registry — extraction for both already exists).
- **Any derived "readiness" or "sleep" score.** No invented composite numbers. (Decided: a
  derived readiness score is misleading for a home-HD patient whose HRV/RHR swing with fluid
  status and the dialysis cycle. HRV-vs-baseline is the honest substitute.)
- Dense raw heart-rate charts, cross-metric correlation, any editing/writes.
- New screenshot goldens unless requested.

## Data reality (verified against live GCS files, 2026-06-20)

9 synced types; **no readiness type and no sleep/readiness score exist** (Fitbit-proprietary, not
in the Google Health export). What the first tiles need is all present:

| Tile | Source type | Fields used |
|---|---|---|
| Sleep | `sleep` | `summary.minutesAsleep`, `summary.minutesAwake`, `summary.stagesSummary[].{type,minutes}`, `sleep.stages[].{startTime,endTime,type}` (AWAKE/LIGHT/DEEP/REM), `sleep.type` (`STAGES` vs classic), `interval` |
| HRV | `daily-heart-rate-variability` | `averageHeartRateVariabilityMilliseconds`, `date` |
| Resting HR | `daily-resting-heart-rate` | `beatsPerMinute`, `date` |
| Respiratory rate | `respiratory-rate-sleep-summary` | `deepSleepStats.breathsPerMinute`, `date` (same field the summary card uses) |

`fl_chart ^1.2.0` is already a dependency. No baseline computation exists to reuse — only the
established principle (chat prompt): *HRV is relative to the patient's personal baseline; no
absolute population cutoffs.* This design honors it with a per-metric trailing-window baseline.

## Architecture

### Backend (new, bearer-guarded; pure helpers + thin handlers)

**DRY refactor first.** `fitnessSummary.ts`'s `LIST_CONFIG` (per-type `getDate`/`getValue`) is the
single source of how to read each type. Extract it into a shared `fitnessExtract.ts` imported by
both the existing summary path (latest value) and the new series path (all values). No behavior
change to `/summary`.

**`GET /api/fitness/series?type=&from=&to=`** → `{ type, points: [{ date, value }] }`, ascending
by date. Uses the shared per-type extractor over every data point in the date-windowed files.
Default window: last 30 days. Pure helper `buildSeries(deps, {type, from, to})` mirrors
`buildSummary`'s deps shape (`listFiles`/`readJson`); unit-tested.

**`GET /api/fitness/sleep?from=&to=`** → `{ nights: [{ date, minutesAsleep, minutesAwake,
stages: [{type, minutes}], hypnogram: [{type, start, end}], hasStages }] }`, newest first.
`hasStages=false` for classic nights (no `sleep.stages`) → `hypnogram: []`, `stages: []`, total
only. Pure helper `parseSleepNight(file)` + `buildSleep(deps, {from,to})`; unit-tested incl. the
classic-night degrade. Default window: last 30 nights.

Both handlers follow the existing per-type isolation philosophy (one bad file → skip, don't abort).

### Flutter

**Metric registry** (`fitness/metric_tiles.dart`): a list of
```
MetricTile {
  String key;            // 'sleep' | 'daily-heart-rate-variability' | ...
  String label; IconData icon;
  Headline Function(FitnessSummary) headline;   // value + optional sub
  Arrow?   Function(List<num>) trend;            // today vs baseline, or null
  Widget   Function(BuildContext) detail;        // tap target
}
```
The screen maps the registry to a 2-column `GridView` of cards. Adding Steps/SpO₂ later = append
an entry. Headlines come from the existing `/summary` (fast first paint); details lazy-fetch
`/series` or `/sleep`.

**Tiles (first set):**
- **Sleep** — headline `7h 42m` (from `minutesAsleep`); sub = stage mini-bar (deep/light/rem/awake
  proportions). Detail: latest-night hypnogram + nightly total-sleep bar trend + stage breakdown.
  Classic nights → total + "no stage data".
- **HRV / Resting HR / Respiratory** — headline value + arrow (▲/▼/▬) vs **trailing 7-day median**
  (excludes today), computed client-side from the `/series` points. Arrows are **purely
  directional** (up/down/steady) with no good/bad coloring — avoids clinical value judgments.
  Detail: `fl_chart` line with a shaded baseline band.

**Baseline/arrow helper** (`fitness/baseline.dart`, pure): `median(window)` and
`arrow(today, baseline, tolerancePct)` → up/down/steady. Unit-tested.

**Reused as-is:** cache (`cacheStoreProvider` + pull-to-refresh), `WidgetsBindingObserver`
staleness refresh, `screenContextProvider.setRoute('/fitness')`, the AI `FilterFitness` listener,
the PopScope→treatment back behavior, and the app-bar **Sync now** button.

**Removed:** `_latestCard`, `_pipelineCard`, `_healthLine`, the GCS-bytes line, and the
`_toJson`/pipeline plumbing they need (kept only if still used by the cache shape — verify during
build).

### Data flow
load → `/summary` (cached, fast) → tiles render headlines → tap tile → `/series`|`/sleep` (cached
per metric) → detail chart. Failures fall back to cache, else a muted "no recent data" tile.

## Testing

- **Backend (vitest):** `buildSeries` (date-windowed, ascending, value extraction per type);
  `parseSleepNight` (stage minutes, hypnogram, classic-night degrade); shared-extractor refactor
  leaves `/summary` tests green.
- **Flutter (widget tests):** registry renders N tiles; sleep tile shows total + mini-bar; trend
  arrow up/down/steady from a fixed series; classic-night detail degrades; error → muted tile.
- `baseline.dart` median/arrow pure unit tests.
- Full `api` (`npm test`) + `flutter test` green.

## Implementation plan (TDD, ordered) — deferred

1. **Backend extractor refactor** — pull `LIST_CONFIG`/`getDate`/`getValue` into
   `fitnessExtract.ts`; `/summary` imports it; tests stay green.
2. **`/series` endpoint** — `buildSeries` pure helper + handler + tests.
3. **`/sleep` endpoint** — `parseSleepNight` + `buildSleep` + handler + tests (incl. classic night).
4. **Flutter API client** — add `fetchSeries(type,from,to)` / `fetchSleep(from,to)` +
   models to `fitness_api.dart`.
5. **Baseline helper** — `baseline.dart` (median, arrow) + tests.
6. **Metric registry + tile grid** — `metric_tiles.dart`; rewrite `fitness_screen.dart` body to
   the 2-column grid; remove diagnostics widgets; keep sync/cache/AI-context plumbing.
7. **Detail screens** — sleep (hypnogram + trend + breakdown), generic trend-line (HRV/RHR/Resp).
8. **Verify** — api + flutter tests green; run app, screenshot the new grid + a detail; breadcrumb
   to the fitness notes.

## Verification

- `cd api && npm test` green; `cd flutter && flutter test` green; `flutter analyze` clean.
- Manual: open `/fitness` → 4 tiles with headlines; tap Sleep → hypnogram; tap HRV → trend+band.
