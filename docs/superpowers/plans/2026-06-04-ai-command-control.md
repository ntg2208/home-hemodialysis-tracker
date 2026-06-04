# AI Command Control — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the in-app Gemini chat drive the Flutter app — navigate screens, apply filters, and pre-fill treatment forms — via Gemini function calling and per-command Riverpod StateProviders.

**Architecture:** `GeminiChatResponder` calls `model.generateContent()` in a loop until no function calls remain; each call is validated against `TreatmentState` in Dart before being dispatched to a per-command `StateProvider<T?>` that the relevant screen drains on mount. All six tools are in-process: no Cloud Run calls.

**Tech Stack:** Flutter (Dart), `google_generative_ai ^0.4.7`, Riverpod, GoRouter. Tests via `flutter_test` / `flutter_riverpod/testing`.

---

## File Map

| Status | File | Responsibility |
|---|---|---|
| NEW | `flutter/lib/features/chat/command_dispatch.dart` | `AppCommand` sealed class + all `StateProvider<T?>` dispatch providers |
| NEW | `flutter/lib/features/chat/command_validator.dart` | `validateCommand()` pure function — Dart-enforced state-machine rules |
| NEW | `flutter/lib/features/chat/screen_context.dart` | `AppScreenContext`, `TreatmentState`, `ScreenContextNotifier`, `screenContextProvider` |
| MODIFY | `flutter/lib/features/chat/gemini_client.dart` | Tool declarations; `model.generateContent()` loop; `onCommand`/`screenContext` params |
| MODIFY | `flutter/lib/features/chat/chat_controller.dart` | Build fresh responder with `onCommand` + `screenContext` on each `send()` |
| MODIFY | `flutter/lib/features/chat/chat_context.dart` | `buildAppState()` appended to system prompt |
| MODIFY | `flutter/lib/app/shell.dart` | `ref.listen(pendingNavigationProvider)` in `_AppShellState` |
| MODIFY | `flutter/lib/features/treatment/treatment_flow.dart` | Publish `TreatmentState`; react to `prefillPreCommandProvider` |
| MODIFY | `flutter/lib/features/treatment/screens/pre.dart` | Drain `prefillPreCommandProvider`; AI-field highlighting |
| MODIFY | `flutter/lib/features/treatment/screens/active.dart` | Drain `prefillReadingCommandProvider`; open sheet with prefill |
| MODIFY | `flutter/lib/features/treatment/widgets/add_reading_sheet.dart` | Accept `initialValues: PrefillReading?`; AI-field highlighting |
| MODIFY | `flutter/lib/features/treatment/screens/post.dart` | Drain `prefillPostCommandProvider`; AI-field highlighting |
| MODIFY | `flutter/lib/features/blood_tests/blood_tests_screen.dart` | Drain `btFilterCommandProvider`; update `_filter` |
| MODIFY | `flutter/lib/features/fitness/fitness_screen.dart` | Drain `fitnessFilterCommandProvider` |
| NEW TEST | `flutter/test/features/chat/command_validator_test.dart` | Unit tests for every invalid state transition |

---

## Task 1: Spike — verify `navigate_to` end-to-end before building out

**Purpose:** Confirm the SDK function-calling loop works (`model.generateContent`, `response.functionCalls.toList()`, `FunctionResponse`), the `StateProvider` dispatch pattern is race-free, and AppShell navigation fires correctly. Do this against the real installed SDK before writing 13 more tasks on top of unverified assumptions.

**Files:**
- Modify temporarily: `flutter/lib/features/chat/gemini_client.dart`
- Create temporarily: `flutter/lib/features/chat/_spike_dispatch.dart`

- [ ] **Step 1: Add a temporary `navigate_to` tool declaration to `GeminiChatResponder`**

Open `flutter/lib/features/chat/gemini_client.dart`. In the `reply()` method, replace the `GenerativeModel(...)` call with:

```dart
final tools = [
  Tool(functionDeclarations: [
    FunctionDeclaration(
      'navigate_to',
      'Navigate to a screen. Call this when the user asks to go somewhere.',
      Schema.object(properties: {
        'route': Schema.string(
          description: 'One of: /treatment, /blood-tests, /inventory, /fitness, /kb',
        ),
      }, requiredProperties: ['route']),
    ),
  ]),
];

final model = GenerativeModel(
  model: 'gemini-2.5-flash',
  apiKey: apiKey,
  tools: tools,
  systemInstruction: Content.system(systemPrompt),
  generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 1024),
);
```

- [ ] **Step 2: Replace `chat.sendMessageStream` with a `generateContent` loop**

Still in `gemini_client.dart`, replace the try block inside `reply()` with:

```dart
// Build content list from existing history + new message
final contents = [
  ...sdkHistory,
  Content.text(prompt),
];

String finalText = '';
try {
  var response = await model.generateContent(contents);

  // Tool call loop — runs until model returns text with no function calls
  while (response.functionCalls.isNotEmpty) {
    final functionResponses = <Content>[];
    for (final call in response.functionCalls) {
      // Dispatch: for spike just print; real dispatch in Task 8
      debugPrint('[SPIKE] tool call: ${call.name} args: ${call.args}');
      functionResponses.add(
        Content.functionResponse(call.name, {'ok': true, 'dispatched': call.name}),
      );
    }
    // Append model response + function responses to content list
    contents.add(response.candidates.first.content);
    contents.addAll(functionResponses);
    response = await model.generateContent(contents);
  }

  finalText = response.text ?? '';
} on GenerativeAIException catch (e) {
  // same error mapping as before
  final msg = e.message.toLowerCase();
  if (msg.contains('api key') || msg.contains('401') || msg.contains('403')) {
    throw ChatError.invalidKey;
  } else if (msg.contains('quota') || msg.contains('429')) {
    throw ChatError.rateLimited;
  } else {
    throw ChatError.serverError;
  }
} catch (_) {
  throw ChatError.network;
}

yield finalText;
```

- [ ] **Step 3: Add a temporary StateProvider for navigation**

