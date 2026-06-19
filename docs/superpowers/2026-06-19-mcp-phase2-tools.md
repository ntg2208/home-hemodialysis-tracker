# MCP Phase 2 (Tools transport) — Spec + Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the existing in-app `AppCommand` tools over an embedded MCP server so external MCP clients (Claude Code, Gemini CLI) on the same WiFi can drive the app — with **zero new tool logic**, just an additional transport over the same handlers.

**Architecture:** A `mcp_server` instance is embedded in the **native Android app** on `:8080` (streamable HTTP). Each MCP tool handler parses arguments into an `AppCommand`, runs the existing `validateCommand` against the live `TreatmentState`, and on success calls the existing `dispatchCommand(cmd, ref)`. Tool names, JSON schemas, and the arg→command parser are extracted into one transport-agnostic module shared by both the Gemini function-calling path and the MCP path. Background survival is handled by a separate **foreground-service** package (orthogonal to MCP). Remote (cross-WiFi) access is via a **Tailscale** mesh (WireGuard-authenticated at the network layer); a bearer key gates any *public* tunnel.

**Tech Stack:** Flutter 3.44, Dart, Riverpod 3.x (`Notifier`/`NotifierProvider`), `mcp_server` package, `flutter_foreground_task` (background survival), `flutter_secure_storage` (bearer key), Hive (settings persistence).

## Context & prior decisions (this is the spec half)

This implements the "Future: Phase 2 — Embedded MCP Server" section of `docs/superpowers/2026-06-04-ai-command-control.md`. Settled there and not reopened here:

- **Embedded, not Cloud Run.** Zero cold start; mid-session commands must be instant. Free, no deploy.
- **One server, both halves** (Tools now; Resources/Skills later). This plan is **Tools-only** — the action transport.
- **Same handlers, no new logic.** MCP is a transport over the same `AppCommand` dispatchers + `validateCommand`.

**In scope (added 2026-06-19 — remote access is now a stated need):** bearer-key auth, background survival via a foreground service, and cross-WiFi access via Tailscale.

**Explicitly out of scope for this plan** (each its own later cycle):
- MCP **Resources** (`health://…` data context) and the **Skills** layer (`pacing-coach.md` etc.) — additive to this server later.
- An **always-on Cloud Run MCP endpoint** for read data/compute (the "agent answers when the phone is off" case). This embedded server only serves live *actions* and only while the Android app runs. The Cloud Run data endpoint is a separate cycle and reopens the health-data-to-network-endpoint privacy question.
- The fitness pacing compute (separate plan).

**Package choice:** `mcp_server` for the server itself — concrete, documented `addTool` / `McpServer.createAndStart` / `TransportConfig.streamableHttp` API (SSE + Streamable HTTP). **Not `flutter_mcp`:** its tool-registration API is undocumented/opaque, and its only relevant extra (background survival) is an *orthogonal* concern better solved by a dedicated foreground-service package. `flutter_foreground_task` keeps the isolate (and thus the `dart:io` socket) alive when the app is backgrounded. **Exact `mcp_server` symbols + the foreground-service behaviour are pinned by the Task 2 spike** before handler code is written.

## Global Constraints

- Riverpod **3.x** API only — `Notifier` + `NotifierProvider` (no legacy `StateProvider`/`StateNotifier`).
- **No new tool logic.** Reuse `validateCommand` and `dispatchCommand` verbatim; do not duplicate validation or routing.
- Server is **opt-in, default OFF**, gated by a persisted settings flag. It must never auto-start in `kCommunity` builds (community flavor has no chat/command layer).
- Tool names, descriptions, and JSON schemas must stay **byte-identical** to the current Gemini declarations in `gemini_client.dart` (they are moved, not rewritten).
- Test command: `flutter test` (run from `flutter/`). All existing tests must stay green after each task.
- Bind to the LAN interface on port **8080**, endpoint **`/mcp`**.
- **Native Android only.** The embedded server uses `dart:io` sockets, which do not exist in the web (PWA) build. The MCP feature is gated to the native build and absent on `homehd.web.app`. **User-facing consequence:** the personal app is normally used as the web PWA — to let an agent drive it you must run the `homehd-personal.apk` and keep it running. Name this in the Settings copy so it isn't a surprise.
- **No public exposure without app-layer auth.** Tailscale (network-layer WireGuard auth) is fine with or without the bearer key. A *public* tunnel (ngrok/Cloudflare) MUST NOT be enabled until the bearer-key check (Task 5) is proven enforcing — an unauthenticated off-LAN endpoint can drive a medical app (prefill forms, end sessions).

## File structure

