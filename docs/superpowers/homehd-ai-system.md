# HomeHD AI Assistant — System Specification

> Edit this document to change the assistant's behaviour, then re-implement the
> relevant section in the app. Sections are ordered from most-likely to
> least-likely to need changing.

---

## 1. Model & Call Parameters

| Parameter | Value |
|---|---|
| Model | `gemini-3.1-flash-lite` |
| Temperature | `0.4` |
| Max output tokens | `2048` |
| API | Google AI Studio (`google_generative_ai` Dart SDK) |
| Function calling | Enabled — see §3 and §4 |

**Call flow (3 turns per tool-using response):**
1. User message → model responds with `FunctionCall`
2. Client executes tool, sends `FunctionResponse` with rich result → model responds with text narration
3. (Retrieval chains) model may call additional tools before narrating — up to 5 chained tool turns

For pure-chat responses (no tool call), only turn 1 fires and text is streamed token-by-token.

---

## 2. System Prompt

Built fresh on every `reply()` call from live app data. Template:

```
You are a personal health assistant for a home hemodialysis patient.

--- PATIENT KNOWLEDGE (user-curated) ---
{KB_SECTION}

--- CURRENT STATE (auto-assembled) ---
{SESSION_LINE}
{BLOODS_LINE}
{FITNESS_LINE}
{INVENTORY_LINE}

--- CLINICAL HINTS ---
Use get_blood_markers when asked about symptoms or when deeper history is needed:
- Itching / skin irritation     → phosphate, adjusted_calcium
- Fatigue / breathlessness      → haemoglobin, ferritin, bicarbonate
- Muscle cramps / palpitations  → potassium, adjusted_calcium
- Swelling / fluid retention    → albumin, sodium
- Bone pain                     → phosphate, adjusted_calcium, intact_pth
- Poor clearance / uraemia      → urea, creatinine, egfr

Use get_sessions for questions about BP trends, UF patterns, or multi-session comparisons.
Use get_out_of_range_markers for "is anything flagged?" or general health-check questions.
When comparing months, fetch 2–3 months of data.

--- INSTRUCTIONS ---
- Answer concisely. Use markdown for tables and lists.
- When the user tells you something worth remembering (a new dry weight, a medication
  change, a symptom note), end your response with a KB update in this EXACT format
  on its own line: <!--KB_UPDATE {"title":"Entry Title","content":"Entry content"}-->
- For blood test values, include reference ranges when you know them.
- HRV values are relative to the patient's personal baseline — do not apply absolute
  population cutoffs.
- If asked about something not in the current state, say so — don't guess.
- Do not give medical advice. Summarise trends and flag patterns, but always defer
  to the clinical team.

--- CURRENT APP STATE ---
Screen: {CURRENT_ROUTE}
Treatment state: {TREATMENT_STATE}   // IDLE | PREFORM | ACTIVE | POSTFORM
Valid commands: {VALID_COMMANDS}
{ACTIVE_SESSION_BLOCK}
{OPEN_FORM_BLOCK}

RULES:
- Only call tools listed in "Valid commands". If the user requests an invalid command,
  explain why and what they should do instead.
- For prefill commands: fill only the provided fields. Leave unspecified fields at
  their current values. Do not guess.
- After dispatching a command, describe what you did in plain language.
- If required fields are missing for a command, ask for them before calling the tool.
```

### 2.1 Placeholder Values

**`{KB_SECTION}`** — user-curated notes, one per line as `Title: content (truncated to 100 chars)`. Example:
```
Dry Weight: 59 kg — target post-dialysis weight.
Session Duration: 4 hours 15 minutes standard session.
```

**`{SESSION_LINE}`** — most recent session, single line. Example:
```
Last dialysis: 2026-06-10, pre 130/85 HR72, post 118/78 HR68, UF 2.5L, 255min.
```

**`{BLOODS_LINE}`** — 8 key markers from the most recent blood draw date. Example:
```
Latest bloods (2026-05-28): creatinine 890 umol/L (ref 45–84 umol/L),
potassium 5.1 mmol/L (ref 3.5–5.3 mmol/L), haemoglobin 110 g/L (ref 115–165 g/L), ...
```
Key markers shown in snapshot: `creatinine`, `potassium`, `haemoglobin`, `urea`,
`phosphate`, `albumin`, `adjusted_calcium`, `bicarbonate`.

