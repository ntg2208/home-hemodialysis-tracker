# Adding Monthly Blood Test Results

How to add a new monthly blood test to the live API so it appears in the dashboard without redeploying.

---

## Prerequisites

Load your API key once per shell session:

```bash
export KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
```

---

## What a monthly home-HD test looks like

Each monthly test produces two draws:

| Draw | timing | What it covers |
|------|--------|----------------|
| **Pre-dialysis** | `pre` | Full panel — ~34 markers |
| **Post-dialysis** | `post` | 6 dialysis-cleared markers only: `urea`, `creatinine`, `sodium`, `potassium`, `egfr`, `chloride` |

All other markers (haemoglobin, phosphate, PTH, etc.) only appear in the pre draw — do not invent post values for them.

---

## Row fields

| Field | Type | Notes |
|-------|------|-------|
| `marker` | string | Canonical name — see list below |
| `datetime` | string | ISO `YYYY-MM-DDTHH:MM:SS` — use the **corrected** date (later of pre/post pair), time from PKB |
| `value` | number | Numeric value — strip commas (`1,073` → `1073`) |
| `unit` | string | From PKB, e.g. `umol/L`, `mmol/L`, `g/L` |
| `ref_low` | number \| null | Lower bound from PKB, or `null` if absent |
| `ref_high` | number \| null | Upper bound from PKB, or `null` if absent |
| `timing` | `"pre"` \| `"post"` \| `""` | Set only for the 6 dialysis-cleared markers; empty string for everything else |
| `note` | string | Free text — use for date corrections, unusual flags, etc. |
| `source` | string | `"imperial-pkb"` or `"london-north-west-pkb"` |
| `lab_id` | string | From PKB "Lab Id" field — shared by all markers in one draw session; combined with `marker` as the deduplication key |
| `phase` | string | Always `"home-hd"` for current tests |
| `qualitative` | boolean | `true` only for non-numeric results (serology, culture comments) — rare |

`created_at` is set by the server automatically — do not include it.

---

## Step-by-step for a new month

### 1. Collect the data from PKB

For each marker, note: value, unit, reference range, Lab Id, date/time.

The 6 dialysis-cleared markers (`urea`, `creatinine`, `sodium`, `potassium`, `egfr`, `chloride`) appear twice — once in the pre draw and once in the post draw. Each has a different Lab Id.

**Date correction rule:** PKB sometimes stamps the post draw with the wrong date. Use the **pre draw's date** for both rows, and record the original PKB date in the `note` field (see example below).

### 2. Build the JSON payload

POST body is `{ "rows": [ ...rows ] }`. Up to 100 rows per request — split if needed.

**Example — May 2026 post-draw (6 markers):**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rows": [
      {
        "marker": "creatinine",
        "datetime": "2026-06-15T12:00:00",
        "value": 361,
        "unit": "umol/L",
        "ref_low": 64,
        "ref_high": 104,
        "timing": "post",
        "note": "post-dialysis draw; PKB-dated 2026-06-10, corrected to 2026-06-15 to match pre-draw 99261XXXXXX",
        "source": "imperial-pkb",
        "lab_id": "99261XXXXXX",
        "phase": "home-hd",
        "qualitative": false
      },
      {
        "marker": "urea",
        "datetime": "2026-06-15T12:00:00",
        "value": 6.3,
        "unit": "mmol/L",
        "ref_low": 2.5,
        "ref_high": 7.8,
        "timing": "post",
        "note": "post-dialysis draw; PKB-dated 2026-06-10, corrected to 2026-06-15",
        "source": "imperial-pkb",
        "lab_id": "99261XXXXXX",
        "phase": "home-hd",
        "qualitative": false
      }
    ]
  }' \
  'https://homehd.web.app/api/blood-tests'
```

Expected response: `{"ok":true,"count":2}`

### 3. Verify the rows appear

```bash
# Check a specific marker for the month
curl -s -H "Authorization: Bearer $KEY" \
  'https://homehd.web.app/api/blood-tests?marker=creatinine&phase=home-hd&from=2026-06&to=2026-06'
```

Both pre and post creatinine rows should appear. Check `lab_id` matches what you entered.

---

## Canonical marker names

Use these exactly — unknown names return 0 rows, not an error.

**Dialysis-cleared (pre + post, set `timing`):**
`urea`, `creatinine`, `egfr`, `sodium`, `potassium`, `chloride`

**Renal / mineral (pre only, `timing: ""`):**
`bicarbonate`, `phosphate`, `adjusted_calcium`, `magnesium`, `pth`, `vitamin_d`

**Haematology (pre only, `timing: ""`):**
`haemoglobin`, `haematocrit`, `rbc`, `wbc`, `platelets`, `mcv`, `mch`, `mchc`, `ferritin`, `rdw`

**Liver (pre only, `timing: ""`):**
`albumin`, `alt`, `ast`, `ggt`, `alkaline_phosphatase`, `bilirubin`

---

## Common mistakes

| Mistake | Effect | Fix |
|---------|--------|-----|
| Setting `timing: "pre"` or `"post"` on non-dialysis markers | Dashboard may mislead on deltas | Use `timing: ""` for everything except the 6 dialysis-cleared markers |
| Reusing a `lab_id` from a previous month | Overwrites the old row silently | Always use the Lab Id from PKB — it's unique per draw |
| Including `created_at` in the payload | Field is ignored (schema strips it) | Omit it — server sets it |
| Wrong date on post draw | Pre/post pair appears on different dates | Use the pre draw's date for both; note original in `note` field |
| Comma in numeric value (`1,073`) | JSON parse error or schema rejection | Strip commas before entering |

---

## Reposting / correcting a row

POST is upsert — if you POST a row with the same `lab_id`, it overwrites the existing Firestore row. The static backfill (CSV) is never modified this way; only Firestore rows can be overwritten via POST.

If you need to correct a row in the static backfill, edit `scripts/pkb_backfill/blood_tests.csv` and redeploy.
