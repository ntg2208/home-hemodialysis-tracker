// flutter/lib/features/chat/gemini_client.dart
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
import 'retriever_tools.dart';
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
      FunctionDeclaration(
        'get_blood_markers',
        'Fetch historical blood test rows for specific markers. Use when asked about symptoms, trends, or comparisons across months.',
        Schema.object(properties: {
          'markers': Schema.array(
            items: Schema.string(description: 'Canonical marker name, e.g. phosphate, potassium, haemoglobin'),
            description: 'List of marker names to fetch',
          ),
          'months_back': Schema.integer(description: 'How many months back to look. Default 2, max 12.'),
        }, requiredProperties: ['markers']),
      ),
      FunctionDeclaration(
        'get_sessions',
        'Fetch dialysis session records. Use for BP trends, UF patterns, weight trends, or multi-session comparisons.',
        Schema.object(properties: {
          'last_n': Schema.integer(description: 'Last N sessions. Default 7, max 30. Mutually exclusive with from/to.'),
          'from': Schema.string(description: 'Start date YYYY-MM-DD (inclusive). Use with to.'),
          'to': Schema.string(description: 'End date YYYY-MM-DD (inclusive). Use with from.'),
          'include_readings': Schema.boolean(description: 'Include intra-session BP readings. Default false. Only use for last_n ≤ 5.'),
        }),
      ),
      FunctionDeclaration(
        'get_out_of_range_markers',
        'Returns all markers from the most recent blood draw that are outside their reference range. Use for general health checks or "is anything flagged?" questions.',
        Schema.object(properties: {}),
      ),
    ]),
  ];

  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    late final RetrieverTools retriever;
    final GeminiBackend backend;

    if (_testBackend != null) {
      // Test path — skip data fetch and model construction entirely.
      retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: []);
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

      retriever = RetrieverTools(
        sessions: [...treatmentData.sessions],
        readings: treatmentData.readings,
        bloodTestRows: btCache.rows,
      );
      backend = _RealBackend(GenerativeModel(
        model: 'gemma-4-26b-a4b-it',
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
      // Buffer ALL text rather than yielding immediately. Thinking models
      // (e.g. Gemma 4) stream internal reasoning as plain text chunks before
      // emitting a function call — yielding those would show the model's
      // internal monologue to the user. We yield only after confirming the
      // stream is pure-chat (no function calls). Breaking early risks premature
      // HTTP cancellation, so we always drain the stream to completion.
      GenerateContentResponse? firstResponse;
      final streamedChunks = <String>[];
      var hasToolCalls = false;

      await for (final chunk in backend.stream(contents)) {
        if (chunk.functionCalls.isNotEmpty) {
          hasToolCalls = true;
          firstResponse = chunk;
          // No break — drain to completion.
        } else {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) {
            streamedChunks.add(text);
          }
        }
      }

      if (!hasToolCalls) {
        // Pure-chat path: yield the complete buffered response.
        final fullText = streamedChunks.join();
        if (fullText.isNotEmpty) yield fullText;
        return;
      }

      // --- Tool-call path: buffered loop ---
      var response = firstResponse!;
      const maxToolTurns = 5;

      for (var turn = 0;
          turn < maxToolTurns && response.functionCalls.isNotEmpty;
          turn++) {
        final functionResponses = <Content>[];
        for (final call in response.functionCalls) {
          Map<String, dynamic> result;

          // Retrieval tools: return data, no AppCommand enqueued.
          if (call.name == 'get_blood_markers') {
            final markers =
                ((call.args['markers'] as List?) ?? []).cast<String>();
            final months = (call.args['months_back'] as num?)?.toInt() ?? 2;
            result = retriever.getBloodMarkers(markers, months);
          } else if (call.name == 'get_sessions') {
            result = retriever.getSessions(
              lastN: (call.args['last_n'] as num?)?.toInt(),
              from: call.args['from'] as String?,
              to: call.args['to'] as String?,
              includeReadings:
                  call.args['include_readings'] as bool? ?? false,
            );
          } else if (call.name == 'get_out_of_range_markers') {
            result = retriever.getOutOfRangeMarkers();
          } else {
            // Action tools: validate state, enqueue command.
            final cmd = _parseCommand(call);
            if (cmd == null) {
              result = {'error': 'Unknown tool: ${call.name}'};
            } else {
              final stateError =
                  validateCommand(cmd, _screenContext.treatmentState);
              final valueError =
                  stateError == null ? validateValues(cmd) : null;
              final error = stateError ?? valueError;
              if (error != null) {
                result = {'error': error};
              } else {
                commandsToRun.add(cmd);
                result = _commandResult(cmd);
              }
            }
          }

          // JSON round-trip ensures nested lists/maps and null values are
          // typed as plain JSON-compatible objects, which the SDK can safely
          // serialize into the function response part.
          final sanitized =
              (jsonDecode(jsonEncode(result)) as Map).cast<String, Object?>();
          functionResponses.add(Content.functionResponse(call.name, sanitized));
        }

        final candidate = response.candidates.firstOrNull;
        if (candidate == null) break;
        if (turn == 0) {
          // Streaming chunks are deltas — their role may be unset and parts
          // are incomplete. Rebuild the model turn explicitly from accumulated
          // text (if any) + the fully-parsed function calls.
          contents.add(Content('model', [
            if (streamedChunks.isNotEmpty) TextPart(streamedChunks.join()),
            ...response.functionCalls,
          ]));
        } else {
          // Non-streaming generate() returns complete content; safe to use.
          contents.add(candidate.content);
        }
        contents.addAll(functionResponses);
        response = await backend.generate(contents);
      }

      // Yield narration so the user can read it, then execute commands.
      // Thinking models return multiple TextParts: earlier parts are internal
      // reasoning, the last part is the user-facing answer. Taking the last
      // TextPart strips thinking tokens from the narration.
      final textParts = response.candidates
              .firstOrNull
              ?.content
              .parts
              .whereType<TextPart>()
              .toList() ??
          const [];
      final finalText =
          textParts.isNotEmpty ? textParts.last.text : (response.text ?? '');
      final narration = finalText.isNotEmpty
          ? finalText
          : commandsToRun.isNotEmpty
              ? _fallbackNarration(commandsToRun)
              : '';
      if (narration.isNotEmpty) yield narration;

      if (commandsToRun.isNotEmpty) {
        // Hold the sheet open long enough to read the narration before closing.
        // ~250 ms per word, min 2 s, max 5 s.
        final words = narration.isEmpty
            ? 0
            : narration.trim().split(RegExp(r'\s+')).length;
        final readMs = (words * 250).clamp(2000, 5000);
        await Future.delayed(Duration(milliseconds: readMs));
        for (final cmd in commandsToRun) {
          _onCommand(cmd);
        }
      }
    } on GenerativeAIException catch (e) {
      debugPrint('[GeminiClient] GenerativeAIException: ${e.message}');
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

  /// Returns a rich result map sent back to Gemini as the function response.
  /// Gives the model enough context to narrate what happened naturally.
  static Map<String, dynamic> _commandResult(AppCommand cmd) => switch (cmd) {
    NavigateTo(:final route) => {
      'success': true,
      'navigated_to': _routeName(route),
      'route': route,
    },
    FilterBloodTests(:final marker, :final phase, :final months, :final tab) => {
      'success': true,
      'screen': 'Blood Tests',
      'marker': ?marker,
      'phase': ?phase,
      'months_back': ?months,
      'tab': ?tab,
    },
    FilterFitness(:final type, :final days) => {
      'success': true,
      'screen': 'Fitness',
      'type': ?type,
      'days_back': ?days,
    },
    PrefillPreTreatment() => {
      'success': true,
      'form': 'pre-treatment',
      'form_opened': true,
    },
    PrefillReading() => {
      'success': true,
      'form': 'add-reading',
      'form_opened': true,
    },
    PrefillPostTreatment() => {
      'success': true,
      'form': 'post-treatment',
      'form_opened': true,
    },
    EndSession() => {
      'success': true,
      'session_ended': true,
      'post_treatment_form_opened': true,
    },
  };

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

  static String _fallbackNarration(List<AppCommand> _) => 'Done.';

  static String _routeName(String route) => switch (route) {
    '/treatment'   => 'Treatment',
    '/blood-tests' => 'Blood Tests',
    '/inventory'   => 'Inventory',
    '/fitness'     => 'Fitness',
    '/kb'          => 'Knowledge Base',
    _              => route,
  };
}
