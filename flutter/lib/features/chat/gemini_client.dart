// flutter/lib/features/chat/gemini_client.dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/blood_tests/bt_store.dart';
import '../../features/inventory/inventory_models.dart';
import '../../features/treatment/models.dart';
import '../../features/treatment/treatment_auth.dart';
import '../../features/treatment/treatment_repo.dart';
import '../../storage/cache_store.dart';
import '../kb/kb_store.dart' show KbRepository;
import 'chat_context.dart';
import 'chat_controller.dart';
import 'command_dispatch.dart';
import 'command_validator.dart';
import 'screen_context.dart';

enum ChatError { network, invalidKey, rateLimited, serverError }

/// Thin abstraction over [GenerativeModel] to allow injection in tests.
/// [GenerativeModel] is `final` and cannot be subclassed.
abstract interface class GeminiBackend {
  Stream<GenerateContentResponse> stream(Iterable<Content> contents);
  Future<GenerateContentResponse> generate(Iterable<Content> contents);
}

class _RealBackend implements GeminiBackend {
  _RealBackend(this._model);
  final GenerativeModel _model;

  @override
  Stream<GenerateContentResponse> stream(Iterable<Content> contents) =>
      _model.generateContentStream(contents);

  @override
  Future<GenerateContentResponse> generate(Iterable<Content> contents) =>
      _model.generateContent(contents);
}

