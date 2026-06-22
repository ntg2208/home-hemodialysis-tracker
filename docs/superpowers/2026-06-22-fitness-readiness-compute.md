# Fitness Readiness Compute (v1) — Design / Spec

**Status:** design approved (brainstorming 2026-06-22). Implementation plan to be appended below by the writing-plans step. Not started.

## Goal

A **deterministic** daily readiness signal — **REST / STEADY / PUSH** — computed from wearable metrics against the patient's personal 30-day baseline, modulated by the dialysis schedule, and cached to a self-explaining `daily_energy/{date}` Firestore doc. **Backend-only; no UI, no check-in, no LLM, no exercise recommendation in v1.**

## Where this sits (the bigger loop)

The patient's intended arc is **pipeline → analysis session → insight → agent skills**:
1. **Pipeline (this doc):** deterministic compute produces trustworthy daily readiness numbers (compute-then-narrate — the model never invents these).
2. **Analysis session (later):** an agent reasons over the accumulated `daily_energy` series *vs* literature (Brenner & Rector) + guidelines (UKKA/KDIGO) to surface patterns/anomalies.
3. **Insight → skills (later):** learnings crystallize into agent skills (the first consumer being the **exercise-pacing skill**, which reads `daily_energy`).

v1 builds step 1 only. It is the data foundation the exercise skill and the analysis session both depend on.

## Prior art grounding

Method copied from validated consumer recipes + HD/pacing research (full breadcrumb: vault note `Home HD Knowledge Base and Tracking System.md`, 2026-06-22 entries):
- **Oura-style** recency-weighted personal-baseline z-blend of HRV + RHR + sleep, with temperature deviation as an illness guard.
- **Dialysis-day modulation** + **HD safety guards** (fluid/infection) — the layer Fitbit structurally lacks.
- Data is available same-morning via the **freshen-today** pipeline (`raw/{type}/today/{date}.json`), shipped 2026-06-22; ≥30 days of archival history confirmed for every metric.

## Inputs (5 metrics)

| Metric | Source data type | Role | Direction |
|---|---|---|---|
| HRV (RMSSD) | `daily-heart-rate-variability` | Core recovery signal | higher = better (`+z`) |
| Resting HR | `daily-resting-heart-rate` | Core | lower = better (`−z`) |
| Sleep duration | `sleep` (`parseSleepNight`) | Core | higher = better, capped |
| Respiratory rate | `respiratory-rate-sleep-summary` | **Guard** (fluid) | deviation = penalty |
| Skin-temp deviation | `daily-sleep-temperature-derivations` | **Guard** (infection) | deviation = penalty |

Today's values come from the freshen `today/{date}.json` objects; baselines come from the archival `raw/{type}/{range}.json` series via the existing `extractSeries` (`fitnessSeries.ts`).

## Algorithm (A1 — weighted z-score blend; approved)

1. **Per-metric baseline** — `rollingBaseline(series, asOf, windowDays=30) → {mean, sd, n}`, **recency-weighted** (recent days weighted more, Oura-style; linear decay weights for v1).
2. **Per-metric z-score** — `z = (today − mean) / sd`, signed by direction (HRV `+`, RHR `−`, sleep `+` capped).
3. **Composite score (0–100)** — `clamp(50 + k·Σ(wᵢ·zᵢ), 0, 100)` over the **core three**, **HRV-dominant** default weights `HRV 0.5 / RHR 0.3 / sleep 0.2` (sum to 1.0, so `Σ(wᵢ·zᵢ)` is a weighted-mean z). Scaling `k = 10` → band edges fall at ±1 weighted-σ (see step 4). All four constants tunable.
4. **Band** — `score ≥ 60 → PUSH`, `40 ≤ score < 60 → STEADY`, `score < 40 → REST` (z=0 ⇒ ~50 ⇒ STEADY; thresholds tunable).
5. **Dialysis-day modulation** — if today is a scheduled dialysis day (fixed weekday schedule Mon/Tue/Thu/Sat, confirmable against logged treatment sessions) and band = PUSH → **cap to STEADY**, `capped_reason = 'dialysis'`.
6. **Safety guards override** — if respiratory-rate `z` or skin-temp `z` exceeds a guard threshold (e.g. `z ≥ +2`), **force REST**, `capped_reason = 'fluid-guard' | 'infection-guard'`. Guards win over everything.
7. **Cold-start** — a metric whose baseline `n < minBaselineDays` (default 30) is **excluded** and weights renormalized; if a core metric is missing, set `building_baseline = true`. (History exists, so defensive.)