| File | Responsibility |
|---|---|
| `flutter/lib/features/chat/app_tools.dart` | **New.** Transport-agnostic tool registry: `AppToolSpec` (name/description/inputSchema), `appToolSpecs` list, and public `parseAppCommand(name, args)`. Single source of truth for both transports. |
| `flutter/lib/features/chat/gemini_client.dart` | **Modify.** Build Gemini `{'type':'function',...}` declarations from `appToolSpecs`; parse via `parseAppCommand`. Behavior unchanged. |
| `flutter/lib/features/mcp/hd_mcp_server.dart` | **New.** `HdMcpServer` controller (provider-owned, holds `Ref`): start/stop the `mcp_server`, register handlers, the `handleToolCall` bridge. Start/stop also drives the foreground service. |
| `flutter/lib/features/mcp/mcp_auth.dart` | **New.** Bearer-key: generate-on-first-enable, store in `flutter_secure_storage`, `mcpBearerKeyProvider`, and the request check (Task 5). |
| `flutter/lib/features/mcp/mcp_settings.dart` | **New.** `mcpServerEnabledProvider` (Hive-persisted bool), lifecycle provider, LAN URL helper. |
| `flutter/lib/features/settings/mcp_settings_section.dart` | **New.** Settings UI: enable toggle, the Android-only/keep-running note, displayed `http://<ip>:8080/mcp` URL, and the bearer key (copy-to-clipboard). Personal flavor only. |
| `flutter/test/features/chat/app_tools_test.dart` | **New.** Unit tests for `parseAppCommand`. |
| `flutter/test/features/mcp/hd_mcp_server_test.dart` | **New.** Unit tests for `handleToolCall` (validation + dispatch via a `ProviderContainer`). |
| `flutter/test/features/mcp/mcp_auth_test.dart` | **New.** Unit tests for key generation + the request check. |

---

### Task 1: Extract the shared tool registry

**Files:**
- Create: `flutter/lib/features/chat/app_tools.dart`
- Modify: `flutter/lib/features/chat/gemini_client.dart` (declarations builder ~lines 100-260; `_parseCommand` ~lines 660-710)
- Test: `flutter/test/features/chat/app_tools_test.dart`

**Interfaces:**
- Produces: `class AppToolSpec { final String name; final String description; final Map<String, dynamic> inputSchema; }`, `const List<AppToolSpec> appToolSpecs`, and `AppCommand? parseAppCommand(String name, Map<String, dynamic> args)`.
- Consumes: `AppCommand` subclasses from `command_dispatch.dart`.

> **Forward-reference — keep this module transport-agnostic.** `app_tools.dart` is the single shared substrate for *every* surface over the same handler core, not just MCP: cloud Gemini function calling (today), external MCP clients (this plan), a future **in-app on-device model** (Gemini Nano / Apple Foundation Models — calls `parseAppCommand`/`dispatchCommand` in-process, *not* via the MCP socket), and future **OS agents** (Android **AppFunctions** — "on-device MCP" — and iOS **App Intents**, whose declarations map almost 1:1 onto `appToolSpecs`). See the Home HD vault note `Home HD - AI Command Control` (2026-06-08 on-device AI entry). Do **not** put any MCP-, Gemini-, or HTTP-specific types in here — only tool name/description/JSON-schema and the pure arg→`AppCommand` parse. Each surface adapts these specs to its own declaration format at its own edge.

- [ ] **Step 1: Write the failing test**

```dart
// flutter/test/features/chat/app_tools_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:treatment_tracker/features/chat/app_tools.dart';
import 'package:treatment_tracker/features/chat/command_dispatch.dart';

void main() {
  test('parseAppCommand maps navigate_to', () {
    final cmd = parseAppCommand('navigate_to', {'route': '/fitness'});
    expect(cmd, isA<NavigateTo>());
    expect((cmd as NavigateTo).route, '/fitness');
  });

  test('parseAppCommand coerces numeric prefill fields', () {
    final cmd = parseAppCommand('prefill_pre_treatment',
        {'weight': 72.4, 'bp_sys': 140, 'bp_dia': 85});
    expect(cmd, isA<PrefillPreTreatment>());
    final p = cmd as PrefillPreTreatment;
    expect(p.weight, 72.4);
    expect(p.bpSys, 140);
    expect(p.bpDia, 85);
  });

  test('parseAppCommand returns null for unknown tool', () {
    expect(parseAppCommand('not_a_tool', {}), isNull);
  });

  test('appToolSpecs lists all seven tools', () {
    expect(appToolSpecs.map((t) => t.name).toSet(), {
      'navigate_to', 'filter_blood_tests', 'filter_fitness',
      'prefill_pre_treatment', 'prefill_reading',
      'prefill_post_treatment', 'end_session',
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter && flutter test test/features/chat/app_tools_test.dart`
Expected: FAIL — `app_tools.dart` does not exist (compile error).

- [ ] **Step 3: Create `app_tools.dart`**

Move the JSON schema bodies **verbatim** from each `parameters:` map in `gemini_client.dart` into the `inputSchema` fields below (copy the exact `description` strings — do not paraphrase). Move the `_parseCommand` switch bodies into `parseAppCommand` (cross-check every arg key against the existing `_parseCommand` so coercion stays identical).