Create `flutter/lib/features/chat/_spike_dispatch.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final spikeNavigationProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 4: Wire the provider in `gemini_client.dart` dispatch**

In the for-loop step above, change the dispatch to actually set the provider. `GeminiChatResponder` is a pure Dart class with no Riverpod access, so pass an `onNavigate` callback:

Add to constructor:
```dart
final void Function(String route)? onNavigate; // spike only
```

In the tool loop:
```dart
if (call.name == 'navigate_to') {
  final route = call.args['route'] as String? ?? '/treatment';
  onNavigate?.call(route);
}
```

- [ ] **Step 5: Pass the callback from `ChatController`**

In `chat_controller.dart`, find where `chatResponderProvider` returns `GeminiChatResponder(...)`. Add:
```dart
onNavigate: (route) {
  ref.read(spikeNavigationProvider.notifier).state = route;
},
```

- [ ] **Step 6: Listen to the provider in AppShell**

In `flutter/lib/app/shell.dart`, make `_AppShellState` a `ConsumerState<AppShell>` (change the base class from `State` to `ConsumerState` and import riverpod). Then in `initState`:

```dart
@override
void initState() {
  super.initState();
  // Spike: will be replaced by pendingNavigationProvider in Task 5
  Future.microtask(() {
    ref.listenManual(spikeNavigationProvider, (_, route) {
      if (route != null && mounted) {
        context.go(route);
        ref.read(spikeNavigationProvider.notifier).state = null;
      }
    });
  });
}
```

Note: `_AppShellState` also needs `import 'package:flutter_riverpod/flutter_riverpod.dart'` and the `_spike_dispatch.dart` import.

- [ ] **Step 7: Run the app in test mode and verify manually**

```bash
cd flutter && flutter run
```

Open the chat, type: "go to blood tests". Confirm:
1. The debug console shows `[SPIKE] tool call: navigate_to args: {route: /blood-tests}`
2. The app navigates to the Blood Tests screen
3. No crash or error in the loop

Type: "just tell me the time" (no tool needed). Confirm:
1. No debug print — loop body never fires
2. Response text is yielded normally

- [ ] **Step 8: Verify race is not an issue (same-screen)**

Navigate manually to `/blood-tests`. Open chat, type "go to blood tests" again. Confirm navigation still works (dispatching to current screen).

- [ ] **Step 9: Commit spike findings, then clean up**

```bash
git add flutter/lib/features/chat/gemini_client.dart flutter/lib/features/chat/_spike_dispatch.dart flutter/lib/app/shell.dart flutter/lib/features/chat/chat_controller.dart
git commit -m "spike: verify Gemini function calling loop + StateProvider dispatch"
```

Do NOT delete the spike files yet — the real implementation in Tasks 2–9 replaces and supersedes them. Delete them in Task 9's final commit.

---

## Task 2: AppCommand sealed class + dispatch providers

**Files:**
- Create: `flutter/lib/features/chat/command_dispatch.dart`

- [ ] **Step 1: Create the file**

```dart
// flutter/lib/features/chat/command_dispatch.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class AppCommand {}

class NavigateTo extends AppCommand {
  NavigateTo(this.route);
  final String route;
}

class FilterBloodTests extends AppCommand {
  FilterBloodTests({this.marker, this.phase, this.months, this.tab});
  final String? marker;
  final String? phase;
  final int? months;
  final String? tab; // 'scorecard' | 'trend'
}

class FilterFitness extends AppCommand {
  FilterFitness({this.type, this.days});
  final String? type;
  final int? days;
}

class PrefillPreTreatment extends AppCommand {
  PrefillPreTreatment({this.weight, this.bpSys, this.bpDia, this.pulse, this.ufGoal, this.ufRate});
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? ufGoal, ufRate;
}

class PrefillReading extends AppCommand {
  PrefillReading({this.bpSys, this.bpDia, this.pulse, this.bloodFlow, this.vp, this.ap});
  final int? bpSys, bpDia, pulse, bloodFlow, vp, ap;
}

class PrefillPostTreatment extends AppCommand {
  PrefillPostTreatment({this.weight, this.bpSys, this.bpDia, this.pulse, this.totalUf});
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? totalUf;
}

// One provider per command type.
// null = no pending command. Screens read and immediately clear (consume) on react.
final pendingNavigationProvider    = StateProvider<String?>((ref) => null);
final btFilterCommandProvider      = StateProvider<FilterBloodTests?>((ref) => null);
final fitnessFilterCommandProvider = StateProvider<FilterFitness?>((ref) => null);
final prefillPreCommandProvider    = StateProvider<PrefillPreTreatment?>((ref) => null);
final prefillReadingCommandProvider = StateProvider<PrefillReading?>((ref) => null);
final prefillPostCommandProvider   = StateProvider<PrefillPostTreatment?>((ref) => null);

/// Dispatch an [AppCommand] to its StateProvider.
/// Called by [GeminiChatResponder] after [validateCommand] clears it.
/// Takes [Ref] (not [WidgetRef]) so it can be called from a Notifier's ref.
void dispatchCommand(AppCommand cmd, Ref ref) {
  switch (cmd) {
    case NavigateTo(:final route):
      ref.read(pendingNavigationProvider.notifier).state = route;
    case FilterBloodTests():
      ref.read(btFilterCommandProvider.notifier).state = cmd;
    case FilterFitness():
      ref.read(fitnessFilterCommandProvider.notifier).state = cmd;
    case PrefillPreTreatment():
      // Also navigate to /treatment — the form may not be visible yet.
      // spec: "Navigates to /treatment first if not already there."
      ref.read(pendingNavigationProvider.notifier).state = '/treatment';
      ref.read(prefillPreCommandProvider.notifier).state = cmd;
    case PrefillReading():
      ref.read(prefillReadingCommandProvider.notifier).state = cmd;
    case PrefillPostTreatment():
      ref.read(prefillPostCommandProvider.notifier).state = cmd;
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd flutter && flutter analyze lib/features/chat/command_dispatch.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/features/chat/command_dispatch.dart
git commit -m "feat: AppCommand sealed class + per-command StateProvider dispatch"
```

---

## Task 3: CommandValidator + unit tests

**Files:**
- Create: `flutter/lib/features/chat/command_validator.dart`
- Create: `flutter/test/features/chat/command_validator_test.dart`

- [ ] **Step 1: Write the failing tests first**

Create `flutter/test/features/chat/command_validator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/command_dispatch.dart';
import 'package:home_hd/features/chat/command_validator.dart';
import 'package:home_hd/features/chat/screen_context.dart';

void main() {
  group('validateCommand', () {
    test('NavigateTo is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(NavigateTo('/blood-tests'), state), isNull);
      }
    });

    test('FilterBloodTests is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(FilterBloodTests(marker: 'haemoglobin'), state), isNull);
      }
    });

    test('FilterFitness is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(FilterFitness(type: 'steps'), state), isNull);
      }
    });

    test('PrefillPreTreatment valid only when idle', () {
      expect(validateCommand(PrefillPreTreatment(weight: 72.4), TreatmentState.idle), isNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.active), isNotNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.preForm), isNotNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.postForm), isNotNull);
    });

    test('PrefillPreTreatment active gives session-in-progress message', () {
      final error = validateCommand(PrefillPreTreatment(), TreatmentState.active);
      expect(error, contains('already in progress'));
    });

    test('PrefillReading valid only when active', () {
      expect(validateCommand(PrefillReading(bpSys: 130), TreatmentState.active), isNull);
      expect(validateCommand(PrefillReading(), TreatmentState.idle), isNotNull);
      expect(validateCommand(PrefillReading(), TreatmentState.preForm), isNotNull);
      expect(validateCommand(PrefillReading(), TreatmentState.postForm), isNotNull);
    });

    test('PrefillReading idle gives no-session message', () {
      final error = validateCommand(PrefillReading(), TreatmentState.idle);
      expect(error, contains('Start a session first'));
    });

    test('PrefillPostTreatment valid only when postForm', () {
      expect(validateCommand(PrefillPostTreatment(weight: 70.0), TreatmentState.postForm), isNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.idle), isNotNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.active), isNotNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.preForm), isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run — confirm all fail (file does not exist yet)**