## Architecture (Section B; approved)

**Files** (mirror the existing `fitness*` lib pattern):
- `api/src/lib/readiness.ts` — **pure**, no I/O:
  - `rollingBaseline(series, asOf, windowDays) → { mean, sd, n }`
  - `computeReadiness(todayValues, baselines, { dialysisDay }) → ReadinessResult`
- `api/src/lib/readiness.test.ts` — TDD unit tests.
- Route `POST /api/fitness/readiness` (bearer-authed) — loads today's values (`today/` + archival), builds baselines via `extractSeries`, derives `dialysisDay`, calls `computeReadiness`, writes `daily_energy/{date}` to Firestore. Reuses `extractSeries` / `parseSleepNight` / Firestore lib — minimal new I/O.

**Trigger:** **chained onto the freshen flow** — after a freshen writes today's data, compute readiness and upsert `daily_energy/{date}`, so readiness is always as fresh as the data and the existing 09/10/11 scheduler drives both. (Alternative considered: a separate `:05` scheduler job — rejected as more moving parts.)

**Output — `daily_energy/{date}` Firestore doc (self-explaining — stores the *why*):**
```json
{
  "date": "2026-06-22",
  "band": "STEADY",
  "score": 52,
  "components": {
    "hrv":   { "value": 34, "z": 0.4, "weight": 0.5 },
    "rhr":   { "value": 62, "z": -0.2, "weight": 0.3 },
    "sleep": { "value": 415, "z": 0.1, "weight": 0.2 }
  },
  "guards": {
    "respiration": { "z": 0.3, "triggered": false },
    "temp":        { "z": 0.5, "triggered": false }
  },
  "dialysis_day": true,
  "capped_reason": "dialysis",
  "building_baseline": false,
  "computed_at": "2026-06-22T10:05:00Z"
}
```
One doc serves the future exercise skill, the morning brief, and next-day review.

## Error handling

- Missing/short-baseline metric → excluded + `building_baseline`; never throws on partial data (mirrors `runSync` per-type isolation).
- Guard trigger → force REST.
- Firestore write only after a successful compute.
- Idempotent: recompute overwrites `daily_energy/{date}`.

## Testing (TDD, like freshen-today)

`readiness.test.ts`, synthetic inputs/baselines → assert:
- high HRV + low RHR + good sleep → **PUSH**
- low HRV → **REST**
- dialysis day caps PUSH → **STEADY** (`capped_reason: 'dialysis'`)
- skin-temp spike → **force REST** (`infection-guard`)
- respiration spike → **force REST** (`fluid-guard`)
- metric with `< minBaselineDays` → excluded, weights renormalized, `building_baseline` when core missing
- `rollingBaseline` recency-weighting math (mean/sd with linear decay)

## Out of scope (separate cycles)

- **Subjective morning check-in** (Borg-RPE 1–5 calibration) — needs Flutter UI.
- **LLM morning brief** (Gemini narration of the band).
- **Exercise-pacing skill** — the first *consumer* of `daily_energy` (the originally-requested skill; comes after this).
- **Analysis session** (data vs literature) and **multi-agent / A2A**.
- **Weights/threshold tuning** beyond sensible defaults — defaults ship; tuning is a follow-on once real `daily_energy` history accrues.

---

<!-- Implementation plan to be appended here by the writing-plans step. -->