**`{FITNESS_LINE}`** — latest wearable readings. Example:
```
Resting HR: 58 bpm. HRV (RMSSD): 42ms. Sleep: 7h 12m. Deep sleep: 84min.
```

**`{INVENTORY_LINE}`** — critical supply stock. Example:
```
Inventory: SAK-303: 3 boxes, CAR-172-C: 2 boxes, PAK-001: 1 boxes, UK00000880: 4 boxes.
Next delivery: 2026-06-18.
```
Critical SKUs tracked: `SAK-303`, `CAR-172-C`, `PAK-001`, `UK00000880`.

**`{TREATMENT_STATE}`** — one of `IDLE`, `PREFORM`, `ACTIVE`, `POSTFORM`.

**`{VALID_COMMANDS}`** — varies by treatment state:
- `IDLE`: `navigate_to, filter_blood_tests, filter_fitness, prefill_pre_treatment`
- `ACTIVE`: `navigate_to, filter_blood_tests, filter_fitness, prefill_reading, end_session`
- `POSTFORM`: `navigate_to, filter_blood_tests, filter_fitness, prefill_post_treatment`

---

## 3. Retrieval Tools

These tools return data to the model. No app action is taken. The model uses the
results to answer the user's question, then optionally chains to an action tool.

---

### `get_blood_markers`

Fetch historical blood test rows for specific markers.

**When to use:** Asked about symptoms, trends, or comparisons across months.

**Parameters:**
| Name | Type | Required | Description |
|---|---|---|---|
| `markers` | `string[]` | ✅ | Canonical marker names, e.g. `["phosphate", "potassium"]` |
| `months_back` | `integer` | | How many months back to look. Default 2, max 12. |

**Returns:**
```json
{
  "results": [
    {
      "marker": "haemoglobin",
      "rows": [
        {
          "date": "2026-05-28",
          "value": 110.0,
          "unit": "g/L",
          "ref_low": 115.0,
          "ref_high": 165.0,
          "in_range": false,
          "timing": "pre"
        }
      ]
    }
  ]
}
```

`timing` is `"pre"`, `"post"`, or `""`. Rows are sorted newest-first within each marker.

---

### `get_sessions`

Fetch dialysis session records.

**When to use:** BP trends, UF patterns, weight trends, multi-session comparisons.

**Parameters:**
| Name | Type | Required | Description |
|---|---|---|---|
| `last_n` | `integer` | | Last N sessions. Default 7, max 30. Mutually exclusive with `from`/`to`. |
| `from` | `string` | | Start date `YYYY-MM-DD` inclusive. Use with `to`. |
| `to` | `string` | | End date `YYYY-MM-DD` inclusive. Use with `from`. |
| `include_readings` | `boolean` | | Include intra-session BP readings. Default false. Only use for `last_n ≤ 5`. |

**Returns:**
```json
{
  "count": 7,
  "sessions": [
    {
      "date": "2026-06-10",
      "session_id": "ses_abc123",
      "pre_weight": 61.5,
      "post_weight": 59.0,
      "weight_removed": 2.5,
      "pre_bp": "130/85",
      "post_bp": "118/78",
      "pre_pulse": 72,
      "post_pulse": 68,
      "uf_goal": 2.5,
      "total_uf": 2.5,
      "uf_achievement_pct": 100,
      "duration_min": 255,
      "comment": "",
      "readings": []
    }
  ]
}
```

If `include_readings: true`, each session's `readings` array contains:
```json
{ "time": "14:32", "bp": "125/80", "pulse": 70, "blood_flow": 350 }
```

---

### `get_out_of_range_markers`

Returns all markers from the most recent blood draw that are outside reference range.

**When to use:** "Is anything flagged?", "How are my bloods?", general health checks.

**Parameters:** None.

**Returns:**
```json
{
  "draw_date": "2026-05-28",
  "total_markers_checked": 22,
  "out_of_range": [
    {
      "marker": "haemoglobin",
      "value": 110.0,
      "unit": "g/L",
      "ref_low": 115.0,
      "ref_high": 165.0,
      "direction": "low"
    }
  ]
}
```

Deduplication rule: if both `pre` and `post` exist for the same marker on the same
date, `pre` wins. Priority order: `pre > post > ""`.