```bash
cd flutter && flutter test test/features/chat/command_validator_test.dart
```

Expected: compile error — `command_validator.dart` not found.

- [ ] **Step 3: Create `screen_context.dart` (needed by the test)**

Create `flutter/lib/features/chat/screen_context.dart`:

```dart
// flutter/lib/features/chat/screen_context.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../treatment/models.dart';

enum TreatmentState { idle, preForm, active, postForm }

class AppScreenContext {
  const AppScreenContext({
    this.currentRoute = '/treatment',
    this.treatmentState = TreatmentState.idle,
    this.activeSession,
    this.sessionReadings = const [],
    this.openForm,
  });

  final String currentRoute;
  final TreatmentState treatmentState;
  final Session? activeSession;
  final List<Reading> sessionReadings;
  final Map<String, dynamic>? openForm;

  AppScreenContext copyWith({
    String? currentRoute,
    TreatmentState? treatmentState,
    Session? activeSession,
    bool clearActiveSession = false,
    List<Reading>? sessionReadings,
    Map<String, dynamic>? openForm,
    bool clearOpenForm = false,
  }) =>
      AppScreenContext(
        currentRoute: currentRoute ?? this.currentRoute,
        treatmentState: treatmentState ?? this.treatmentState,
        activeSession: clearActiveSession ? null : activeSession ?? this.activeSession,
        sessionReadings: sessionReadings ?? this.sessionReadings,
        openForm: clearOpenForm ? null : openForm ?? this.openForm,
      );

  List<String> get validCommands => [
    'navigate_to',
    'filter_blood_tests',
    'filter_fitness',
    if (treatmentState == TreatmentState.idle) 'prefill_pre_treatment',
    if (treatmentState == TreatmentState.active) 'prefill_reading',
    if (treatmentState == TreatmentState.postForm) 'prefill_post_treatment',
  ];

  String toPromptSection() {
    final buf = StringBuffer();
    buf.writeln('--- CURRENT APP STATE ---');
    buf.writeln('Screen: $currentRoute');
    buf.writeln('Treatment state: ${treatmentState.name.toUpperCase()}');
    buf.writeln('Valid commands: ${validCommands.join(', ')}');

    final session = activeSession;
    if (session != null) {
      buf.writeln('Active session: ${session.sessionId}');
      if (session.preWeight != null) {
        buf.writeln('Pre: weight=${session.preWeight}kg, BP=${session.preBpSys}/${session.preBpDia}, pulse=${session.prePulse}, UF goal=${session.ufGoal}L');
      }
      if (sessionReadings.isNotEmpty) {
        buf.writeln('Readings recorded: ${sessionReadings.length}');
        for (final r in sessionReadings.take(5)) {
          buf.writeln('  ${r.time} — BP ${r.bpSys}/${r.bpDia}, pulse ${r.pulse}, BF ${r.bloodFlow}');
        }
      }
    }

    final form = openForm;
    if (form != null) {
      final screen = form['screen'] as String? ?? 'unknown';
      buf.writeln('Open form: $screen');
      form.forEach((key, value) {
        if (key == 'screen') return;
        final display = value == null ? '— (empty)' : '$value';
        buf.writeln('  $key: $display');
      });
    }

    buf.writeln('''
RULES:
- Only call tools listed in "Valid commands". If the user requests an invalid command, explain why and what they should do instead.
- For prefill commands: fill only the provided fields. Leave unspecified fields at their current values. Do not guess.
- After dispatching a command, describe what you did in plain language.
- If required fields are missing for a command, ask for them before calling the tool.''');

    return buf.toString().trim();
  }
}

class ScreenContextNotifier extends StateNotifier<AppScreenContext> {
  ScreenContextNotifier() : super(const AppScreenContext());

  void setRoute(String route) => state = state.copyWith(currentRoute: route);

  void setTreatmentState(TreatmentState ts, {
    Session? activeSession,
    bool clearSession = false,
    List<Reading>? readings,
  }) =>
      state = state.copyWith(
        treatmentState: ts,
        activeSession: activeSession,
        clearActiveSession: clearSession,
        sessionReadings: readings ?? (clearSession ? [] : state.sessionReadings),
      );

  void setOpenForm(Map<String, dynamic>? form) =>
      state = state.copyWith(openForm: form, clearOpenForm: form == null);

  void updateReadings(List<Reading> readings) =>
      state = state.copyWith(sessionReadings: readings);
}

final screenContextProvider =
    StateNotifierProvider<ScreenContextNotifier, AppScreenContext>(
  (_) => ScreenContextNotifier(),
);
```

- [ ] **Step 4: Create `command_validator.dart`**

```dart
// flutter/lib/features/chat/command_validator.dart
import 'command_dispatch.dart';
import 'screen_context.dart';

/// Returns null if [cmd] is valid in [state], or an error string if blocked.
/// Called by GeminiChatResponder before dispatching; error is sent back as
/// the FunctionResponse so Gemini narrates it to the user.
String? validateCommand(AppCommand cmd, TreatmentState state) => switch (cmd) {
  PrefillPreTreatment() when state != TreatmentState.idle =>
      state == TreatmentState.active
          ? 'A session is already in progress. Add a reading or end the session first.'
          : 'Cannot start a new session while the current form is open.',
  PrefillReading() when state != TreatmentState.active =>
      state == TreatmentState.idle
          ? 'There is no active session. Start a session first, then add readings.'
          : 'Cannot add a reading — the session is not yet active.',
  PrefillPostTreatment() when state != TreatmentState.postForm =>
      state == TreatmentState.idle
          ? 'There is no session to finish. Start one first.'
          : 'Cannot fill post-treatment details until the active session is ended.',
  _ => null,
};
```

- [ ] **Step 5: Run tests — confirm all pass**

```bash
cd flutter && flutter test test/features/chat/command_validator_test.dart
```

Expected: all 10 tests pass.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/chat/command_validator.dart flutter/lib/features/chat/screen_context.dart flutter/test/features/chat/command_validator_test.dart
git commit -m "feat: CommandValidator + AppScreenContext — state-machine enforcement in Dart"
```

---

## Task 4: AppShell — navigate on `pendingNavigationProvider`

**Files:**
- Modify: `flutter/lib/app/shell.dart`

The current `AppShell._AppShellState` extends `State<AppShell>`. Change it to `ConsumerState<AppShell>` to access Riverpod.

- [ ] **Step 1: Change the state base class and add navigation listener**

In `flutter/lib/app/shell.dart`, change:

```dart
// OLD
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.go_router.dart';

