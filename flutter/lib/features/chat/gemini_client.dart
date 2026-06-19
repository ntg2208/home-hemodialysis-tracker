// flutter/lib/features/chat/gemini_client.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/blood_tests/blood_tests_api.dart';
import '../../features/blood_tests/bt_store.dart';
import '../../features/blood_tests/logic.dart' show sixMonthsAgo;
import '../../features/inventory/inventory_models.dart';
import '../../features/treatment/models.dart';
import '../../features/treatment/treatment_auth.dart';
import '../../features/treatment/treatment_repo.dart';
import '../../storage/cache_store.dart';
import '../kb/kb_store.dart' show KbRepository;
import 'app_tools.dart';
import 'chat_context.dart';
import 'chat_controller.dart';
import 'command_dispatch.dart';
import 'command_validator.dart';
import 'retriever_tools.dart';
import 'screen_context.dart';

enum ChatError { network, invalidKey, rateLimited, serverError }

// ── SDK backend abstraction (test-only) ──────────────────────────────────────

/// Thin abstraction over [GenerativeModel] for test injection.
/// Production uses [_replyViaOpenAI] directly.
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

// ── Main responder ────────────────────────────────────────────────────────────

class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required String apiKey,
    required TreatmentAuth auth,
    required KbRepository kbStore,
    required TreatmentRepo treatmentRepo,
    required BtStore btStore,
    required BloodTestsApi bloodTestsApi,
    required CacheStore cacheStore,
    required void Function(AppCommand) onCommand,
    required AppScreenContext screenContext,
  })  : _apiKey = apiKey,
        _auth = auth,
        _kbStore = kbStore,
        _treatmentRepo = treatmentRepo,
        _btStore = btStore,
        _bloodTestsApi = bloodTestsApi,
        _cacheStore = cacheStore,
        _onCommand = onCommand,
        _screenContext = screenContext,
        _testBackend = null;

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
        _bloodTestsApi = null,
        _cacheStore = null,
        _onCommand = onCommand,
        _screenContext = screenContext,
        _testBackend = testBackend;

  final String _apiKey;
  final TreatmentAuth? _auth;
  final KbRepository? _kbStore;
  final TreatmentRepo? _treatmentRepo;
  final BtStore? _btStore;
  final BloodTestsApi? _bloodTestsApi;
  final CacheStore? _cacheStore;
  final void Function(AppCommand) _onCommand;
  final AppScreenContext _screenContext;
  final GeminiBackend? _testBackend;

  // Google's OpenAI-compatible endpoint — same API key, full JSON control,
  // no thought_signature issues since tool calls use tool_call_id instead.
  static const _oaiBase =
      'https://generativelanguage.googleapis.com/v1beta/openai';
  static const _model = 'gemma-4-26b-a4b-it';

  // 3 retriever tools — data-fetching, not commands. Kept here verbatim.
  static const _retrieverTools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_blood_markers',
        'description':
            'Fetch historical blood test rows for specific markers. '
            'Use when asked about symptoms, trends, or comparisons across months.',
        'parameters': {
          'type': 'object',
          'properties': {
            'markers': {
              'type': 'array',
              'items': {
                'type': 'string',
                'description':
                    'Canonical marker name, e.g. phosphate, potassium, haemoglobin',
              },
              'description': 'List of marker names to fetch',
            },
            'months_back': {
              'type': 'integer',
              'description': 'How many months back to look. Default 2, max 12.',
            },
          },
          'required': ['markers'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_sessions',
        'description':
            'Fetch dialysis session records. Use for BP trends, UF patterns, '
            'weight trends, or multi-session comparisons.',
        'parameters': {
          'type': 'object',
          'properties': {
            'last_n': {
              'type': 'integer',
              'description':
                  'Last N sessions. Default 7, max 30. Mutually exclusive with from/to.',
            },
            'from': {
              'type': 'string',
              'description': 'Start date YYYY-MM-DD (inclusive). Use with to.',
            },
            'to': {
              'type': 'string',
              'description': 'End date YYYY-MM-DD (inclusive). Use with from.',
            },
            'include_readings': {
              'type': 'boolean',
              'description':
                  'Include intra-session BP readings. Default false. Only use for last_n ≤ 5.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_out_of_range_markers',
        'description':
            'Returns all markers from the most recent blood draw that are outside '
            'their reference range. Use for general health checks or "is anything flagged?" questions.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];

  // 7 command tools (from app_tools.dart) + 3 retriever tools = 10 total.
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

  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    if (_testBackend != null) {
      yield* _replyViaSdkBackend(_testBackend!, prompt, history);
      return;
    }

    final auth = _auth!;
    final kbStore = _kbStore!;
    final treatmentRepo = _treatmentRepo!;
    final btStore = _btStore!;
    final cacheStore = _cacheStore!;

    await auth.ensure();

    final kbEntries = await kbStore.getAll();
    final treatmentData = await treatmentRepo.getAll();

    var btCache = btStore.readCache();
    const _twelveHours = 12 * 60 * 60 * 1000;
    final cacheAge = btCache.lastSynced == null
        ? _twelveHours + 1
        : DateTime.now().millisecondsSinceEpoch - btCache.lastSynced!;
    if (cacheAge > _twelveHours && _bloodTestsApi != null) {
      try {
        final defaultFrom = sixMonthsAgo(DateTime.now());
        final rows = await _bloodTestsApi.fetchRange(from: defaultFrom);
        final now = DateTime.now().millisecondsSinceEpoch;
        await btStore.writeCache(rows, defaultFrom, now);
        btCache = btStore.readCache();
      } catch (_) {}
    }

    final fitnessSummary = cacheStore.readStale('fitness_summary');
    final inventoryRaw = cacheStore.readStale('inventory');
    InventoryResponse? inventory;
    if (inventoryRaw != null) {
      try { inventory = InventoryResponse.fromJson(inventoryRaw); } catch (_) {}
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

    final retriever = RetrieverTools(
      sessions: [...treatmentData.sessions],
      readings: treatmentData.readings,
      bloodTestRows: btCache.rows,
    );

    yield* _replyViaOpenAI(systemPrompt, retriever, prompt, history);
  }

  // ── OpenAI-compatible path (production) ──────────────────────────────────────

  Stream<String> _replyViaOpenAI(
    String systemPrompt,
    RetrieverTools retriever,
    String prompt,
    List<ChatMessage> history,
  ) async* {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history
          .where((m) => !m.thinking && m.text.isNotEmpty)
          .map((m) => {
                'role': m.role == ChatRole.user ? 'user' : 'assistant',
                'content': m.text,
              }),
      {'role': 'user', 'content': prompt},
    ];

    final dio = Dio()
      ..options.connectTimeout = const Duration(seconds: 60)
      ..options.receiveTimeout = const Duration(seconds: 60)
      ..options.responseType = ResponseType.json
      ..options.validateStatus = (_) => true;

    final commandsToRun = <AppCommand>[];

    try {
      const maxTurns = 5;
      for (var turn = 0; turn < maxTurns; turn++) {
        Response res;
        try {
          res = await dio.post(
            '$_oaiBase/chat/completions',
            data: {
              'model': _model,
              'messages': messages,
              'tools': _oaiTools,
              'tool_choice': 'auto',
              'temperature': 0.4,
              'max_tokens': 8192,
            },
            options: Options(
              headers: {'Authorization': 'Bearer $_apiKey'},
            ),
          );
        } on DioException {
          throw ChatError.network;
        }

        final status = res.statusCode ?? 0;
        if (status == 401 || status == 403) throw ChatError.invalidKey;
        if (status == 429) throw ChatError.rateLimited;
        if (status < 200 || status >= 300) throw ChatError.serverError;

        final data = res.data as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          if (commandsToRun.isNotEmpty) yield _fallbackNarration(commandsToRun);
          break;
        }

        final message =
            (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>;
        final toolCalls = message['tool_calls'] as List?;

        if (toolCalls == null || toolCalls.isEmpty) {
          final rawContent = message['content'] as String? ?? '';
          final content = _stripThought(rawContent);
          final narration = content.isNotEmpty
              ? content
              : commandsToRun.isNotEmpty
                  ? _fallbackNarration(commandsToRun)
                  : '';
          if (narration.isNotEmpty) yield narration;
          if (commandsToRun.isNotEmpty) {
            final words = content.trim().split(RegExp(r'\s+')).length;
            final readMs = (words * 250).clamp(2000, 5000);
            await Future.delayed(Duration(milliseconds: readMs));
            for (final cmd in commandsToRun) _onCommand(cmd);
          }
          return;
        }

        // Add assistant's tool-call turn to conversation history.
        messages.add(Map<String, dynamic>.from(message));

        for (final rawCall in toolCalls.cast<Map<String, dynamic>>()) {
          final callId = rawCall['id'] as String;
          final fn = rawCall['function'] as Map<String, dynamic>;
          final name = fn['name'] as String;
          final args =
              jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;

          final result = _dispatchTool(name, args, retriever, commandsToRun);
          messages.add({
            'role': 'tool',
            'tool_call_id': callId,
            'content': jsonEncode(result),
          });
        }
      }
    } on ChatError {
      rethrow;
    } catch (_) {
      if (commandsToRun.isNotEmpty) {
        for (final cmd in commandsToRun) _onCommand(cmd);
        yield _fallbackNarration(commandsToRun);
        return;
      }
      throw ChatError.network;
    }
  }

  // ── SDK path (test-only) ─────────────────────────────────────────────────────

  Stream<String> _replyViaSdkBackend(
    GeminiBackend backend,
    String prompt,
    List<ChatMessage> history,
  ) async* {
    final retriever =
        RetrieverTools(sessions: [], readings: [], bloodTestRows: []);
    final sdkHistory = history
        .where((m) => !m.thinking && m.text.isNotEmpty)
        .map((m) => Content(
            m.role == ChatRole.user ? 'user' : 'model', [TextPart(m.text)]))
        .toList();
    final contents = [...sdkHistory, Content.text(prompt)];
    final commandsToRun = <AppCommand>[];

    try {
      GenerateContentResponse? firstResponse;
      var hasToolCalls = false;

      await for (final chunk in backend.stream(contents)) {
        if (chunk.functionCalls.isNotEmpty) {
          hasToolCalls = true;
          firstResponse = chunk;
        } else {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) yield text;
        }
      }

      if (!hasToolCalls) return;

      var response = firstResponse!;
      const maxToolTurns = 5;

      for (var turn = 0;
          turn < maxToolTurns && response.functionCalls.isNotEmpty;
          turn++) {
        final functionResponses = <Content>[];
        for (final call in response.functionCalls) {
          final result =
              _dispatchTool(call.name, call.args, retriever, commandsToRun);
          final sanitized =
              (jsonDecode(jsonEncode(result)) as Map).cast<String, Object?>();
          functionResponses
              .add(Content.functionResponse(call.name, sanitized));
        }

        final candidate = response.candidates.firstOrNull;
        if (candidate == null) break;
        if (turn == 0) {
          contents.add(Content('model', [...response.functionCalls]));
        } else {
          contents.add(candidate.content);
        }
        contents.addAll(functionResponses);
        response = await backend.generate(contents);
      }

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
        final words = narration.isEmpty
            ? 0
            : narration.trim().split(RegExp(r'\s+')).length;
        final readMs = (words * 250).clamp(2000, 5000);
        await Future.delayed(Duration(milliseconds: readMs));
        for (final cmd in commandsToRun) _onCommand(cmd);
      }
    } on GenerativeAIException catch (e) {
      if (commandsToRun.isNotEmpty) {
        for (final cmd in commandsToRun) _onCommand(cmd);
        yield _fallbackNarration(commandsToRun);
        return;
      }
      final msg = e.message.toLowerCase();
      if (msg.contains('api key') || msg.contains('401') ||
          msg.contains('403')) {
        throw ChatError.invalidKey;
      } else if (msg.contains('quota') || msg.contains('429')) {
        throw ChatError.rateLimited;
      } else {
        throw ChatError.serverError;
      }
    } catch (_) {
      if (commandsToRun.isNotEmpty) {
        for (final cmd in commandsToRun) _onCommand(cmd);
        yield _fallbackNarration(commandsToRun);
        return;
      }
      throw ChatError.network;
    }
  }

  // ── Shared tool dispatch ──────────────────────────────────────────────────────

  Map<String, dynamic> _dispatchTool(
    String name,
    Map<String, Object?> args,
    RetrieverTools retriever,
    List<AppCommand> commandsToRun,
  ) {
    if (name == 'get_blood_markers') {
      final markers = ((args['markers'] as List?) ?? []).cast<String>();
      final months = (args['months_back'] as num?)?.toInt() ?? 2;
      return retriever.getBloodMarkers(markers, months);
    } else if (name == 'get_sessions') {
      return retriever.getSessions(
        lastN: (args['last_n'] as num?)?.toInt(),
        from: args['from'] as String?,
        to: args['to'] as String?,
        includeReadings: args['include_readings'] as bool? ?? false,
      );
    } else if (name == 'get_out_of_range_markers') {
      return retriever.getOutOfRangeMarkers();
    } else {
      final cmd = _parseCommand(name, args);
      if (cmd == null) return {'error': 'Unknown tool: $name'};
      final stateError = validateCommand(cmd, _screenContext.treatmentState);
      final valueError = stateError == null ? validateValues(cmd) : null;
      final error = stateError ?? valueError;
      if (error != null) return {'error': error};
      commandsToRun.add(cmd);
      return _commandResult(cmd);
    }
  }

  AppCommand? _parseCommand(String name, Map<String, Object?> a) =>
      parseAppCommand(name, a);

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

  /// Strips leading <thought>...</thought> from Gemma 4 content.
  /// The model always emits its chain-of-thought before the visible answer.
  static String _stripThought(String content) {
    final end = content.indexOf('</thought>');
    if (end == -1) return content; // no thought block — return as-is
    return content.substring(end + '</thought>'.length).trimLeft();
  }

  static String _fallbackNarration(List<AppCommand> _) => 'Done.';

  static String _routeName(String route) => switch (route) {
        '/treatment' => 'Treatment',
        '/blood-tests' => 'Blood Tests',
        '/inventory' => 'Inventory',
        '/fitness' => 'Fitness',
        '/kb' => 'Knowledge Base',
        _ => route,
      };
}