class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required String apiKey,
    required TreatmentAuth auth,
    required KbRepository kbStore,
    required TreatmentRepo treatmentRepo,
    required BtStore btStore,
    required CacheStore cacheStore,
    required void Function(AppCommand) onCommand,
    required AppScreenContext screenContext,
  })  : _apiKey = apiKey,
        _auth = auth,
        _kbStore = kbStore,
        _treatmentRepo = treatmentRepo,
        _btStore = btStore,
        _cacheStore = cacheStore,
        _onCommand = onCommand,
        _screenContext = screenContext,
        _testBackend = null;

  /// Test-only constructor. Skips all data fetching; injects the model backend.
  @visibleForTesting
  GeminiChatResponder.forTest({
    required void Function(AppCommand) onCommand,
    required AppScreenContext screenContext,
    required GeminiBackend testBackend,
  })  : _apiKey = '',
        _auth = null,
        _kbStore = null,
        _treatmentRepo = null,
        _btStore = null,
        _cacheStore = null,
        _onCommand = onCommand,
        _screenContext = screenContext,
        _testBackend = testBackend;

  final String _apiKey;
  final TreatmentAuth? _auth;
  final KbRepository? _kbStore;
  final TreatmentRepo? _treatmentRepo;
  final BtStore? _btStore;
  final CacheStore? _cacheStore;
  final void Function(AppCommand) _onCommand;
  final AppScreenContext _screenContext;
  final GeminiBackend? _testBackend;

  static List<Tool> get _tools => [
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
      FunctionDeclaration(
        'end_session',
        'End the active dialysis session and open the post-treatment form. '
        'Optionally pre-fill post-treatment fields in the same call. '
        'Only valid when a session is active (treatment state = ACTIVE).',
        Schema.object(properties: {
          'weight': Schema.number(description: 'Post-treatment weight in kg'),
          'bp_sys': Schema.integer(description: 'Post-treatment systolic BP'),
          'bp_dia': Schema.integer(description: 'Post-treatment diastolic BP'),
          'pulse': Schema.integer(description: 'Post-treatment pulse rate'),
          'total_uf': Schema.number(description: 'Total UF removed in litres'),
        }),
      ),
    ]),
  ];

  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    final GeminiBackend backend;

    if (_testBackend != null) {
      // Test path — skip data fetch and model construction entirely.
      backend = _testBackend;
    } else {
      // Production path — fetch data and build system prompt.
      // The production constructor guarantees all of these are non-null.
      final auth = _auth!;
      final kbStore = _kbStore!;
      final treatmentRepo = _treatmentRepo!;
      final btStore = _btStore!;
      final cacheStore = _cacheStore!;

      await auth.ensure();

      final kbEntries = await kbStore.getAll();
      final treatmentData = await treatmentRepo.getAll();
      final btCache = btStore.readCache();
      final fitnessSummary = cacheStore.readStale('fitness_summary');
      final inventoryRaw = cacheStore.readStale('inventory');
      InventoryResponse? inventory;
      if (inventoryRaw != null) {
        try {
          inventory = InventoryResponse.fromJson(inventoryRaw);
        } catch (_) {}
      }

      final sessions = [...treatmentData.sessions]
        ..sort((a, b) => b.date.compareTo(a.date));
      final lastSession = sessions.isEmpty ? null : sessions.first;
      final lastReadings = lastSession == null
          ? <Reading>[]
          : treatmentData.readings
              .where((r) => r.sessionId == lastSession.sessionId)
              .toList();

      final systemPrompt = ChatContextBuilder(
        kbEntries: kbEntries,
        lastSession: lastSession,
        lastReadings: lastReadings,
        bloodTestRows: btCache.rows,
        fitnessSummary: fitnessSummary,
        inventory: inventory,
        appState: _screenContext,
      ).build();

      backend = _RealBackend(GenerativeModel(
        model: 'gemini-3.1-flash-lite',
        apiKey: _apiKey,
        tools: _tools,
        systemInstruction: Content.system(systemPrompt),
        generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 2048),
      ));
    }

    final sdkHistory = history
        .where((m) => !m.thinking && m.text.isNotEmpty)
        .map((m) => Content(
            m.role == ChatRole.user ? 'user' : 'model', [TextPart(m.text)]))
        .toList();

    final contents = [...sdkHistory, Content.text(prompt)];

    // Declared before the try so catch blocks can access them.
    // Commands are collected here but executed AFTER narration is yielded,
    // so the user sees the AI's response before the app acts on it.
    final commandsToRun = <AppCommand>[];

    try {
      // --- First turn: streaming ---
      // Yield text chunks as they arrive. When a function call chunk is
      // detected, stop yielding text but continue draining the stream fully.
      // Breaking early causes premature HTTP cancellation (which can itself
      // throw), and any text the model generates before the function call
      // would be absent from the history sent to the next generate() call,
      // producing an incomplete turn that the API rejects intermittently.
      GenerateContentResponse? firstResponse;
      final streamedChunks = <String>[];
      var hasToolCalls = false;

      await for (final chunk in backend.stream(contents)) {
        if (chunk.functionCalls.isNotEmpty) {
          hasToolCalls = true;
          firstResponse = chunk;
          // No break — drain to completion.
        } else if (!hasToolCalls) {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) {
            streamedChunks.add(text);
            yield text; // stream incrementally
          }
        }
      }

      if (!hasToolCalls) return; // pure-chat path: already yielded all chunks

      // --- Tool-call path: buffered loop ---
      var response = firstResponse!;
      const maxToolTurns = 5;

      for (var turn = 0;
          turn < maxToolTurns && response.functionCalls.isNotEmpty;
          turn++) {
        final functionResponses = <Content>[];
        for (final call in response.functionCalls) {
          final cmd = _parseCommand(call);
          Map<String, dynamic> result;

          if (cmd == null) {
            result = {'error': 'Unknown tool: ${call.name}'};
          } else {
            final stateError = validateCommand(cmd, _screenContext.treatmentState);
            final valueError = stateError == null ? validateValues(cmd) : null;
            final error = stateError ?? valueError;
            if (error != null) {
              result = {'error': error};
            } else {
              commandsToRun.add(cmd); // deferred — run after narration is shown
              result = {'ok': true};
            }
          }

          functionResponses.add(Content.functionResponse(call.name, result));
        }

        final candidate = response.candidates.firstOrNull;
        if (candidate == null) break;
        // For the first tool turn, prepend any text that was streamed before
        // the function call so the history reflects the model's full output.
        if (turn == 0 && streamedChunks.isNotEmpty) {
          contents.add(Content('model', [
            TextPart(streamedChunks.join()),
            ...candidate.content.parts,
          ]));
        } else {
          contents.add(candidate.content);
        }
        contents.addAll(functionResponses);
        response = await backend.generate(contents);
      }

      // Show narration FIRST so the user sees the AI's response before the app
      // acts on it, then execute deferred commands after a brief pause.
      final finalText = response.text ?? '';
      if (finalText.isNotEmpty) {
        yield finalText;
      } else if (commandsToRun.isNotEmpty) {
        yield _fallbackNarration(commandsToRun);
      }
      if (commandsToRun.isNotEmpty) {
        // Let the user read the response, then close the sheet, then navigate.
        await Future.delayed(const Duration(milliseconds: 400));
        for (final cmd in commandsToRun) {
          _onCommand(cmd);
        }
      }
    } on GenerativeAIException catch (e) {
      // Narration API failed but commands were validated — still execute them
      // and confirm, rather than showing an error for a succeeded action.
      if (commandsToRun.isNotEmpty) {
        for (final cmd in commandsToRun) {
          _onCommand(cmd);
        }
        yield _fallbackNarration(commandsToRun);
        return;
      }
      final msg = e.message.toLowerCase();
      if (msg.contains('api key') || msg.contains('401') || msg.contains('403')) {
        throw ChatError.invalidKey;
      } else if (msg.contains('quota') || msg.contains('429')) {
        throw ChatError.rateLimited;
      } else {
        throw ChatError.serverError;
      }
    } catch (_) {
      if (commandsToRun.isNotEmpty) {
        for (final cmd in commandsToRun) {
          _onCommand(cmd);
        }
        yield _fallbackNarration(commandsToRun);
        return;
      }
      throw ChatError.network;
    }
  }

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
      'end_session' => EndSession(
          weight: (a['weight'] as num?)?.toDouble(),
          bpSys: (a['bp_sys'] as num?)?.toInt(),
          bpDia: (a['bp_dia'] as num?)?.toInt(),
          pulse: (a['pulse'] as num?)?.toInt(),
          totalUf: (a['total_uf'] as num?)?.toDouble(),
        ),
      _ => null,
    };
  }

  static String _fallbackNarration(List<AppCommand> commands) {
    for (final cmd in commands) {
      return switch (cmd) {
        NavigateTo(:final route) => 'Here — ${_routeName(route)}.',
        FilterBloodTests()      => 'Filter applied.',
        FilterFitness()         => 'Filter applied.',
        PrefillPreTreatment()   => 'Pre-treatment form filled in.',
        PrefillReading()        => 'Add Reading sheet filled in.',
        PrefillPostTreatment()  => 'Post-treatment form filled in.',
        EndSession()            => 'Session ended — post-treatment form is open.',
      };
    }
    return 'Done.';
  }

  static String _routeName(String route) => switch (route) {
    '/treatment'   => 'Treatment',
    '/blood-tests' => 'Blood Tests',
    '/inventory'   => 'Inventory',
    '/fitness'     => 'Fitness',
    '/kb'          => 'Knowledge Base',
    _              => route,
  };
}