import 'providers.dart' show testModeProvider;
import '../features/chat/chat_sheet.dart';
```

Add the new import:
```dart
import '../features/chat/command_dispatch.dart' show pendingNavigationProvider;
```

Change `_AppShellState extends State<AppShell>` to:
```dart
class _AppShellState extends ConsumerState<AppShell> {
```

Add `initState`:
```dart
@override
void initState() {
  super.initState();
  // Listen for AI navigation commands dispatched by GeminiChatResponder.
  Future.microtask(() {
    if (!mounted) return;
    ref.listenManual(pendingNavigationProvider, (_, route) {
      if (route != null && mounted) {
        context.go(route);
        ref.read(pendingNavigationProvider.notifier).state = null;
      }
    });
  });
}
```

- [ ] **Step 2: Analyze**

```bash
cd flutter && flutter analyze lib/app/shell.dart
```

Expected: no new errors.

- [ ] **Step 3: Test manually — chat "go to inventory"**

```bash
flutter run
```

Open chat, type "go to inventory". Expected: app navigates to `/inventory`. Drawer highlight updates. Back-button behavior unchanged.

- [ ] **Step 4: Commit**

```bash
git add flutter/lib/app/shell.dart
git commit -m "feat: AppShell listens to pendingNavigationProvider for AI navigation"
```

---

## Task 5: TreatmentFlow — publish TreatmentState + react to prefillPre

**Files:**
- Modify: `flutter/lib/features/treatment/treatment_flow.dart`

`TreatmentFlow` owns the treatment state machine (`_Home`, `_Pre`, `_Active`, `_Post`). It needs to:
1. Publish `TreatmentState` to `screenContextProvider` whenever `_screen` changes.
2. React to `prefillPreCommandProvider` — if currently `_Home`, transition to `_Pre`.

- [ ] **Step 1: Add imports to `treatment_flow.dart`**

```dart
import '../../features/chat/command_dispatch.dart'
    show prefillPreCommandProvider, PrefillPreTreatment;
import '../../features/chat/screen_context.dart'
    show screenContextProvider, TreatmentState;
```

- [ ] **Step 2: Wire `prefillPre` listener and context publishing in `initState`**

In `_TreatmentFlowState.initState`, after `_bootstrap()`:

```dart
// Publish initial treatment state (idle until bootstrap completes).
Future.microtask(() {
  if (!mounted) return;
  _publishTreatmentState();
  // React to AI prefill-pre command — transition to Pre if currently on Home.
  ref.listenManual(prefillPreCommandProvider, (_, cmd) {
    if (cmd != null && _screen is _Home && mounted) {
      final ids = ref.read(treatmentStoreProvider).getCachedSessions()
          ?.map((s) => s.sessionId).toList() ?? [];
      _goPre(ids); // command stays in provider; PreTreatment drains it
    }
  });
});
```

- [ ] **Step 3: Add `_publishTreatmentState()` helper**

```dart
void _publishTreatmentState() {
  final notifier = ref.read(screenContextProvider.notifier);
  switch (_screen) {
    case _Home() || _Loading() || _ErrorScreen():
      notifier.setTreatmentState(TreatmentState.idle, clearSession: true);
    case _Pre():
      notifier.setTreatmentState(TreatmentState.preForm, clearSession: true);
    case final _Active s:
      notifier.setTreatmentState(
        TreatmentState.active,
        activeSession: s.session,
        readings: s.readings.map((p) => p.reading).toList(),
      );
    case final _Post s:
      notifier.setTreatmentState(TreatmentState.postForm, activeSession: s.session);
  }
}
```

- [ ] **Step 4: Call `_publishTreatmentState()` after every `setState` that changes `_screen`**

Find every `setState(() => _screen = ...)` call in `_TreatmentFlowState` and add `_publishTreatmentState()` after `setState`:

```dart
// Example — _goPre:
void _goPre(List<String> ids) {
  setState(() => _screen = _Pre(ids));
  _store.saveActiveState(...);
  _publishTreatmentState();  // ← add this
}

// Example — _goActive:
void _goActive(Session session, bool heparinUsed, bool epoUsed) {
  final s = _Active(session, [], heparinUsed, epoUsed);
  _lastActive = s;
  setState(() => _screen = s);
  _persistActive(s);
  _publishTreatmentState();  // ← add this
}

// Do the same for _goPost, setState(() => _screen = _Home()), etc.
```

- [ ] **Step 5: Analyze**

```bash
cd flutter && flutter analyze lib/features/treatment/treatment_flow.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/treatment/treatment_flow.dart
git commit -m "feat: TreatmentFlow publishes TreatmentState and reacts to AI prefill-pre command"
```

---

## Task 6: System prompt extension — `buildAppState`

**Files:**
- Modify: `flutter/lib/features/chat/chat_context.dart`

`ChatContextBuilder` needs to include the current app state section so Gemini knows where the user is and what commands are valid.

- [ ] **Step 1: Add `appState` parameter to `ChatContextBuilder`**

In `flutter/lib/features/chat/chat_context.dart`, add to the constructor:

```dart
class ChatContextBuilder {
  const ChatContextBuilder({
    required this.kbEntries,
    required this.lastSession,
    required this.lastReadings,
    required this.bloodTestRows,
    required this.fitnessSummary,
    required this.inventory,
    required this.appState,       // ← new
  });
  // ... existing fields ...
  final AppScreenContext appState; // ← new
```

Add the import at the top:
```dart
import 'screen_context.dart' show AppScreenContext;
```

- [ ] **Step 2: Append app state to `build()`**

In the `build()` method, add the app state section at the end (before `.trim()`):

```dart
String build() {
  return '''
You are a personal health assistant for a home hemodialysis patient.

--- PATIENT KNOWLEDGE (user-curated) ---
${_kbSection()}

--- CURRENT STATE (auto-assembled) ---
${_sessionLine()}
${_bloodsLine()}
${_fitnessLine()}
${_inventoryLine()}

--- INSTRUCTIONS ---
- Answer concisely. Use markdown for tables and lists.
- When the user tells you something worth remembering, end your response with: <!--KB_UPDATE {"title":"Entry Title","content":"Entry content"}-->
- For blood test values, include reference ranges when you know them.
- HRV values are relative to the patient's personal baseline — do not apply absolute population cutoffs.
- If asked about something not in the current state, say so — don't guess.
- Do not give medical advice. Summarise trends and flag patterns, but always defer to the clinical team.

${appState.toPromptSection()}
'''
      .trim();
}
```

- [ ] **Step 3: Fix compilation — update all callers of `ChatContextBuilder`**

Search for `ChatContextBuilder(` in the codebase:

```bash
cd flutter && grep -rn "ChatContextBuilder(" lib/
```

The only caller should be in `gemini_client.dart`. Pass `appState: screenContext` (the `screenContext` parameter added in Task 8 will supply this). For now, use a default:

```dart
// Temporary until Task 8 wires screenContext
final systemPrompt = ChatContextBuilder(
  kbEntries: kbEntries,
  lastSession: lastSession,
  lastReadings: lastReadings,
  bloodTestRows: btCache.rows,
  fitnessSummary: fitnessSummary,
  inventory: inventory,
  appState: const AppScreenContext(),  // ← temporary default
).build();
```

- [ ] **Step 4: Analyze**

```bash
cd flutter && flutter analyze lib/features/chat/
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/chat/chat_context.dart flutter/lib/features/chat/gemini_client.dart
git commit -m "feat: ChatContextBuilder includes current app state section in system prompt"
```

---

## Task 7: GeminiChatResponder — tool declarations + `generateContent` loop

**Files:**
- Modify: `flutter/lib/features/chat/gemini_client.dart`

Replace the chat-session approach with `model.generateContent()` loop and add all 6 tool declarations.

- [ ] **Step 1: Add imports**

```dart
import 'command_dispatch.dart';
import 'command_validator.dart';
import 'screen_context.dart';
```

- [ ] **Step 2: Add constructor parameters**

```dart
class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required this.apiKey,
    required this.auth,
    required this.kbStore,
    required this.treatmentRepo,
    required this.btStore,
    required this.cacheStore,
    required this.onCommand,      // ← new
    required this.screenContext,  // ← new
  });