---

## 4. Action Tools

These tools control the app. Each validated command is enqueued, the model narrates,
then the app acts after a reading-time delay (2–5 s proportional to narration length).

On success the function response sent back to the model is a rich result map (see §4.8).
On validation failure the function response is `{"error": "..."}` and the model
explains the issue to the user.

---

### `navigate_to`

Navigate to a main screen.

**Valid at:** any treatment state.

**Parameters:**
| Name | Type | Required | Values |
|---|---|---|---|
| `route` | `string` | ✅ | `/treatment`, `/blood-tests`, `/inventory`, `/fitness`, `/kb` |

**Function response on success:**
```json
{ "success": true, "navigated_to": "Blood Tests", "route": "/blood-tests" }
```

---

### `filter_blood_tests`

Navigate to blood tests and apply a filter.

**Valid at:** any treatment state.

**Parameters (all optional):**
| Name | Type | Description |
|---|---|---|
| `marker` | `string` | Canonical marker name, e.g. `haemoglobin` |
| `phase` | `string` | `home-hd`, `in-center-hd`, or `admission` |
| `months` | `integer` | Months back from today |
| `tab` | `string` | `scorecard` or `trend` |

**Function response on success:**
```json
{ "success": true, "screen": "Blood Tests", "marker": "haemoglobin", "months_back": 3 }
```
(only non-null filter fields are included)

---

### `filter_fitness`

Navigate to fitness and filter by type and/or time window.

**Valid at:** any treatment state.

**Parameters (all optional):**
| Name | Type | Description |
|---|---|---|
| `type` | `string` | `steps`, `sleep`, `heart-rate`, or `hrv` |
| `days` | `integer` | Days back from today |

**Function response on success:**
```json
{ "success": true, "screen": "Fitness", "type": "hrv", "days_back": 30 }
```

---

### `prefill_pre_treatment`

Pre-fill the pre-treatment form and open it.

**Valid at:** `IDLE` only. Blocked if session is already active or a form is open.

**Parameters (all optional):**
| Name | Type | Sanity range |
|---|---|---|
| `weight` | `number` | 30–200 kg |
| `bp_sys` | `integer` | 50–260 mmHg |
| `bp_dia` | `integer` | 30–160 mmHg |
| `pulse` | `integer` | 30–200 bpm |
| `uf_goal` | `number` | 0–6 L |
| `uf_rate` | `number` | 0–2000 mL/h |

**Function response on success:**
```json
{ "success": true, "form": "pre-treatment", "form_opened": true }
```

---

### `prefill_reading`

Pre-fill the Add Reading form during an active session.

**Valid at:** `ACTIVE` only.

**Parameters (all optional):**
| Name | Type | Sanity range |
|---|---|---|
| `bp_sys` | `integer` | 50–260 mmHg |
| `bp_dia` | `integer` | 30–160 mmHg |
| `pulse` | `integer` | 30–200 bpm |
| `blood_flow` | `integer` | 50–600 mL/min |
| `vp` | `integer` | venous pressure |
| `ap` | `integer` | arterial pressure |

**Function response on success:**
```json
{ "success": true, "form": "add-reading", "form_opened": true }
```

---

### `prefill_post_treatment`

Pre-fill the post-treatment form.

**Valid at:** `POSTFORM` only (session has been ended, form is open).

**Parameters (all optional):**
| Name | Type | Sanity range |
|---|---|---|
| `weight` | `number` | 30–200 kg |
| `bp_sys` | `integer` | 50–260 mmHg |
| `bp_dia` | `integer` | 30–160 mmHg |
| `pulse` | `integer` | 30–200 bpm |
| `total_uf` | `number` | 0–6 L |

**Function response on success:**
```json
{ "success": true, "form": "post-treatment", "form_opened": true }
```

---

### `end_session`

End the active dialysis session and open the post-treatment form.
Can optionally pre-fill post-treatment fields in the same call.

**Valid at:** `ACTIVE` only.

**Parameters (all optional — same as `prefill_post_treatment`):**
| Name | Type | Sanity range |
|---|---|---|
| `weight` | `number` | 30–200 kg |
| `bp_sys` | `integer` | 50–260 mmHg |
| `bp_dia` | `integer` | 30–160 mmHg |
| `pulse` | `integer` | 30–200 bpm |
| `total_uf` | `number` | 0–6 L |

