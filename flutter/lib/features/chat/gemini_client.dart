// flutter/lib/features/chat/gemini_client.dart
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/blood_tests/bt_store.dart';
import '../../features/inventory/inventory_models.dart';
import '../../features/treatment/models.dart';
import '../../features/treatment/treatment_auth.dart';
import '../../features/treatment/treatment_repo.dart';
import '../../storage/cache_store.dart';
import '../kb/kb_store.dart';
import 'chat_context.dart';
import 'chat_controller.dart';
import 'command_dispatch.dart';
import 'command_validator.dart';
import 'screen_context.dart';

enum ChatError { network, invalidKey, rateLimited, serverError }

class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required this.apiKey,
    required this.auth,
    required this.kbStore,
    required this.treatmentRepo,
    required this.btStore,
    required this.cacheStore,
    required this.onCommand,
    required this.screenContext,
  });

  final String apiKey;
  final TreatmentAuth auth;
  final KbStore kbStore;
  final TreatmentRepo treatmentRepo;
  final BtStore btStore;
  final CacheStore cacheStore;
  final void Function(AppCommand) onCommand;
  final AppScreenContext screenContext;

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
    ]),
  ];

  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    // 1. Ensure Firebase auth (fast path <100ms if already authed)
    await auth.ensure();

    // 2. Fetch data (TreatmentRepo is typed via the provider)
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
      appState: screenContext,
    ).build();

    // 4. Call Gemini
    final model = GenerativeModel(
      model: 'gemini-3.1-flash-lite',
      apiKey: apiKey,
      tools: _tools,
      systemInstruction: Content.system(systemPrompt),
      generationConfig:
          GenerationConfig(temperature: 0.4, maxOutputTokens: 1024),
    );

    final sdkHistory = history
        .where((m) => !m.thinking && m.text.isNotEmpty)
        .map((m) => Content(
            m.role == ChatRole.user ? 'user' : 'model', [TextPart(m.text)]))
        .toList();

    // Build content list from existing history + new message
    final contents = [
      ...sdkHistory,
      Content.text(prompt),
    ];

    const maxToolTurns = 5;
    String finalText = '';
    try {
      var response = await model.generateContent(contents);

      // Tool call loop — runs until model returns text with no function calls
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
        // Append model response + function responses to content list
        final candidate = response.candidates.firstOrNull;
        if (candidate == null) break;
        contents.add(candidate.content);
        contents.addAll(functionResponses);
        response = await model.generateContent(contents);
      }

      finalText = response.text ?? '';
    } on GenerativeAIException catch (e) {
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

    if (finalText.isEmpty) return;
    yield finalText;
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
      _ => null,
    };
  }
}