  final void Function(AppCommand) onCommand;
  final AppScreenContext screenContext;
  // ... existing fields unchanged
```

- [ ] **Step 3: Define `_tools` as a static constant**

Add before the class, or as a static field:

```dart
static final _tools = [
  Tool(functionDeclarations: [
    FunctionDeclaration(
      'navigate_to',
      'Navigate to a main screen.',
      Schema.object(properties: {
        'route': Schema.string(description: 'One of: /treatment, /blood-tests, /inventory, /fitness, /kb'),
      }, requiredProperties: ['route']),
    ),
    FunctionDeclaration(
      'filter_blood_tests',
      'Navigate to blood tests and apply a filter. All parameters are optional.',
      Schema.object(properties: {
        'marker': Schema.string(description: 'Canonical marker name, e.g. haemoglobin, ferritin, potassium'),
        'phase': Schema.string(description: 'home-hd, in-center-hd, or admission'),
        'months': Schema.integer(description: 'Number of months back from today'),
        'tab': Schema.string(description: 'scorecard or trend'),
      }),
    ),
    FunctionDeclaration(
      'filter_fitness',
      'Navigate to fitness and filter by type and/or time window.',
      Schema.object(properties: {
        'type': Schema.string(description: 'steps, sleep, heart-rate, or hrv'),
        'days': Schema.integer(description: 'Number of days back from today'),
      }),
    ),
    FunctionDeclaration(
      'prefill_pre_treatment',
      'Pre-fill the pre-treatment form and open it. Only valid when no session is active.',
      Schema.object(properties: {
        'weight': Schema.number(description: 'Pre-treatment weight in kg'),
        'bp_sys': Schema.integer(description: 'Systolic BP'),
        'bp_dia': Schema.integer(description: 'Diastolic BP'),
        'pulse': Schema.integer(description: 'Pulse rate'),
        'uf_goal': Schema.number(description: 'UF goal in litres'),
        'uf_rate': Schema.number(description: 'UF rate in mL/h'),
      }),
    ),
    FunctionDeclaration(
      'prefill_reading',
      'Pre-fill the Add Reading form. Only valid when a session is active.',
      Schema.object(properties: {
        'bp_sys': Schema.integer(),
        'bp_dia': Schema.integer(),
        'pulse': Schema.integer(),
        'blood_flow': Schema.integer(description: 'Blood flow in mL/min'),
        'vp': Schema.integer(description: 'Venous pressure'),
        'ap': Schema.integer(description: 'Arterial pressure'),
      }),
    ),
    FunctionDeclaration(
      'prefill_post_treatment',
      'Pre-fill the post-treatment form. Only valid when the session has been ended.',
      Schema.object(properties: {
        'weight': Schema.number(description: 'Post-treatment weight in kg'),
        'bp_sys': Schema.integer(),
        'bp_dia': Schema.integer(),
        'pulse': Schema.integer(),
        'total_uf': Schema.number(description: 'Total UF removed in litres'),
      }),
    ),
  ]),
];
```

- [ ] **Step 4: Replace the `reply()` body with the `generateContent` loop**

Replace everything from `// 4. Call Gemini` to the end of the `try` block:

```dart
// 4. Build content list from history + new prompt
final contents = <Content>[
  ...sdkHistory,
  Content.text(prompt),
];

// 5. generateContent loop — runs until no function calls remain
final model = GenerativeModel(
  model: 'gemini-2.5-flash',
  apiKey: apiKey,
  tools: _tools,
  systemInstruction: Content.system(systemPrompt),
  generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 1024),
);

String finalText = '';
try {
  var response = await model.generateContent(contents);

  while (response.functionCalls.isNotEmpty) {
    final functionResponses = <Content>[];

    for (final call in response.functionCalls) {
      final cmd = _parseCommand(call);
      Map<String, dynamic> result;

      if (cmd == null) {
        result = {'error': 'Unknown tool: ${call.name}'};
      } else {
        final error = validateCommand(cmd, screenContext.treatmentState);
        if (error != null) {
          result = {'error': error};
        } else {
          onCommand(cmd);
          result = {'ok': true};
        }
      }

      functionResponses.add(
        Content.functionResponse(call.name, result),
      );
    }

    contents.add(response.candidates.first.content);
    contents.addAll(functionResponses);
    response = await model.generateContent(contents);
  }

  finalText = response.text ?? '';
} on GenerativeAIException catch (e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('api key') || msg.contains('permission') ||
      msg.contains('401') || msg.contains('403')) {
    throw ChatError.invalidKey;
  } else if (msg.contains('quota') || msg.contains('rate') || msg.contains('429')) {
    throw ChatError.rateLimited;
  } else {
    throw ChatError.serverError;
  }
} catch (_) {
  throw ChatError.network;
}

if (finalText.isEmpty) return;
yield finalText;
```

- [ ] **Step 5: Add `_parseCommand()` helper**

```dart
AppCommand? _parseCommand(FunctionCall call) {
  final a = call.args;
  return switch (call.name) {
    'navigate_to' => NavigateTo(a['route'] as String? ?? '/treatment'),
    'filter_blood_tests' => FilterBloodTests(
        marker: a['marker'] as String?,
        phase: a['phase'] as String?,
        months: (a['months'] as num?)?.toInt(),
        tab: a['tab'] as String?,
      ),
    'filter_fitness' => FilterFitness(
        type: a['type'] as String?,
        days: (a['days'] as num?)?.toInt(),
      ),
    'prefill_pre_treatment' => PrefillPreTreatment(
        weight: (a['weight'] as num?)?.toDouble(),
        bpSys: (a['bp_sys'] as num?)?.toInt(),
        bpDia: (a['bp_dia'] as num?)?.toInt(),
        pulse: (a['pulse'] as num?)?.toInt(),
        ufGoal: (a['uf_goal'] as num?)?.toDouble(),
        ufRate: (a['uf_rate'] as num?)?.toDouble(),
      ),
    'prefill_reading' => PrefillReading(
        bpSys: (a['bp_sys'] as num?)?.toInt(),
        bpDia: (a['bp_dia'] as num?)?.toInt(),
        pulse: (a['pulse'] as num?)?.toInt(),
        bloodFlow: (a['blood_flow'] as num?)?.toInt(),
        vp: (a['vp'] as num?)?.toInt(),
        ap: (a['ap'] as num?)?.toInt(),
      ),
    'prefill_post_treatment' => PrefillPostTreatment(
        weight: (a['weight'] as num?)?.toDouble(),
        bpSys: (a['bp_sys'] as num?)?.toInt(),
        bpDia: (a['bp_dia'] as num?)?.toInt(),
        pulse: (a['pulse'] as num?)?.toInt(),
        totalUf: (a['total_uf'] as num?)?.toDouble(),
      ),
    _ => null,
  };
}
```

Also update `ChatContextBuilder` call in `reply()` to pass real `screenContext`:
```dart
final systemPrompt = ChatContextBuilder(
  kbEntries: kbEntries,
  lastSession: lastSession,
  lastReadings: lastReadings,
  bloodTestRows: btCache.rows,
  fitnessSummary: fitnessSummary,
  inventory: inventory,
  appState: screenContext,  // ← real context now
).build();
```

- [ ] **Step 6: Analyze**

```bash
cd flutter && flutter analyze lib/features/chat/gemini_client.dart
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/chat/gemini_client.dart
git commit -m "feat: GeminiChatResponder — 6 tool declarations + generateContent loop + parseCommand"
```

---

## Task 8: ChatController wiring

**Files:**
- Modify: `flutter/lib/features/chat/chat_controller.dart`

`ChatController` needs to supply fresh `onCommand` and `screenContext` on each `send()` call.

- [ ] **Step 1: Add import**

```dart
import '../../app/providers.dart';
import 'command_dispatch.dart' show dispatchCommand;
import 'screen_context.dart' show screenContextProvider;
```

- [ ] **Step 2: Update `chatResponderProvider` to watch `aiSettingsControllerProvider`**

The `chatResponderProvider` currently returns `MockChatResponder` or `GeminiChatResponder`. Since `GeminiChatResponder` now requires `onCommand` and `screenContext` at construction time but `screenContext` must be fresh at send-time, build the responder **inside `send()`** not inside the provider.

Replace the `chatResponderProvider` with a simpler provider that returns just the API key state:

```dart
// Keep this but only for checking if AI is ready
final chatResponderProvider = Provider<ChatResponder>((ref) {
  final ai = ref.watch(aiSettingsControllerProvider);
  ref.watch(testModeProvider);
  if (!ai.ready) return MockChatResponder();
  // Return a sentinel — ChatController.send() builds the real responder per-call
  return _AiReadyMarker(ai.apiKey!);
});

class _AiReadyMarker implements ChatResponder {
  _AiReadyMarker(this.apiKey);
  final String apiKey;
  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    yield ''; // never called directly
  }
}
```

- [ ] **Step 3: Build GeminiChatResponder fresh in `send()`**

In `ChatController.send()`, after the `if (trimmed.isEmpty || state.sending) return;` check, add:

```dart
// Build responder with fresh context. screenContext is read at call-time so it
// reflects the current screen, not the screen when the provider was created.
final responder = switch (ref.read(chatResponderProvider)) {
  MockChatResponder() => ref.read(chatResponderProvider),
  _AiReadyMarker(:final apiKey) => GeminiChatResponder(
      apiKey: apiKey,
      auth: ref.read(treatmentAuthProvider),
      kbStore: ref.read(kbStoreProvider),
      treatmentRepo: ref.read(treatmentRepoProvider),
      btStore: ref.read(btStoreProvider),
      cacheStore: ref.read(cacheStoreProvider),
      screenContext: ref.read(screenContextProvider),
      onCommand: (cmd) => dispatchCommand(cmd, ref),
    ),
  _ => ref.read(chatResponderProvider),
};
```

Note: `dispatchCommand` takes `Ref` (not `WidgetRef`). `ChatController.ref` is `Ref`, so `onCommand: (cmd) => dispatchCommand(cmd, ref)` compiles directly. `dispatchCommand` handles navigation-for-prefill-pre automatically — no extra work needed here.

Then replace `ref.read(chatResponderProvider)` in the rest of `send()` with the local `responder` variable.

- [ ] **Step 4: Remove the spike files**

```bash
cd flutter && rm lib/features/chat/_spike_dispatch.dart
```

Remove references to `spikeNavigationProvider` from `chat_controller.dart` and `shell.dart` if any remain.

- [ ] **Step 5: Analyze**

```bash
cd flutter && flutter analyze lib/features/chat/
```

Expected: no errors.

- [ ] **Step 6: End-to-end test in test mode**

```bash
flutter run
```

Open chat (test mode is ON). Type: "go to blood tests". Expected: navigation fires. Type: "show my Hb for last 3 months". Expected: navigation to `/blood-tests` AND filter applies (next task).

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/chat/chat_controller.dart flutter/lib/features/chat/gemini_client.dart flutter/lib/app/shell.dart
git commit -m "feat: ChatController builds GeminiChatResponder with fresh onCommand + screenContext per send()"
```

---

## Task 9: BloodTestsScreen — react to `FilterBloodTests`

**Files:**
- Modify: `flutter/lib/features/blood_tests/blood_tests_screen.dart`

- [ ] **Step 1: Add import**

```dart
import '../../features/chat/command_dispatch.dart'
    show btFilterCommandProvider, FilterBloodTests;
```

- [ ] **Step 2: Drain the provider in `initState`**

In `_BloodTestsScreenState.initState`, after `_bootstrap()`:

```dart
ref.listenManual(btFilterCommandProvider, (_, cmd) {
  if (cmd == null || !mounted) return;
  _applyAiFilter(cmd);
  ref.read(btFilterCommandProvider.notifier).state = null; // consume
});
```

- [ ] **Step 3: Add `_applyAiFilter`**

```dart
void _applyAiFilter(FilterBloodTests cmd) {
  setState(() {
    var f = _filter;
    if (cmd.marker != null) f = f.copyWith(marker: cmd.marker);
    if (cmd.phase != null) f = f.copyWith(phases: [cmd.phase!]);
    if (cmd.months != null) {
      f = f.copyWith(rangePreset: switch (cmd.months!) {
        3 => '3m',
        6 => '6m',
        12 => '1y',
        _ => 'all',
      });
    }
    _filter = f;
  });
}
```

Also update `screenContextProvider` route in `initState`:

```dart
ref.read(screenContextProvider.notifier).setRoute('/blood-tests');
```

- [ ] **Step 4: Analyze + commit**

```bash
cd flutter && flutter analyze lib/features/blood_tests/blood_tests_screen.dart
git add flutter/lib/features/blood_tests/blood_tests_screen.dart
git commit -m "feat: BloodTestsScreen reacts to FilterBloodTests AI command"
```

---

## Task 10: FitnessScreen — react to `FilterFitness`

**Files:**
- Modify: `flutter/lib/features/fitness/fitness_screen.dart`

- [ ] **Step 1: Check what local state exists for filtering**

```bash
grep -n "_filter\|_type\|_days" flutter/lib/features/fitness/fitness_screen.dart | head -20
```

- [ ] **Step 2: Add import and drain provider**

```dart
import '../chat/command_dispatch.dart'
    show fitnessFilterCommandProvider, FilterFitness;
import '../chat/screen_context.dart' show screenContextProvider;
```

In `initState` of the fitness screen's state class:

```dart
ref.read(screenContextProvider.notifier).setRoute('/fitness');
ref.listenManual(fitnessFilterCommandProvider, (_, cmd) {
  if (cmd == null || !mounted) return;
  // Store the filter for display; the fitness screen currently shows a summary
  // so this is a visual/UX affordance — log the command for now and extend
  // once the fitness screen gains a type filter UI
  debugPrint('[AI] FilterFitness: type=${cmd.type} days=${cmd.days}');
  ref.read(fitnessFilterCommandProvider.notifier).state = null;
});
```

Note: if `FitnessScreen` has no type-filter UI yet, this task is a stub — the filter command is accepted and acknowledged but has no visual effect until the fitness screen gains filter controls. The system prompt includes the command as valid, which is correct.

- [ ] **Step 3: Analyze + commit**

```bash
cd flutter && flutter analyze lib/features/fitness/fitness_screen.dart
git add flutter/lib/features/fitness/fitness_screen.dart
git commit -m "feat: FitnessScreen drains FilterFitness AI command (stub, no filter UI yet)"
```

---

## Task 11: PreTreatment — drain `prefillPreCommandProvider` + AI-fill highlighting

**Files:**
- Modify: `flutter/lib/features/treatment/screens/pre.dart`

- [ ] **Step 1: Add imports**

```dart
import '../../../features/chat/command_dispatch.dart'
    show prefillPreCommandProvider, PrefillPreTreatment;
```

- [ ] **Step 2: Add `_aiFilledFields` to state**

```dart
final Set<String> _aiFilledFields = {};
```

- [ ] **Step 3: Drain `prefillPreCommandProvider` in `initState`**

`listenManual` fires `fireImmediately: false` by default — it misses any value already set before this widget mounts. **Always read the current value first**, then register for future changes:

```dart
// After existing initState body:

// 1. Apply any value already in the provider (set before this widget mounted)
final pending = ref.read(prefillPreCommandProvider);
if (pending != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _applyAiPrefill(pending);
    ref.read(prefillPreCommandProvider.notifier).state = null;
  });
}