```dart
// flutter/lib/features/chat/app_tools.dart
import 'command_dispatch.dart';

/// Transport-agnostic description of one app tool. Consumed by both the
/// Gemini function-calling path and the MCP server.
class AppToolSpec {
  const AppToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;

  /// JSON Schema object: { 'type': 'object', 'properties': {...} }
  final Map<String, dynamic> inputSchema;
}

const List<AppToolSpec> appToolSpecs = [
  AppToolSpec(
    name: 'navigate_to',
    description: 'Navigate to a screen in the app.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'route': {
          'type': 'string',
          'description':
              'One of /treatment, /blood-tests, /fitness, /inventory, /kb',
        },
      },
    },
  ),
  AppToolSpec(
    name: 'filter_blood_tests',
    description:
        'Navigate to blood tests and apply a filter. All parameters are optional.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'marker': {
          'type': 'string',
          'description':
              'Canonical marker name, e.g. haemoglobin, ferritin, potassium',
        },
        'phase': {
          'type': 'string',
          'description': 'home-hd, in-center-hd, or admission',
        },
        'months': {
          'type': 'integer',
          'description': 'Number of months back from today',
        },
        'tab': {'type': 'string', 'description': 'scorecard or trend'},
      },
    },
  ),
  AppToolSpec(
    name: 'filter_fitness',
    description: 'Navigate to fitness and filter by type and/or time window.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'description': 'steps, sleep, heart-rate, or hrv',
        },
        'days': {
          'type': 'integer',
          'description': 'Number of days back from today',
        },
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_pre_treatment',
    description:
        'Open the pre-treatment form and pre-fill fields. Valid only when idle. All parameters optional.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {'type': 'number', 'description': 'Pre weight in kg'},
        'bp_sys': {'type': 'integer', 'description': 'Systolic BP'},
        'bp_dia': {'type': 'integer', 'description': 'Diastolic BP'},
        'pulse': {'type': 'integer', 'description': 'Pulse'},
        'uf_goal': {'type': 'number', 'description': 'UF goal in litres'},
        'uf_rate': {'type': 'number', 'description': 'UF rate in mL/h'},
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_reading',
    description:
        'Open the add-reading sheet and pre-fill fields. Valid only during an active session. All parameters optional.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'bp_sys': {'type': 'integer', 'description': 'Systolic BP'},
        'bp_dia': {'type': 'integer', 'description': 'Diastolic BP'},
        'pulse': {'type': 'integer', 'description': 'Pulse'},
        'blood_flow': {'type': 'integer', 'description': 'Blood flow mL/min'},
        'vp': {'type': 'integer', 'description': 'Venous pressure'},
        'ap': {'type': 'integer', 'description': 'Arterial pressure'},
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_post_treatment',
    description:
        'Open the post-treatment form and pre-fill fields. Valid only in the post form. All parameters optional.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {'type': 'number', 'description': 'Post weight in kg'},
        'bp_sys': {'type': 'integer', 'description': 'Systolic BP'},
        'bp_dia': {'type': 'integer', 'description': 'Diastolic BP'},
        'pulse': {'type': 'integer', 'description': 'Pulse'},
        'total_uf': {'type': 'number', 'description': 'Total UF in litres'},
      },
    },
  ),
  AppToolSpec(
    name: 'end_session',
    description:
        'End the active session, optionally pre-filling post-treatment values. Valid only during an active session.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {'type': 'number', 'description': 'Post weight in kg'},
        'bp_sys': {'type': 'integer', 'description': 'Systolic BP'},
        'bp_dia': {'type': 'integer', 'description': 'Diastolic BP'},
        'pulse': {'type': 'integer', 'description': 'Pulse'},
        'total_uf': {'type': 'number', 'description': 'Total UF in litres'},
      },
    },
  ),
];

/// Maps an MCP/Gemini tool call to an [AppCommand]. Returns null for an
/// unknown tool. Numeric coercion handles num-typed JSON args.
AppCommand? parseAppCommand(String name, Map<String, dynamic> a) {
  double? d(String k) => (a[k] as num?)?.toDouble();
  int? i(String k) => (a[k] as num?)?.toInt();
  switch (name) {
    case 'navigate_to':
      return NavigateTo(a['route'] as String? ?? '/treatment');
    case 'filter_blood_tests':
      return FilterBloodTests(
        marker: a['marker'] as String?,
        phase: a['phase'] as String?,
        months: i('months'),
        tab: a['tab'] as String?,
      );
    case 'filter_fitness':
      return FilterFitness(type: a['type'] as String?, days: i('days'));
    case 'prefill_pre_treatment':
      return PrefillPreTreatment(
        weight: d('weight'), bpSys: i('bp_sys'), bpDia: i('bp_dia'),
        pulse: i('pulse'), ufGoal: d('uf_goal'), ufRate: d('uf_rate'),
      );
    case 'prefill_reading':
      return PrefillReading(
        bpSys: i('bp_sys'), bpDia: i('bp_dia'), pulse: i('pulse'),
        bloodFlow: i('blood_flow'), vp: i('vp'), ap: i('ap'),
      );
    case 'prefill_post_treatment':
      return PrefillPostTreatment(
        weight: d('weight'), bpSys: i('bp_sys'), bpDia: i('bp_dia'),
        pulse: i('pulse'), totalUf: d('total_uf'),
      );
    case 'end_session':
      return EndSession(
        weight: d('weight'), bpSys: i('bp_sys'), bpDia: i('bp_dia'),
        pulse: i('pulse'), totalUf: d('total_uf'),
      );
    default:
      return null;
  }
}
```

- [ ] **Step 4: Refactor `gemini_client.dart` to use the registry**

