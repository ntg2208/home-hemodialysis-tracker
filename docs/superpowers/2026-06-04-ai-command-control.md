# AI Command Control

#type/build #status/planned #effort/multi-week #domain/llm #domain/health

Extends [[2026-06-03-chat-llm]] to give the in-app Gemini assistant the ability to **drive the app** — navigate screens, apply filters, and pre-fill forms — via Gemini function calling + a typed command bus.

## Design Decisions

- **Control model:** In-app Gemini chat (Dart SDK function calling) controls the app. Everything is in-process on the device — no Cloud Run, no cold start.
- **Execution model:** Read-only and navigation commands execute automatically. Write commands (forms) pre-fill and wait for user to tap Submit.
- **Architecture:** Command Bus — Gemini tool use → `AppCommand` sealed class → Riverpod stream bus → each screen reacts independently.
- **Context model:** Current screen, treatment state machine, and open form state are sent to Gemini on every message via an extended system prompt section.
- **MCP server:** Explicitly deferred to Phase 2. When built, it will be embedded in the Flutter app (no Cloud Run) using `flutter_mcp` or `dart_mcp`, sharing the same `AppCommand` tool handlers as in-app function calling. External clients (Gemini CLI, Claude Code) connect via the same WiFi network. See [[#future-phase-2-embedded-mcp-server]] below.

---

## Architecture

```
User message
    │
    ▼
GeminiChatResponder.reply()
    │  ← tools: [FunctionDeclaration(...)]
    │  ← system prompt includes: current screen + treatment state + form state
    ▼
Gemini API
    │  → FunctionCall: filter_blood_tests(marker: "haemoglobin", months: 3)
    ▼
GeminiChatResponder — dispatches AppCommand via onCommand callback
    │
    ▼
CommandBus (Riverpod StreamController<AppCommand>)
    │         │           │
    ▼         ▼           ▼
  Router   BloodTests   Treatment
  .go()    filter       prefill form
           provider     provider
    │
    ▼
Gemini gets FunctionResponse → generates reply text
    ▼
Chat bubble: "Here's your Hb trend for the last 3 months. Latest: 112 g/L (↑ from 108)."
```

---

## Treatment State Machine

The AI is given the current treatment state in every system prompt. It will only call tools valid for that state; if an invalid command is requested, it explains why and offers the correct path.

```
IDLE ──[start session]──▶ PRE_FORM ──[tap Start]──▶ ACTIVE ──[tap End]──▶ POST_FORM ──[tap Finish]──▶ IDLE
```

| State | Valid AI commands |
|---|---|
| `idle` | `navigate_to`, `prefill_pre_treatment`, `filter_blood_tests`, `filter_fitness` |
| `pre_form` | `prefill_pre_treatment` (update fields), `navigate_to` (cancel flow) |
| `active` | `prefill_reading`, `navigate_to` (navigates away — session persists) |
| `post_form` | `prefill_post_treatment` (update fields) |

---

## AppScreenContext

New class that captures the current runtime state of the app. Built by `screenContextProvider` (Riverpod provider) and passed into `ChatContextBuilder` before each Gemini call.

```dart
enum TreatmentState { idle, preForm, active, postForm }

class AppScreenContext {
  final String currentRoute;              // e.g. '/blood-tests'
  final TreatmentState treatmentState;    // current stage of the treatment flow
  final List<String> validCommands;       // tool names valid right now
  final Session? activeSession;           // non-null when treatmentState == active | postForm
  final List<Reading> sessionReadings;    // readings recorded so far this session
  final Map<String, dynamic>? openForm;   // field name → current value for the open form
                                          // null if no form is open
}
```

### openForm example (Add Reading modal open)

```dart
{
  'screen': 'add_reading',
  'time': '20:45',       // filled
  'bp_sys': null,        // empty — required
  'bp_dia': null,        // empty — required
  'pulse': null,         // empty — optional
  'blood_flow': 350,     // defaulted from last reading
  'vp': null,
  'ap': null,
}
```

### screenContextProvider

`StateNotifierProvider<ScreenContextNotifier, AppScreenContext>`. Each screen calls `ref.read(screenContextProvider.notifier).update(...)` when:
- The screen becomes active (navigation)
- The user opens a form modal
- A form field changes value

---

## Command Vocabulary

Seven tools declared in `GenerativeModel`. Tool names are snake_case. All parameters optional unless marked required.

Two categories:
- **UI control tools** (6) — execute in-process, call Riverpod/GoRouter directly, no network hop.
- **Data tools** (1) — call Cloud Run API. Possible 2s cold start on first call of the day; acceptable for one-off data entry tasks. Handled directly in `GeminiChatResponder`, not via the AppCommand bus.

### `navigate_to`
Navigate to any main route.

| Param | Type | Required | Notes |
|---|---|---|---|
| `route` | string | ✓ | One of: `/treatment`, `/blood-tests`, `/inventory`, `/fitness`, `/kb` |

Execution: **auto** — fires immediately, no user confirmation.

---

### `filter_blood_tests`
Navigate to blood tests and apply a filter.

| Param | Type | Notes |
|---|---|---|
| `marker` | string | Canonical marker name, e.g. `haemoglobin`, `ferritin`, `potassium` |
| `phase` | string | `home-hd`, `in-center-hd`, `admission` |
| `months` | int | Number of months back from today |
| `tab` | string | `scorecard` or `trend` |

Execution: **auto** — navigates and applies filter immediately.

---

### `filter_fitness`
Navigate to fitness and apply a filter.

| Param | Type | Notes |
|---|---|---|
| `type` | string | e.g. `steps`, `sleep`, `heart-rate`, `hrv` |
| `days` | int | Number of days back from today |

Execution: **auto**.

---

### `prefill_pre_treatment`
Pre-fill the pre-treatment form. Navigates to `/treatment` first if not already there.

| Param | Type | Notes |
|---|---|---|
| `weight` | double | Pre-treatment weight in kg |
| `bp_sys` | int | Systolic BP |
| `bp_dia` | int | Diastolic BP |
| `pulse` | int | Pulse rate |
| `uf_goal` | double | UF goal in litres |
| `uf_rate` | double | UF rate in mL/h |

Execution: **fill + preview** — form opens with fields filled, user taps Start. AI-filled fields are highlighted. Required fields not provided by the user are left empty.

Invalid when: `treatmentState != idle`. If called in wrong state, Gemini explains and does not dispatch the command.

---

### `prefill_reading`
Pre-fill the Add Reading modal on the Active Session screen.

| Param | Type | Notes |
|---|---|---|
| `bp_sys` | int | Systolic BP |
| `bp_dia` | int | Diastolic BP |
| `pulse` | int | Pulse rate |
| `blood_flow` | int | Blood flow in mL/min |
| `vp` | int | Venous pressure |
| `ap` | int | Arterial pressure |

Execution: **fill + preview** — modal opens with provided fields filled, `blood_flow` defaults to last reading if not given, user taps Save.

Invalid when: `treatmentState != active`.

---

### `prefill_post_treatment`
Pre-fill the post-treatment form.

| Param | Type | Notes |
|---|---|---|
| `weight` | double | Post-treatment weight in kg |
| `bp_sys` | int | Systolic BP |
| `bp_dia` | int | Diastolic BP |
| `pulse` | int | Pulse rate |
| `total_uf` | double | Total UF in litres |

Execution: **fill + preview** — fields filled, user taps Finish.

Invalid when: `treatmentState != postForm`.

---

### `insert_portal_paste`
Parse a raw PKB portal paste and insert all blood test rows into Firestore.

| Param | Type | Required | Notes |
|---|---|---|---|
| `paste` | string | ✓ | Full text copied from the PKB portal summary page |
| `year` | int | | Year of the results. Defaults to current year if omitted |

Execution: **Cloud Run call** — `GeminiChatResponder` calls `POST /api/blood-tests/parse-paste`, receives `{ ok, count }`, and returns the result to Gemini as the FunctionResponse. Gemini reports back to the user ("Parsed and inserted 25 rows. Your latest Hb is 112 g/L."). After a successful insert, Gemini optionally dispatches `filter_blood_tests` to show the newly added data.

Does **not** go through the AppCommand bus — no Flutter widget state change needed.

Cold start note: first call of the day may take ~2s. Acceptable for a monthly one-off task.

**Backend: `POST /api/blood-tests/parse-paste`**

New endpoint on the existing `bloodTests` Hono handler. Ports `_parse_portal_paste` from `scripts/pkb_backfill/parse_pkb.py` to TypeScript.

Request body:
```ts
{ paste: string; year?: number }
```

Logic:
1. Parse the paste text using a ported version of the Python block parser (`MARKER_MAP`, `SKIP_LINES`, `DATE_RE`).
2. For each parsed row, look up the most recent `ref_low` / `ref_high` for that marker from the existing static data + Firestore (same merge logic as GET).
3. Batch-insert all rows via Firestore `batch.set()` (same as existing `POST /`).
4. Return `{ ok: true, count: N }`.

Returns `400` if no rows could be parsed (format unrecognised).

---

## System Prompt Extension

`ChatContextBuilder` gains a new `currentAppState` section appended after existing context:

```
--- CURRENT APP STATE ---
Screen: /blood-tests
Treatment state: IDLE
Valid commands: navigate_to, prefill_pre_treatment, filter_blood_tests, filter_fitness

[when active session exists:]
Active session: 2026-06-04-1 (started 19:00)
Pre: weight=72.4 kg, BP=140/85, pulse=74, UF goal=2.4 L
Readings recorded: 2
  19:15 — BP 130/80, pulse 72, BF 350, VP 150, AP -120
  20:00 — BP 128/78, pulse 70, BF 350, VP 148, AP -118

[when a form is open:]
Open form: add_reading
  time: 20:45 (filled)
  bp_sys: — (empty)
  bp_dia: — (empty)
  pulse: — (empty)
  blood_flow: 350 (defaulted from last reading)
  vp: — (empty)
  ap: — (empty)

RULES:
- Only call tools listed in "Valid commands". If the user requests an invalid command,
  explain why it cannot be done now and what they should do instead.
- For "fill + preview" commands: fill provided fields only; leave unspecified fields
  at their current values. Do not guess or invent values.
- After dispatching a command, describe what you did in plain language.
- If required fields are missing for a command, ask for them before calling the tool.
```

---

## GeminiChatResponder Changes

### Tool declarations

```dart
final _tools = [
  Tool(functionDeclarations: [
    FunctionDeclaration('navigate_to', 'Navigate to a screen',
        Schema.object(properties: {
          'route': Schema.string(description: 'One of: /treatment, /blood-tests, /inventory, /fitness, /kb'),
        }, requiredProperties: ['route'])),
    FunctionDeclaration('filter_blood_tests', 'Navigate to blood tests and apply filter',
        Schema.object(properties: {
          'marker': Schema.string(),
          'phase': Schema.string(),
          'months': Schema.integer(),
          'tab': Schema.string(),
        })),
    FunctionDeclaration('filter_fitness', 'Navigate to fitness and apply filter',
        Schema.object(properties: {
          'type': Schema.string(),
          'days': Schema.integer(),
        })),
    FunctionDeclaration('prefill_pre_treatment', 'Pre-fill pre-treatment form',
        Schema.object(properties: {
          'weight': Schema.number(), 'bp_sys': Schema.integer(),
          'bp_dia': Schema.integer(), 'pulse': Schema.integer(),
          'uf_goal': Schema.number(), 'uf_rate': Schema.number(),
        })),
    FunctionDeclaration('prefill_reading', 'Pre-fill Add Reading form',
        Schema.object(properties: {
          'bp_sys': Schema.integer(), 'bp_dia': Schema.integer(),
          'pulse': Schema.integer(), 'blood_flow': Schema.integer(),
          'vp': Schema.integer(), 'ap': Schema.integer(),
        })),
    FunctionDeclaration('prefill_post_treatment', 'Pre-fill post-treatment form',
        Schema.object(properties: {
          'weight': Schema.number(), 'bp_sys': Schema.integer(),
          'bp_dia': Schema.integer(), 'pulse': Schema.integer(),
          'total_uf': Schema.number(),
        })),
  ]),
];
```

### Tool call loop

Gemini may return a `FunctionCall` part before the final text response. The responder must handle this multi-turn loop:

```
send message → model returns FunctionCall (NOT streamed — full response)
    → dispatch AppCommand via onCommand callback
    → send FunctionResponse back to model
    → model returns final text response (CAN be streamed)
    → yield text chunks to chat
```

**Streaming caveat:** The Gemini SDK's `sendMessageStream` does not stream tool call parts — the `FunctionCall` arrives as a complete `GenerateContentResponse`. Only the second call (after sending the `FunctionResponse`) streams. Implementation must handle this: use `sendMessage` (non-streaming) for the first turn if a tool call is returned, then switch to `sendMessageStream` for the follow-up. If no tool call is returned, the full response streams normally.

`GeminiChatResponder` receives an `onCommand` callback: `void Function(AppCommand)`. This keeps the responder decoupled from Riverpod.

```dart
class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required this.apiKey,
    required this.auth,
    required this.kbStore,
    required this.treatmentRepo,
    required this.btStore,
    required this.cacheStore,
    required this.onCommand,         // ← new
    required this.screenContext,     // ← new
  });

  final void Function(AppCommand) onCommand;
  final AppScreenContext screenContext;
  // ... existing fields
}
```

`ChatController` supplies both. `screenContext` is read fresh on each `send()` call (not watched) — this ensures the context is current at the moment the user sends a message without causing the responder to rebuild mid-conversation:

```dart
// Inside ChatController.send(), before calling responder.reply():
final responder = GeminiChatResponder(
  ...existingArgs,
  onCommand: (cmd) => ref.read(commandBusProvider).add(cmd),
  screenContext: ref.read(screenContextProvider),  // fresh read each time
);
```

---

## CommandBus

```dart
// lib/features/chat/command_bus.dart

sealed class AppCommand {}

class NavigateTo extends AppCommand {
  final String route;
  NavigateTo(this.route);
}

class FilterBloodTests extends AppCommand {
  final String? marker;
  final String? phase;
  final int? months;
  final String? tab; // 'scorecard' | 'trend'
  FilterBloodTests({this.marker, this.phase, this.months, this.tab});
}

class FilterFitness extends AppCommand {
  final String? type;
  final int? days;
  FilterFitness({this.type, this.days});
}

class PrefillPreTreatment extends AppCommand {
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? ufGoal, ufRate;
  PrefillPreTreatment({this.weight, this.bpSys, this.bpDia, this.pulse, this.ufGoal, this.ufRate});
}

class PrefillReading extends AppCommand {
  final int? bpSys, bpDia, pulse, bloodFlow, vp, ap;
  PrefillReading({this.bpSys, this.bpDia, this.pulse, this.bloodFlow, this.vp, this.ap});
}

class PrefillPostTreatment extends AppCommand {
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? totalUf;
  PrefillPostTreatment({this.weight, this.bpSys, this.bpDia, this.pulse, this.totalUf});
}

// Provider — broadcast so multiple screens can listen simultaneously
final commandBusProvider = Provider<StreamController<AppCommand>>(
  (ref) => StreamController<AppCommand>.broadcast(),
);
```

---

## Screen Integration

Each affected screen/feature subscribes to the command bus and reacts to commands it owns.

### Navigation (AppShell or router listener)

```dart
// In AppShell.initState or a top-level widget
ref.listen<StreamController<AppCommand>>(commandBusProvider, (_, bus) {
  bus.stream.listen((cmd) {
    if (cmd is NavigateTo) context.go(cmd.route);
  });
});
```

### BloodTestsScreen

Watches bus for `FilterBloodTests`. On receipt: update local filter state providers and navigate to the correct tab. Executes automatically (no user action needed).

### TreatmentFlow screens

- **HomeScreen**: watches for `PrefillPreTreatment` when state is `idle` → opens PreTreatment form pre-filled
- **ActiveScreen**: watches for `PrefillReading` → opens Add Reading modal pre-filled
- **PostScreen**: watches for `PrefillPostTreatment` → applies values to form fields

### AI-filled field highlighting

Fields pre-filled by AI get a distinct visual treatment (e.g. amber/cyan left border or background tint). Cleared as soon as the user edits the field. Implemented via a `Set<String> aiFilledFields` in each form's local state.

---

## Chat UX During Commands

When the AI dispatches a command, the chat reply narrates what happened:

- "I've opened the pre-treatment form with your weight (72.4 kg) and BP (140/85). Pulse and UF rate are blank — fill those in and tap Start."
- "Hb trend filtered to the last 3 months. Latest value: 112 g/L (up from 108 in March)."
- "There's no active session right now. Want to start one? I can open the pre-treatment form."

When a prefill command is dispatched, the chat sheet animates to a collapsed mini-bar at the bottom of the screen (height ~48 dp, showing "AI filled the form — tap to reopen"). The form is visible behind it. Tapping the mini-bar re-expands the chat sheet to its normal height. The sheet closes fully only when the user taps the close icon.

---

## Files Changed

### New Files

| File | Purpose |
|---|---|
| `flutter/lib/features/chat/command_bus.dart` | `AppCommand` sealed class + `commandBusProvider` |
| `flutter/lib/features/chat/screen_context.dart` | `AppScreenContext`, `TreatmentState`, `ScreenContextNotifier`, `screenContextProvider` |

### Modified Files

| File | Changes |
|---|---|
| `flutter/lib/features/chat/gemini_client.dart` | Add tool declarations, tool call loop, `onCommand` callback, `screenContext` parameter |
| `flutter/lib/features/chat/chat_controller.dart` | Pass `onCommand` + `screenContext` when constructing responder; rebuild responder on screen context change |
| `flutter/lib/features/chat/chat_context.dart` | Add `currentAppState` section to system prompt |
| `flutter/lib/features/blood_tests/blood_tests_screen.dart` | Subscribe to `FilterBloodTests` command; update filter providers |
| `flutter/lib/features/fitness/fitness_screen.dart` | Subscribe to `FilterFitness` command |
| `flutter/lib/features/treatment/screens/home.dart` | Publish screen context (idle state); react to `PrefillPreTreatment` |
| `flutter/lib/features/treatment/screens/pre.dart` | Publish screen context (pre_form + form fields); react to `PrefillPreTreatment` updates; AI-filled field highlighting |
| `flutter/lib/features/treatment/screens/active.dart` | Publish screen context (active + readings); react to `PrefillReading`; AI-filled field highlighting in modal |
| `flutter/lib/features/treatment/screens/post.dart` | Publish screen context (post_form + form fields); react to `PrefillPostTreatment`; AI-filled field highlighting |
| `flutter/lib/app/shell.dart` | Subscribe to `NavigateTo` at top level |

### Not Changed

- `apps-script/Code.gs` — treatment writes still go direct to Apps Script
- `firestore.rules` — no new collections (`blood_tests` collection already exists)

### API changes

| File | Changes |
|---|---|
| `api/src/handlers/bloodTests.ts` | Add `POST /parse-paste` route: port `_parse_portal_paste` Python logic to TypeScript, ref-range lookup from static+Firestore, batch insert |
| `api/src/schemas/bloodTests.ts` | Add `ParsePasteBodySchema` (`{ paste: string, year?: number }`) and `MARKER_MAP` constant |

---

## Out of Scope

- **Inventory commands** — inventory write operations have complex multi-step flows (order placement, delivery confirmation); add after the core 6 commands are proven
- **KB commands** — searching/filtering KB via AI command; deferred to after KB screen is more mature
- **Voice input** — natural speech → command; deferred
- **Multi-step command sequences in one message** — e.g. "start session then show Hb"; Gemini can call multiple tools sequentially, but the UI handling of mid-flow navigation is complex. Initial version: one primary command per message; multi-step deferred
- **Undo for auto-executed commands** — navigation filters are trivially reversible by the user; no undo needed

---

## Future: Phase 2 — Embedded MCP Server

Researched during brainstorm on 2026-06-04. Capturing decisions here so Phase 2 starts from a clear baseline.

**Why not Phase 1:** The in-app Gemini function calling already delivers full control. MCP adds external client access (Gemini CLI, Claude Code) but not new capabilities — build Phase 1 first, prove it works, then add Phase 2.

**Why not Cloud Run for MCP:** Cold start (500ms–2s for Node.js) is unacceptable for mid-session commands. `min-instances=1` fixes it for ~£6/month but adds cost and deployment complexity. Embedding in the Flutter app is simpler, free, and zero cold start.

**Gemini Spark note:** Announced at Google I/O 2026. A 24/7 agentic assistant that executes tasks in third-party apps. Currently US-only, Google AI Ultra ($100/month). UK expected Q3 2026. Likely supports MCP. When available, connect to the same embedded MCP server — no rework needed.

**Architecture:**

```
Flutter app (Android)
├── flutter_mcp embedded server (port 8080, SSE/HTTP transport)
│     └── same AppCommand tool handlers as Phase 1 function calling
│
├── In-app Gemini chat (Phase 1 — unchanged)
│
└── Apps Script (treatment writes — unchanged)

External clients (same WiFi, no tunnel needed at home):
├── Gemini CLI  ──MCP──► app:8080
└── Claude Code ──MCP──► app:8080
```

**Key packages (evaluated 2026-06-04):**
- [`flutter_mcp`](https://pub.dev/packages/flutter_mcp) — MCP server + LLM client + background service + lifecycle + secure storage. Likely the right choice.
- [`dart_mcp`](https://pub.dev/packages/dart_mcp) — official Dart Labs experimental package; both server and client; backed by Dart team. Lower-level, more control.
- [`mcp_server`](https://pub.dev/packages/mcp_server) — focused MCP server implementation, supports SSE + Streamable HTTP transports.

**Implementation note:** Tool handlers in Phase 1 call Riverpod providers directly (in-process). In Phase 2, the same handlers are exposed via the MCP server. No logic duplication — MCP is just an additional transport layer over the same `AppCommand` dispatchers.

---

## Update Log

### 2026-06-04
Initial spec. Extends [[2026-06-03-chat-llm]] with Gemini function calling, AppCommand command bus, AppScreenContext for state-aware prompting, and six tool declarations covering navigation, filtering, and form prefill.

Brainstorm also explored MCP server options (Cloud Run, embedded in app). Decision: Phase 1 is in-app function calling only — all in-process, no Cloud Run, no cold start. Phase 2 (deferred) will embed an MCP server in the Flutter app using `flutter_mcp`/`dart_mcp` so external clients (Gemini CLI, Claude Code, future Gemini Spark) can connect on the same WiFi. Phase 2 adds no new tool logic — just a transport layer over the same `AppCommand` handlers.

Added 7th tool `insert_portal_paste` — a data tool (not UI control) that calls `POST /api/blood-tests/parse-paste` on Cloud Run. Ports the Python PKB paste parser from `scripts/pkb_backfill/parse_pkb.py` to TypeScript. Cold start (~2s) acceptable for a monthly one-off task. Conversation history unaffected by Cloud Run scaling — history lives in Firestore/Flutter memory, Cloud Run is stateless.