// 2. Listen for future values
ref.listenManual(prefillPreCommandProvider, (_, cmd) {
  if (cmd == null || !mounted) return;
  _applyAiPrefill(cmd);
  ref.read(prefillPreCommandProvider.notifier).state = null; // consume
});
```

- [ ] **Step 4: Add `_applyAiPrefill`**

```dart
void _applyAiPrefill(PrefillPreTreatment cmd) {
  setState(() {
    if (cmd.weight != null) {
      _preWeight = cmd.weight;
      _aiFilledFields.add('weight');
    }
    if (cmd.bpSys != null) {
      _bpSys = cmd.bpSys;
      _aiFilledFields.add('bpSys');
    }
    if (cmd.bpDia != null) {
      _bpDia = cmd.bpDia;
      _aiFilledFields.add('bpDia');
    }
    if (cmd.pulse != null) {
      _pulse = cmd.pulse;
      _aiFilledFields.add('pulse');
    }
    if (cmd.ufGoal != null) {
      _ufGoal = cmd.ufGoal;
      _goalTouched = true;
      _aiFilledFields.add('ufGoal');
    }
    if (cmd.ufRate != null) {
      _ufRate = cmd.ufRate;
      _rateTouched = true;
      _aiFilledFields.add('ufRate');
    }
  });
}
```

- [ ] **Step 5: Clear `_aiFilledFields` when user edits a field**

For each `NumberField` that is AI-fillable, add an `onChanged` that clears the field from `_aiFilledFields`:

```dart
// Example for weight field — pattern repeats for bpSys, bpDia, pulse, ufGoal, ufRate
NumberField(
  label: 'Weight (kg)',
  value: _preWeight,
  onChanged: (v) {
    setState(() {
      _preWeight = v;
      _aiFilledFields.remove('weight'); // user edit clears AI highlight
    });
  },
  // Add highlight decoration when AI-filled:
  decoration: _aiFilledFields.contains('weight')
      ? InputDecoration(
          labelText: 'Weight (kg)',
          filled: true,
          fillColor: Colors.amber.withValues(alpha: 0.12),
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.amber.shade600, width: 1.5),
          ),
        )
      : null,
),
```

Check how `NumberField` exposes `decoration` — if it doesn't accept one, pass a `suffixIcon: Icon(Icons.auto_awesome, size: 14, color: Colors.amber)` when AI-filled instead:

```dart
NumberField(
  label: 'Weight (kg)',
  value: _preWeight,
  onChanged: (v) => setState(() { _preWeight = v; _aiFilledFields.remove('weight'); }),
  suffix: _aiFilledFields.contains('weight')
      ? const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFF59E0B))
      : null,
),
```

Adapt to whichever API `NumberField` exposes — check `flutter/lib/widgets/number_field.dart`.

- [ ] **Step 6: Analyze + commit**

```bash
cd flutter && flutter analyze lib/features/treatment/screens/pre.dart
git add flutter/lib/features/treatment/screens/pre.dart
git commit -m "feat: PreTreatment drains prefillPreCommandProvider with AI-fill highlighting"
```

---

## Task 12: ActiveSession + AddReadingSheet — react to `prefillReadingCommandProvider`

**Files:**
- Modify: `flutter/lib/features/treatment/screens/active.dart`
- Modify: `flutter/lib/features/treatment/widgets/add_reading_sheet.dart`

The approach: `ActiveSession` watches `prefillReadingCommandProvider`. When a command arrives, it opens the add-reading sheet and passes the prefill values as initial values. The sheet applies them and marks those fields as AI-filled.

- [ ] **Step 1: Add `initialValues` parameter to `_AddReadingSheet`**

In `flutter/lib/features/treatment/widgets/add_reading_sheet.dart`:

```dart
// Add to the showAddReadingSheet signature:
Future<void> showAddReadingSheet(
  BuildContext context, {
  required String sessionId,
  required int seq,
  int? defaultBloodFlow,
  required Future<void> Function(Reading) onSave,
  PrefillReading? prefill,        // ← new
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddReadingSheet(
      sessionId: sessionId,
      seq: seq,
      defaultBloodFlow: defaultBloodFlow,
      onSave: onSave,
      prefill: prefill,           // ← new
    ),
  );
}
```

Add the import:
```dart
import '../../../features/chat/command_dispatch.dart' show PrefillReading;
```

Add `prefill` to `_AddReadingSheet`:

```dart
class _AddReadingSheet extends StatefulWidget {
  const _AddReadingSheet({
    required this.sessionId,
    required this.seq,
    required this.defaultBloodFlow,
    required this.onSave,
    this.prefill,         // ← new
  });
  final PrefillReading? prefill;  // ← new
  // ... existing fields
```

- [ ] **Step 2: Apply prefill values in `_AddReadingSheetState.initState`**

```dart
final Set<String> _aiFilledFields = {};

@override
void initState() {
  super.initState();
  final p = widget.prefill;
  if (p != null) {
    if (p.bpSys != null) { _bpSys = p.bpSys; _aiFilledFields.add('bpSys'); }
    if (p.bpDia != null) { _bpDia = p.bpDia; _aiFilledFields.add('bpDia'); }
    if (p.pulse != null) { _pulse = p.pulse; _aiFilledFields.add('pulse'); }
    if (p.bloodFlow != null) { _bloodFlow = p.bloodFlow; _aiFilledFields.add('bloodFlow'); }
    if (p.vp != null) { _vp = p.vp; _aiFilledFields.add('vp'); }
    if (p.ap != null) { _ap = p.ap; _aiFilledFields.add('ap'); }
  }
}
```

Add the same AI-field highlight pattern to each `NumberField` in the sheet (same suffix-icon approach from Task 11, clearing from `_aiFilledFields` on user edit).

- [ ] **Step 3: Wire in `ActiveSession.initState`**

In `flutter/lib/features/treatment/screens/active.dart`:

```dart
import '../../../features/chat/command_dispatch.dart'
    show prefillReadingCommandProvider, PrefillReading;
```

In `_ActiveSessionState.initState` — read current value first, then listen for future ones:

```dart
void _drainPrefillReading(PrefillReading cmd) {
  final nextSeq = _readings.length + 1;
  final lastBF = _readings.isNotEmpty ? _readings.last.reading.bloodFlow : null;
  showAddReadingSheet(
    context,
    sessionId: widget.session.sessionId,
    seq: nextSeq,
    defaultBloodFlow: lastBF,
    onSave: _saveReading,
    prefill: cmd,
  );
  ref.read(prefillReadingCommandProvider.notifier).state = null;
}

// In initState:
final pendingReading = ref.read(prefillReadingCommandProvider);
if (pendingReading != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _drainPrefillReading(pendingReading);
  });
}
ref.listenManual(prefillReadingCommandProvider, (_, cmd) {
  if (cmd == null || !mounted) return;
  _drainPrefillReading(cmd);
});
```

- [ ] **Step 4: Analyze + commit**

```bash
cd flutter && flutter analyze lib/features/treatment/screens/active.dart lib/features/treatment/widgets/add_reading_sheet.dart
git add lib/features/treatment/screens/active.dart lib/features/treatment/widgets/add_reading_sheet.dart
git commit -m "feat: ActiveSession opens AddReadingSheet with AI prefill values"
```

---

## Task 13: PostTreatment — drain `prefillPostCommandProvider`

**Files:**
- Modify: `flutter/lib/features/treatment/screens/post.dart`

- [ ] **Step 1: Add import + `_aiFilledFields`**

```dart
import '../../../features/chat/command_dispatch.dart'
    show prefillPostCommandProvider, PrefillPostTreatment;