**Function response on success:**
```json
{ "success": true, "session_ended": true, "post_treatment_form_opened": true }
```

---

## 5. Knowledge Base (KB) Update Protocol

The model can propose KB entries by appending a structured comment to its response:

```
<!--KB_UPDATE {"title":"Dry Weight","content":"Updated to 59.5 kg after clinic review."}-->
```

The app parses this comment out of the response text, strips it before displaying,
and shows an "Accept" chip below the message. On accept, the entry is upserted into
the KB store (matched by `title`).

**Trigger conditions (model decides):**
- User states a new dry weight, medication change, or clinical note
- User corrects previously stored information
- User mentions a new symptom pattern or care instruction

---

## 6. Treatment State Machine

```
IDLE ──(start session)──► PREFORM ──(session created)──► ACTIVE ──(end_session)──► POSTFORM ──(form submitted)──► IDLE
```

Valid action tools per state:

| State | Valid prefill/action tools |
|---|---|
| `IDLE` | `prefill_pre_treatment` |
| `PREFORM` | _(none — form already open)_ |
| `ACTIVE` | `prefill_reading`, `end_session` |
| `POSTFORM` | `prefill_post_treatment` |

`navigate_to`, `filter_blood_tests`, `filter_fitness` are always valid.

---

## 7. Validation Rules

### State validation errors (returned as function response `{"error": "..."}`)

| Command | Blocked when | Error message |
|---|---|---|
| `prefill_pre_treatment` | state = `ACTIVE` | "A session is already in progress. Add a reading or end the session first." |
| `prefill_pre_treatment` | state = `PREFORM` or `POSTFORM` | "Cannot start a new session while the current form is open." |
| `prefill_reading` | state = `IDLE` | "There is no active session. Start a session first, then add readings." |
| `prefill_reading` | state ≠ `ACTIVE` | "Cannot add a reading -- the session is not yet active." |
| `prefill_post_treatment` | state = `IDLE` | "There is no session to finish. Start one first." |
| `prefill_post_treatment` | state ≠ `POSTFORM` | "Cannot fill post-treatment details until the active session is ended." |
| `end_session` | state = `IDLE` | "There is no active session to end." |
| `end_session` | state ≠ `ACTIVE` | "The session cannot be ended from this state." |

### Value validation (clinical sanity ranges)

| Field | Min | Max |
|---|---|---|
| `weight` | 30 kg | 200 kg |
| `bp_sys` | 50 mmHg | 260 mmHg |
| `bp_dia` | 30 mmHg | 160 mmHg |
| `pulse` | 30 bpm | 200 bpm |
| `uf_goal` | 0 L | 6 L |
| `uf_rate` | 0 mL/h | 2000 mL/h |
| `blood_flow` | 50 mL/min | 600 mL/min |
| `total_uf` | 0 L | 6 L |

Out-of-range values return: `"field=value looks out of range (expected min–max). Please confirm the value."`

---

## 8. Narration Timing

After yielding the model's narration text, the app delays before closing the sheet
and executing commands. Delay formula:

```
delay = clamp(words × 250 ms, min=2000 ms, max=5000 ms)
```

This gives the user time to read before the app navigates. If the model returns empty
text, the fallback narration is `"Done."` and the minimum 2 s delay applies.

---

## 9. Notes for Future Agent Migration

If migrating to a proper agent framework (LangGraph, Vertex AI Agent Builder, etc.):

- **Retrieval tools** (`get_blood_markers`, `get_sessions`, `get_out_of_range_markers`)
  map cleanly to agent "knowledge tools" — pure read, no side effects.
- **Action tools** map to agent "action tools" — they mutate app state and require
  state-machine gating. The validation logic in §6–7 must be preserved regardless
  of framework.
- **The system prompt context** (§2) is regenerated per turn from live data. In an
  agent framework this would be the "memory/context injection" step.
- **KB updates** (§5) are the only persistent write path from the model — they
  need an equivalent "memory write" tool in an agent framework.
- **The 3-turn call flow** (user → tool call → function response → narration) is
  standard function-calling and maps directly to any agent framework's tool loop.
- The `TreatmentState` enum and `validCommands` gate are critical safety constraints —
  the model must not be able to call `end_session` when idle, regardless of framework.