`gemini_client.dart` has a `static const _oaiTools` of **10** declarations: the 7 command tools (`navigate_to` … `end_session`) **plus 3 retriever tools** (`get_blood_markers`, `get_sessions`, `get_out_of_range_markers`) that return data via `RetrieverTools` and are **not** `AppCommand`s. Only the **7 command tools** move to the registry; the retriever tools stay here. Add `import 'app_tools.dart';` and:

1. Move the 3 retriever map literals **verbatim** out of `_oaiTools` into a new `static const _retrieverTools = [ … ]` (the three `{'type':'function','function':{'name':'get_…'}}` entries, unchanged).
2. Replace `_oaiTools` with a builder that combines the command tools (from `appToolSpecs`) with the retriever tools. A collection-`for` can't appear in a `const` list, so change `static const _oaiTools` → `static final`:

```dart
static final List<Map<String, dynamic>> _oaiTools = [
  for (final t in appToolSpecs)
    {
      'type': 'function',
      'function': {
        'name': t.name,
        'description': t.description,
        'parameters': t.inputSchema,
      },
    },
  ..._retrieverTools,
];
```

3. Replace the `_parseCommand` switch body with a delegation — **keep its existing signature** (args are `Map<String, Object?>`, assignable to `parseAppCommand`'s `Map<String, dynamic>`):

```dart
AppCommand? _parseCommand(String name, Map<String, Object?> args) =>
    parseAppCommand(name, args);
```

**Source of truth for the 7 command schemas = the existing `_oaiTools` entries, not the reconstructed schemas in Step 3.** Before finalizing `app_tools.dart`, diff each `inputSchema` against the live `parameters` map and make them byte-identical (exact `description` strings and any `'required'` arrays). The `gemini_responder` test exercises the full 10-tool payload and must stay green.

- [ ] **Step 5: Run the new + existing chat tests to verify all pass**

Run: `cd flutter && flutter test test/features/chat/`
Expected: PASS — `app_tools_test.dart` green AND the existing `command_validator_test.dart` and any chat tests still green (declarations/parse behavior unchanged).

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/chat/app_tools.dart flutter/lib/features/chat/gemini_client.dart flutter/test/features/chat/app_tools_test.dart
git commit -m "refactor(chat): extract transport-agnostic tool registry (app_tools.dart)"
```

---

### Task 2: Add `mcp_server` and pin its API with a spike

**Files:**
- Modify: `flutter/pubspec.yaml`
- Create (temporary): `flutter/lib/features/mcp/spike_main.dart` (deleted at end of task)

**Interfaces:**
- Produces: confirmed symbol names for the next tasks — the server factory, the tool-registration call, the handler signature, the result type, and the streamable-HTTP transport config — recorded in this task's notes.

- [ ] **Step 1: Add the dependency**

Add to `flutter/pubspec.yaml` under `dependencies:` (pin to latest published; record resolved versions). `flutter_secure_storage` may already be present (used for keys elsewhere) — reuse it if so.

```yaml
  mcp_server: ^1.0.0
  flutter_foreground_task: ^8.0.0   # background survival (Android)
  flutter_secure_storage: ^9.0.0    # bearer key (skip if already a dep)
```

Run: `cd flutter && flutter pub get`
Expected: resolves without conflict. Note the exact resolved versions in this file's Update Log.

- [ ] **Step 2: Write a throwaway spike server**

Create `flutter/lib/features/mcp/spike_main.dart` registering one echo tool and starting streamable HTTP on `:8080`. Use the API from the package's own README/example (the names below match the documented `mcp_server` API — **confirm against the installed version and correct any mismatch before proceeding**):

```dart
import 'package:mcp_server/mcp_server.dart';

Future<void> main() async {
  final result = await McpServer.createAndStart(
    config: McpServer.simpleConfig(name: 'HD Tracker', version: '0.1.0'),
    transportConfig: TransportConfig.streamableHttp(
      host: '0.0.0.0',
      port: 8080,
      endpoint: '/mcp',
      isJsonResponseEnabled: false,
    ),
  );
  final server = result.get();
  server.addTool(
    name: 'echo',
    description: 'Echoes its input',
    inputSchema: {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'}
      },
    },
    handler: (args) async => CallToolResult(
      content: [TextContent(text: 'echo: ${args['text']}')],
      isError: false,
    ),
  );
}
```

- [ ] **Step 3: Run the spike and round-trip a client**

Run the spike on a desktop target: `cd flutter && flutter run -d macos -t lib/features/mcp/spike_main.dart` (or any available desktop device).
Then connect the MCP Inspector from another terminal:

Run: `npx @modelcontextprotocol/inspector`
Connect transport: **Streamable HTTP**, URL `http://localhost:8080/mcp`. List tools → expect `echo`. Call `echo` with `{"text":"hi"}` → expect `echo: hi`.

Expected: tool lists and the call returns `echo: hi`.

- [ ] **Step 4: Record the confirmed API + isolate behavior**

In this file's Update Log note the exact, verified symbols: server factory, `addTool` parameter names, handler argument type, result/content types, transport config constructor. Also resolve three things the later tasks depend on:

- **Isolate:** Confirm the handler runs on the main isolate (add a `print(Isolate.current.debugName)` or set a top-level variable from the handler and confirm it's the root isolate) — Task 3 mutates Riverpod providers from the handler, only safe on the main isolate. If off-isolate, Task 3 must marshal via `SendPort`/`scheduleMicrotask` on the root isolate; record the finding.
- **Header hook (gates the bearer key, Task 5):** Determine whether `TransportConfig.streamableHttp` exposes incoming request headers to a middleware/guard hook. If **yes**, Task 5's key check lives there. If **no**, record it: the bearer key cannot be enforced in-transport, so **public-tunnel exposure stays blocked** and Task 5 either (a) fronts the server with a minimal `dart:io` `HttpServer` proxy that checks the header, or (b) is deferred — Tailscale-only remote needs no app-layer key regardless.
- **Foreground service:** Confirm `flutter_foreground_task` keeps the `dart:io` socket listening when the app is backgrounded (start the spike server, background the app, hit the endpoint from another device). Record whether a persistent notification is required (it is, on Android) and the minimal config.

- [ ] **Step 5: Delete the spike and commit the dependency**

```bash
rm flutter/lib/features/mcp/spike_main.dart
git add flutter/pubspec.yaml flutter/pubspec.lock
git commit -m "chore(mcp): add mcp_server dependency (API pinned via spike)"
```

---

### Task 3: Build the MCP server controller + handler bridge

**Files:**
- Create: `flutter/lib/features/mcp/hd_mcp_server.dart`
- Test: `flutter/test/features/mcp/hd_mcp_server_test.dart`

**Interfaces:**
- Consumes: `appToolSpecs`, `parseAppCommand` (Task 1); `validateCommand` (`command_validator.dart`); `dispatchCommand` (`command_dispatch.dart`); `screenContextProvider` (`screen_context.dart`).
- Produces: `Future<CallToolResult> handleToolCall(String name, Map<String, dynamic> args, Ref ref)` (the pure-ish bridge, unit-tested), and `class HdMcpServer` with `Future<void> start()` / `Future<void> stop()`, exposed as `hdMcpServerProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter/test/features/mcp/hd_mcp_server_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treatment_tracker/features/chat/command_dispatch.dart';
import 'package:treatment_tracker/features/chat/screen_context.dart';
import 'package:treatment_tracker/features/mcp/hd_mcp_server.dart';

// A ProviderContainer is NOT a Ref. Expose one via a Provider so handlers/
// dispatch (which take a Ref) can be exercised in tests.
final _refProvider = Provider<Ref>((ref) => ref);

(ProviderContainer, Ref) _setup(TreatmentState state) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(screenContextProvider.notifier).setTreatmentState(state);
  return (c, c.read(_refProvider));
}

void main() {
  test('valid navigate_to dispatches and returns ok', () async {
    final (c, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('navigate_to', {'route': '/fitness'}, ref);
    expect(res.isError, isFalse);
    expect(c.read(pendingNavigationProvider), '/fitness');
  });

  test('prefill_reading while idle returns a validation error, no dispatch', () async {
    final (c, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('prefill_reading', {'bp_sys': 120}, ref);
    expect(res.isError, isTrue);
    expect(c.read(prefillReadingCommandProvider), isNull);
  });

  test('unknown tool returns an error', () async {
    final (_, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('nope', {}, ref);
    expect(res.isError, isTrue);
  });
}
```

> Note: `setTreatmentState` (in `screen_context.dart`) takes the state as its first positional arg plus optional named args — confirm the exact signature when implementing and pass `state` positionally as shown. If reading `screenContextProvider.notifier` requires Hive/other setup, add the matching `setUp` (see Task 4's Hive init pattern).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter && flutter test test/features/mcp/hd_mcp_server_test.dart`
Expected: FAIL — `hd_mcp_server.dart` does not exist.

- [ ] **Step 3: Implement the controller + bridge**

```dart
// flutter/lib/features/mcp/hd_mcp_server.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_server/mcp_server.dart';

import '../chat/app_tools.dart';
import '../chat/command_dispatch.dart';
import '../chat/command_validator.dart';
import '../chat/screen_context.dart';

/// Bridge: parse → validate against live TreatmentState → dispatch.
/// Pure with respect to [ref]; unit-tested with a ProviderContainer.
Future<CallToolResult> handleToolCall(
    String name, Map<String, dynamic> args, Ref ref) async {
  final cmd = parseAppCommand(name, args);
  if (cmd == null) {
    return CallToolResult(
      content: [TextContent(text: 'Unknown tool: $name')],
      isError: true,
    );
  }
  final state = ref.read(screenContextProvider).treatmentState;
  final error = validateCommand(cmd, state);
  if (error != null) {
    return CallToolResult(content: [TextContent(text: error)], isError: true);
  }
  dispatchCommand(cmd, ref);
  return CallToolResult(
    content: [TextContent(text: 'Done: $name')],
    isError: false,
  );
}

/// Owns the embedded MCP server lifecycle. Provider-scoped so it holds a [Ref]
/// that handler closures use to dispatch into the app.
class HdMcpServer {
  HdMcpServer(this.ref);
  final Ref ref;
  Server? _server;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final result = await McpServer.createAndStart(
      config: McpServer.simpleConfig(name: 'HD Tracker', version: '1.0.0'),
      transportConfig: TransportConfig.streamableHttp(
        host: '0.0.0.0',
        port: 8080,
        endpoint: '/mcp',
        isJsonResponseEnabled: false,
      ),
    );
    final server = result.get();
    for (final t in appToolSpecs) {
      server.addTool(
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema,
        handler: (args) => handleToolCall(t.name, args, ref),
      );
    }
    _server = server;
  }

  Future<void> stop() async {
    await _server?.dispose();
    _server = null;
  }
}

final hdMcpServerProvider =
    Provider<HdMcpServer>((ref) => HdMcpServer(ref));
```

> Adjust `Server`, `result.get()`, `_server?.dispose()`, and the transport constructor to the exact symbols recorded in Task 2 if they differ.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter && flutter test test/features/mcp/hd_mcp_server_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/mcp/hd_mcp_server.dart flutter/test/features/mcp/hd_mcp_server_test.dart
git commit -m "feat(mcp): embedded MCP server controller + tool handler bridge"
```

---

### Task 4: Settings toggle, lifecycle, and LAN URL

**Files:**
- Create: `flutter/lib/features/mcp/mcp_settings.dart`
- Create: `flutter/lib/features/settings/mcp_settings_section.dart`
- Modify: `flutter/lib/features/settings/settings_screen.dart` (personal flavor settings list)
- Test: `flutter/test/features/mcp/mcp_settings_test.dart`

**Interfaces:**
- Consumes: `hdMcpServerProvider` (Task 3); the existing Hive settings box used by other prefs (e.g. `treatment` box per `notification_prefs.dart`).
- Produces: `mcpServerEnabledProvider` (`NotifierProvider<…, bool>`, Hive-persisted) and `Future<String> mcpLanUrl()`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter/test/features/mcp/mcp_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:treatment_tracker/features/mcp/mcp_settings.dart';

void main() {
  setUp(() async {
    Hive.init('./.test_hive');
    await Hive.openBox('treatment');
  });
  tearDown(() async => Hive.deleteFromDisk());

  test('mcpServerEnabled defaults to false and persists when set', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(mcpServerEnabledProvider), isFalse);
    c.read(mcpServerEnabledProvider.notifier).set(true);
    expect(c.read(mcpServerEnabledProvider), isTrue);
    expect(Hive.box('treatment').get('mcp_server_enabled'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter && flutter test test/features/mcp/mcp_settings_test.dart`
Expected: FAIL — `mcp_settings.dart` does not exist.

- [ ] **Step 3: Implement the flag + URL helper**

```dart
// flutter/lib/features/mcp/mcp_settings.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

const _kBox = 'treatment';
const _kKey = 'mcp_server_enabled';

class McpServerEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => Hive.box(_kBox).get(_kKey, defaultValue: false) as bool;

  void set(bool v) {
    Hive.box(_kBox).put(_kKey, v);
    state = v;
  }
}

final mcpServerEnabledProvider =
    NotifierProvider<McpServerEnabledNotifier, bool>(
  McpServerEnabledNotifier.new,
);

/// Best-effort LAN URL for display. Picks the first non-loopback IPv4.
Future<String> mcpLanUrl() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  for (final ni in interfaces) {
    for (final addr in ni.addresses) {
      if (!addr.isLoopback) return 'http://${addr.address}:8080/mcp';
    }
  }
  return 'http://localhost:8080/mcp';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter && flutter test test/features/mcp/mcp_settings_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire start/stop to the flag (lifecycle)**

In `mcp_settings.dart`, add a listener that starts/stops the server when the flag changes, and runs once at app start. Add this provider and watch it from the personal app root (e.g. `shell.dart` or wherever the personal app is built — NOT the community flavor):

```dart
// append to mcp_settings.dart
final mcpLifecycleProvider = Provider<void>((ref) {
  final enabled = ref.watch(mcpServerEnabledProvider);
  final server = ref.read(hdMcpServerProvider);
  if (enabled) {
    startMcpForegroundService(); // keep the isolate alive when backgrounded
    server.start();
  } else {
    server.stop();
    stopMcpForegroundService();
  }
});
```

Add `import 'hd_mcp_server.dart';` to `mcp_settings.dart`. In the personal app root, add `ref.watch(mcpLifecycleProvider);` inside the build of a `ConsumerWidget`/`ConsumerState` that lives for the app's lifetime. Guard with the existing community flag so it never runs in `kCommunity` builds.

- [ ] **Step 5b: Implement the foreground service helpers**

Using the `flutter_foreground_task` config confirmed in the Task 2 spike, add `startMcpForegroundService()` / `stopMcpForegroundService()` to `hd_mcp_server.dart` (or a small `mcp/foreground.dart`). They show/clear a persistent "HD Tracker MCP server running" notification so Android does not kill the process. No-op on non-Android platforms. Verify manually: enable the toggle, background the app, confirm the notification persists and the endpoint still responds from another device on the LAN.

- [ ] **Step 6: Build the settings section**

```dart
// flutter/lib/features/settings/mcp_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mcp/mcp_settings.dart';

class McpSettingsSection extends ConsumerWidget {
  const McpSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(mcpServerEnabledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('MCP SERVER',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        SwitchListTile(
          title: const Text('Allow external AI clients (same WiFi)'),
          subtitle: const Text(
              'Lets Claude Code / Gemini CLI drive the app over your local network. '
              'Android app only — keep it running. For other networks, use Tailscale.'),
          value: enabled,
          onChanged: (v) =>
              ref.read(mcpServerEnabledProvider.notifier).set(v),
        ),
        if (enabled)
          FutureBuilder<String>(
            future: mcpLanUrl(),
            builder: (context, snap) => ListTile(
              dense: true,
              title: const Text('Connect URL'),
              subtitle: Text(snap.data ?? '…'),
            ),
          ),
      ],
    );
  }
}
```

Then add `const McpSettingsSection()` to the personal `settings_screen.dart` list (after the existing sections). Do **not** add it to `community_settings_screen.dart`.

- [ ] **Step 7: Run the full suite**

Run: `cd flutter && flutter test`
Expected: PASS — all existing + new tests green.

- [ ] **Step 8: Commit**

```bash
git add flutter/lib/features/mcp/mcp_settings.dart flutter/lib/features/settings/mcp_settings_section.dart flutter/lib/features/settings/settings_screen.dart flutter/test/features/mcp/mcp_settings_test.dart
git commit -m "feat(mcp): settings toggle, lifecycle wiring, LAN URL (personal only)"
```

---

### Task 5: Bearer-key auth (gates public-tunnel exposure)

> Required **only before exposing via a public tunnel**. Tailscale-only remote (Task 6) is network-authenticated and needs no app-layer key. Enforcement location depends on the Task 2 header-hook finding.

**Files:**
- Create: `flutter/lib/features/mcp/mcp_auth.dart`
- Modify: `flutter/lib/features/mcp/hd_mcp_server.dart` (apply the guard), `flutter/lib/features/settings/mcp_settings_section.dart` (show the key)
- Test: `flutter/test/features/mcp/mcp_auth_test.dart`

**Interfaces:**
- Produces: `String generateMcpKey()`, `Future<String> mcpLoadOrCreateKey()`, `bool checkBearer(String? authHeader, String expectedKey)`, `mcpBearerKeyProvider` (`FutureProvider<String>`).

- [ ] **Step 1: Write the failing test (pure helpers only)**

```dart
// flutter/test/features/mcp/mcp_auth_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:treatment_tracker/features/mcp/mcp_auth.dart';

void main() {
  test('generateMcpKey returns 64 hex chars', () {
    final k = generateMcpKey();
    expect(k.length, 64);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(k), isTrue);
    expect(generateMcpKey(), isNot(k)); // random each call
  });

  test('checkBearer accepts the exact Bearer header and rejects others', () {
    expect(checkBearer('Bearer abc', 'abc'), isTrue);
    expect(checkBearer('Bearer xyz', 'abc'), isFalse);
    expect(checkBearer('abc', 'abc'), isFalse); // missing scheme
    expect(checkBearer(null, 'abc'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter && flutter test test/features/mcp/mcp_auth_test.dart`
Expected: FAIL — `mcp_auth.dart` does not exist.

- [ ] **Step 3: Implement `mcp_auth.dart`**

```dart
// flutter/lib/features/mcp/mcp_auth.dart
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _kKey = 'mcp_bearer_key';

String generateMcpKey() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<String> mcpLoadOrCreateKey() async {
  final existing = await _storage.read(key: _kKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final key = generateMcpKey();
  await _storage.write(key: _kKey, value: key);
  return key;
}

bool checkBearer(String? authHeader, String expectedKey) =>
    authHeader != null && authHeader == 'Bearer $expectedKey';

final mcpBearerKeyProvider =
    FutureProvider<String>((ref) => mcpLoadOrCreateKey());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter && flutter test test/features/mcp/mcp_auth_test.dart`
Expected: PASS. (Storage read/write is exercised manually on device, not in unit tests — it needs platform channels.)

- [ ] **Step 5: Apply the guard (conditional on the Task 2 finding)**

- If Task 2 confirmed the streamable-HTTP transport exposes request headers to a hook: in `HdMcpServer.start()`, read `await mcpLoadOrCreateKey()` and register the guard so any request failing `checkBearer(header, key)` is rejected (401) before reaching a tool handler.
- If Task 2 found **no** header hook: do **not** fake it. Record in the Update Log that public-tunnel exposure stays blocked, and either (a) front the server with a minimal `dart:io` `HttpServer` that checks `Authorization` and proxies to `:8080`, or (b) defer — Tailscale-only remote is unaffected. Pick (b) unless a public tunnel is actually needed.

- [ ] **Step 6: Show the key in Settings**

Add a `ListTile` to `McpSettingsSection` (visible only when enabled) that watches `mcpBearerKeyProvider` and shows the key with a copy-to-clipboard icon, labelled "Bearer key (only needed for public tunnels — not for same-WiFi or Tailscale)."

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/mcp/mcp_auth.dart flutter/lib/features/settings/mcp_settings_section.dart flutter/lib/features/mcp/hd_mcp_server.dart flutter/test/features/mcp/mcp_auth_test.dart
git commit -m "feat(mcp): bearer-key auth (gates public-tunnel exposure)"
```

---

### Task 6: End-to-end verification on device + docs

**Files:**
- Modify: this plan's Update Log (record the verification result).

**Interfaces:** none (manual acceptance).

- [ ] **Step 1: Run the personal app on an Android device on home WiFi**

Run: `cd flutter && flutter run -d <android-device>` (personal flavor). Settings → MCP Server → toggle on. Note the displayed Connect URL (e.g. `http://192.168.1.x:8080/mcp`).

- [ ] **Step 2: Connect Claude Code from a laptop on the same WiFi**

Add the server, e.g.:

```bash
claude mcp add --transport http hd-tracker http://192.168.1.x:8080/mcp
```

In Claude Code, confirm the 7 tools are listed.

- [ ] **Step 3: Verify a happy-path command**

Ask Claude Code to call `navigate_to` with `{"route":"/fitness"}`.
Expected: the phone navigates to the Fitness screen; the tool returns `Done: navigate_to`.

- [ ] **Step 4: Verify a state-machine rejection**

With the app idle, ask Claude Code to call `prefill_reading` with `{"bp_sys":120}`.
Expected: the tool returns the `validateCommand` error string (`isError: true`); the app does **not** open the reading sheet.

- [ ] **Step 5: Verify background survival**

With the toggle on, press Home (background the app). Confirm the persistent "MCP server running" notification. From Claude Code, re-list tools and call `navigate_to`.
Expected: tools still listed; the call succeeds (foreground service kept the socket alive).

- [ ] **Step 6: Verify cross-WiFi via Tailscale**

Install Tailscale on the phone and the laptop, sign both into the same tailnet. Put the laptop on a *different* network (e.g. phone hotspot for the laptop, phone itself on home WiFi — or vice versa). Re-add the server in Claude Code using the phone's **Tailscale IP**:

```bash
claude mcp add --transport http hd-tracker-ts http://<phone-tailscale-ip>:8080/mcp
```

List tools and call `navigate_to`.
Expected: works across networks with no public exposure and no bearer key (WireGuard authenticates the mesh). Confirm the same URL is **unreachable** from a device *not* on the tailnet.

- [ ] **Step 7: Verify the off switch**

Toggle MCP Server off in Settings. Re-list tools from Claude Code.
Expected: connection refused / no tools — server stopped, notification cleared.

- [ ] **Step 8: Record results + commit**

Append a dated entry to this file's Update Log: confirmed tool count, the happy-path + rejection results, background-survival result, the Tailscale cross-WiFi result, the off-switch behavior, the resolved package versions, and the Task 2 findings (isolate, header-hook, foreground config).

```bash
git add docs/superpowers/2026-06-19-mcp-phase2-tools.md
git commit -m "docs(mcp): record Phase 2 Tools end-to-end verification"
```

---

## Access tiers & security (read before enabling)

The server exposes **app-control over a medical app** (prefill forms, end sessions). Treat reach as a safety boundary, not just privacy. Three tiers, in increasing risk:

| Tier | Auth | Verdict |
|---|---|---|
| **Same WiFi (LAN)** | None | OK for single-user home WiFi, toggle default-off. Anyone on the LAN can reach it — fine at home, never on untrusted WiFi. |
| **Tailscale (cross-WiFi)** | WireGuard mesh (network-layer) | **Primary remote path.** Only devices in your tailnet can connect. No app-layer key required. No public surface. |
| **Public tunnel (ngrok/Cloudflare)** | Bearer key (Task 5) | **Blocked** until the bearer-key check is proven enforcing (depends on the Task 2 header-hook finding). An unauthenticated public endpoint driving this app is unacceptable. Avoid unless genuinely needed. |

**Hard rules:** never port-forward `:8080`; never enable a public tunnel without a working bearer key; keep the toggle default-off. The "agent answers when the phone is off / app is killed" case is **not** solvable here (embedded server dies with the process) — that's the deferred Cloud Run **read-only** data endpoint, which is a separate cycle and reopens the health-data-to-network-endpoint privacy question from the 2026-06-08 notes.

## Update Log

### 2026-06-19
Initial spec + plan. Tools-first, embedded `mcp_server`, default-off. Grounded against the live `command_dispatch.dart` / `command_validator.dart` / `gemini_client.dart`. Resources, Skills, and the always-on Cloud Run data endpoint deferred to their own cycles.

### 2026-06-19 (revision — connection requirements)
Folded in stated needs for keyed + cross-WiFi access. Changes: (1) **kept `mcp_server`** (verified API) and added `flutter_foreground_task` for background survival — rejected switching to `flutter_mcp` (opaque tool API; background survival is orthogonal); (2) **Tailscale is the primary remote path** (network-layer WireGuard auth, no app-layer key needed); (3) added a **bearer-key task (Task 5)** that *gates public tunnels only*, contingent on the Task 2 header-hook spike; (4) documented **native-Android-only** (web PWA can't host a `dart:io` server) and the keep-the-APK-running friction. Now 6 tasks. The "answer when phone is off" case remains the deferred Cloud Run read endpoint.