// In _PostTreatmentState:
final Set<String> _aiFilledFields = {};
```

- [ ] **Step 2: Drain in `initState`** — read current value first to avoid missing a pre-mount value

```dart
final pendingPost = ref.read(prefillPostCommandProvider);
if (pendingPost != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _applyAiPrefill(pendingPost);
    ref.read(prefillPostCommandProvider.notifier).state = null;
  });
}
ref.listenManual(prefillPostCommandProvider, (_, cmd) {
  if (cmd == null || !mounted) return;
  _applyAiPrefill(cmd);
  ref.read(prefillPostCommandProvider.notifier).state = null;
});
```

- [ ] **Step 3: Add `_applyAiPrefill`**

```dart
void _applyAiPrefill(PrefillPostTreatment cmd) {
  setState(() {
    if (cmd.weight != null)  { _postWeight = cmd.weight;  _aiFilledFields.add('weight'); }
    if (cmd.bpSys != null)   { _bpSys = cmd.bpSys;        _aiFilledFields.add('bpSys'); }
    if (cmd.bpDia != null)   { _bpDia = cmd.bpDia;        _aiFilledFields.add('bpDia'); }
    if (cmd.pulse != null)   { _pulse = cmd.pulse;         _aiFilledFields.add('pulse'); }
    if (cmd.totalUf != null) {
      _totalUf = cmd.totalUf;
      _totalUfTouched = true;
      _aiFilledFields.add('totalUf');
    }
  });
}
```

Apply the same AI-field highlight and clear-on-edit pattern to each relevant `NumberField`.

- [ ] **Step 4: Analyze + commit**

```bash
cd flutter && flutter analyze lib/features/treatment/screens/post.dart
git add flutter/lib/features/treatment/screens/post.dart
git commit -m "feat: PostTreatment drains prefillPostCommandProvider with AI-fill highlighting"
```

---

## Task 14: Final integration test + cleanup

**Files:**
- Delete: `flutter/lib/features/chat/_spike_dispatch.dart` (if not already removed)

- [ ] **Step 1: Run full analysis**

```bash
cd flutter && flutter analyze --no-pub 2>&1 | grep -E "^error"
```

Expected: no errors (warnings and infos are acceptable).

- [ ] **Step 2: Run all tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass including `command_validator_test.dart`.

- [ ] **Step 3: End-to-end manual test in test mode**

Run with `flutter run`. Test mode ON (amber banner). Use the chat FAB to test each command:

| Command | Expected behaviour |
|---|---|
| "go to inventory" | Navigates to `/inventory` |
| "show my Hb for the last 3 months" | Navigates to `/blood-tests`, marker=haemoglobin, range=3m |
| "show home-hd blood tests" | Blood tests filtered to home-hd phase |
| "start a session with weight 72.4 and BP 140/85" | Navigates to `/treatment`, transitions to Pre form, weight+BP pre-filled with amber highlight |
| "add a reading, BP 132/82, pulse 74" | Must be on active screen (if not active: AI explains). If active: opens add-reading sheet with fields pre-filled |
| "add reading" (no values) | AI asks for BP and pulse before calling the tool |
| "end session, post weight 70.1" | Must be on post screen. If pre-form: AI explains. If post: fills weight |

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: AI command control — 6 tools, state-machine enforcement, prefill highlighting"
```

---

## Notes

**`NumberField` widget:** Check `flutter/lib/widgets/number_field.dart` to see if it accepts a `suffix`, `decoration`, or neither. Adapt the AI-fill highlight accordingly — the important invariant is that the user can see which fields were filled by AI and that editing clears the highlight.

**Test mode:** All write commands (`prefill_*`) still update local Flutter form state only — no network calls happen until the user taps Submit. Test mode is therefore safe for all prefill commands. `navigate_to` and filter commands also make no network calls.

**TreatmentState and `_publishTreatmentState`:** The `TreatmentFlow` is a `ConsumerStatefulWidget`. When `_screen` changes via `setState`, `_publishTreatmentState()` must be called immediately after — not in `build()`, which may not fire synchronously. Search the file for all places `_screen` is set and add the call.
