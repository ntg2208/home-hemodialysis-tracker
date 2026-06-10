# Chat: Retrieval Tools + Voice Input

**Date:** 2026-06-10
**Status:** Design approved, awaiting implementation plan

## Summary

Two additions to the chat assistant:

1. **Data retrieval tools** — three new Gemini function-call tools that let the AI fetch historical session and blood-test data on demand, enabling analytical answers ("why am I itching?", "compare last month's bloods to this month", "what was my average BP last week?").
2. **Voice input (STT)** — mic button in the chat input field; speech converts to text and goes through the existing pipeline unchanged.

The existing eager context (last session summary, 8 key blood markers, fitness snapshot, critical inventory) stays exactly as-is. Simple questions answer from context with no tool call. The new tools activate only when the user asks something that requires historical or cross-session reasoning.

---

## 1. System Prompt Changes

### 1a. Clinical Hints Section (new)

Appended to `ChatContextBuilder.build()` between `CURRENT STATE` and `INSTRUCTIONS`:

```
--- CLINICAL HINTS ---
Use get_blood_markers when asked about symptoms or when deeper history is needed:
- Itching / skin irritation     → phosphate, adjusted_calcium
- Fatigue / breathlessness      → haemoglobin, ferritin, bicarbonate
- Muscle cramps / palpitations  → potassium, adjusted_calcium
- Swelling / fluid retention    → albumin, sodium
- Bone pain                     → phosphate, adjusted_calcium, pth
- Poor clearance / uraemia      → urea, creatinine, egfr

Use get_sessions for questions about BP trends, UF patterns, or multi-session comparisons.
Use get_out_of_range_markers for "is anything flagged?" or general health-check questions.
When comparing months, fetch 2–3 months of data.
```

### 1b. No other system prompt changes

`ChatContextBuilder` fields, the `CURRENT STATE` section, and `AppScreenContext.toPromptSection()` are unchanged.

---

## 2. New Retrieval Tools

### 2a. `get_blood_markers`

```
Parameters:
  markers       string[]   Required. Canonical marker names, e.g. ["phosphate", "potassium"]
  months_back   int?       Optional. How far back to look. Default 2, max 12.
```

**Returns** (as FunctionResponse JSON):
```json
{
  "results": [
    {
      "marker": "phosphate",
      "rows": [
        {
          "date": "2026-05-18",
          "value": 1.9,
          "unit": "mmol/L",
          "ref_low": 0.8,
          "ref_high": 1.5,
          "in_range": false,
          "timing": "pre"
        }
      ]
    }
  ]
}
```
Top-level `results` array — one object per requested marker, in request order. Rows sorted newest-first. If a marker is not found in cache, its `rows` array is empty.

### 2b. `get_sessions`

```
Parameters:
  last_n            int?     Optional. Last N sessions. Default 7, max 30.
  from              string?  Optional. YYYY-MM-DD start date (inclusive).
  to                string?  Optional. YYYY-MM-DD end date (inclusive).
  include_readings  bool?    Optional. Include intra-session readings. Default false.
                             Only use for small last_n (≤ 5) — adds significant tokens.
```

`last_n` and `from/to` are mutually exclusive; if both provided, `from/to` wins.

**Returns** (as FunctionResponse JSON):
```json
{
  "sessions": [
    {
      "date": "2026-06-09",
      "session_id": "2026-06-09",
      "pre_weight": 61.0,
      "post_weight": 59.4,
      "weight_removed": 1.6,
      "pre_bp": "117/89",
      "post_bp": "112/78",
      "pre_pulse": 89,
      "post_pulse": 82,
      "uf_goal": 2.0,
      "total_uf": 1.6,
      "uf_achievement_pct": 80,
      "duration_min": 255,
      "comment": "",
      "readings": []
    }
  ],
  "count": 1
}
```

### 2c. `get_out_of_range_markers`

```
Parameters: (none)
```

**Returns** (as FunctionResponse JSON):
```json
{
  "draw_date": "2026-05-18",
  "out_of_range": [
    {
      "marker": "phosphate",
      "value": 1.9,
      "unit": "mmol/L",
      "ref_low": 0.8,
      "ref_high": 1.5,
      "direction": "high"
    }
  ],
  "total_markers_checked": 34
}
```

Covers only the most recent draw date. `direction` is `"high"` or `"low"`.

---

## 3. Implementation: Retrieval Tools Architecture

### 3a. Data source

All retrieval tools operate on data already fetched at the top of `GeminiChatResponder.reply()`:

```dart
final treatmentData = await treatmentRepo.getAll(); // sessions + readings
final btCache = btStore.readCache();                 // all blood test rows
```

No additional network calls during the conversation loop.

### 3b. New class: `RetrieverTools`

A pure Dart class (no async I/O, unit-testable) that takes the pre-fetched data and executes retrieval queries:

```dart
class RetrieverTools {
  const RetrieverTools({
    required this.sessions,
    required this.readings,
    required this.bloodTestRows,
  });

  final List<Session> sessions;
  final List<Reading> readings;
  final List<BloodTestRow> bloodTestRows;

  Map<String, dynamic> getBloodMarkers(List<String> markers, int monthsBack);
  Map<String, dynamic> getSessions({int? lastN, String? from, String? to, bool includeReadings = false});
  Map<String, dynamic> getOutOfRangeMarkers();
}
```

### 3c. Tool registration

Retrieval tools are added to `GeminiChatResponder._tools` alongside the existing action tools. They are always valid (not gated by `TreatmentState`) and are not added to `AppScreenContext.validCommands` (that list is for action tools only).

### 3d. Tool-call loop handling

In the existing tool-call loop in `reply()`, retrieval tool calls are handled by calling `RetrieverTools` methods and returning the result as a `FunctionResponse`. No `AppCommand` is enqueued (retrieval tools have no UI side-effect).

```dart
final retriever = RetrieverTools(
  sessions: [...treatmentData.sessions],
  readings: treatmentData.readings,
  bloodTestRows: btCache.rows,
);

// In the loop:
'get_blood_markers' => {
  final markers = (call.args['markers'] as List).cast<String>();
  final months = (call.args['months_back'] as num?)?.toInt() ?? 2;
  result = retriever.getBloodMarkers(markers, months);
},
'get_sessions' => {
  result = retriever.getSessions(
    lastN: (call.args['last_n'] as num?)?.toInt(),
    from: call.args['from'] as String?,
    to: call.args['to'] as String?,
    includeReadings: call.args['include_readings'] as bool? ?? false,
  );
},
'get_out_of_range_markers' => {
  result = retriever.getOutOfRangeMarkers();
},
```

### 3e. Token budget

| Query | Approx tokens |
|---|---|
| `get_blood_markers(["phosphate"], 2)` | ~400 |
| `get_sessions(last_n: 7)` | ~700 |
| `get_out_of_range_markers()` (34 markers, 5 flagged) | ~300 |

All well within `gemini-3.1-flash-lite`'s context window.

---

## 4. Voice Input (STT)

### 4a. Package

`speech_to_text` (pub.dev). Covers Android (native recognizer), iOS (Siri), Chrome/web (Web Speech API). Mic button hidden on unsupported platforms (non-Chrome web, permission permanently denied).

### 4b. UI

Mic icon button added to the right of the chat input field, left of the send button. States:

| State | Icon | Hint text |
|---|---|---|
| Idle | `Icons.mic_none` | — |
| Listening | `Icons.mic` (pulsing red) | "Listening…" replaces placeholder |
| Unavailable | hidden | — |

### 4c. Interaction flow

1. Tap mic → request permission (one-time OS dialog)
2. On grant: start listening, enter listening state
3. Speech recognised: transcript streams into the text field
4. On silence detection (2s pause) or second tap: stop listening, auto-send if field is non-empty
5. User can edit the transcript before auto-send fires (cancels the timer)

### 4d. What doesn't change

Everything downstream of the text field is unchanged — Gemini sees the same prompt, retrieval tools and action tools work identically whether input came from keyboard or voice.

### 4e. TTS (deferred)

Not in scope. The AI responds with text in the chat bubble. Phase B (speak responses aloud) is a clean addition wrapping the existing `Stream<String>` reply — deferred until needed.

---

## 5. What Doesn't Change

- `ChatContextBuilder` fields and eager-loaded context (last session, 8 key markers, fitness, inventory)
- All existing action tools (`navigate_to`, `filter_blood_tests`, `filter_fitness`, `prefill_*`, `end_session`)
- `CommandDispatch`, `CommandValidator`, `AppScreenContext`
- `AppScreenContext.validCommands` (retrieval tools are not state-gated)
- `GenerationConfig` (temperature 0.4, maxOutputTokens 2048)
- Firestore conversation history

---

## 6. Files Affected

| File | Change |
|---|---|
| `lib/features/chat/chat_context.dart` | Add clinical hints section to `build()` |
| `lib/features/chat/gemini_client.dart` | Add 3 tool declarations to `_tools`; wire retrieval calls in tool loop; construct `RetrieverTools` |
| `lib/features/chat/retriever_tools.dart` | **New file** — `RetrieverTools` pure class |
| `lib/features/chat/chat_sheet.dart` | Add mic button to input row |
| `pubspec.yaml` | Add `speech_to_text` dependency |
| `test/retriever_tools_test.dart` | **New file** — unit tests for `RetrieverTools` |
| `test/features/chat/gemini_responder_test.dart` | Add tests for retrieval tool call/response round-trip |

---

## 7. Out of Scope

- TTS / spoken AI responses
- Multi-turn voice conversations
- Streaming STT (transcription updates mid-speech shown incrementally — nice to have, deferred)
- On-device LLM (Phase C from roadmap)
- MCP server / Skills layer (roadmap item)
