// flutter/lib/features/chat/gemini_client.dart
import 'package:flutter/foundation.dart';
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

enum ChatError { network, invalidKey, rateLimited, serverError }

class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required this.apiKey,
    required this.auth,
    required this.kbStore,
    required this.treatmentRepo,
    required this.btStore,
    required this.cacheStore,
    this.onNavigate,
  });

  final String apiKey;
  final TreatmentAuth auth;
  final KbStore kbStore;
  final TreatmentRepo treatmentRepo;
  final BtStore btStore;
  final CacheStore cacheStore;
  final void Function(String route)? onNavigate; // spike only

  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    // 1. Ensure Firebase auth (fast path <100ms if already authed)
    await auth.ensure();

    // 2. Fetch data (TreatmentRepo is typed via the provider)
    final kbEntries = await kbStore.getAll();

    final treatmentData = await treatmentRepo.getAll()
        as ({List<Session> sessions, List<Reading> readings});

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
    ).build();

    // 4. Call Gemini
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
      model: 'gemini-3.1-flash-lite',
      apiKey: apiKey,
      tools: tools,
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
          debugPrint('[SPIKE] tool call: ${call.name} args: ${call.args}');
          if (call.name == 'navigate_to') {
            final route = call.args['route'] as String? ?? '/treatment';
            onNavigate?.call(route);
          }
          functionResponses.add(
            Content.functionResponse(call.name, {'ok': true, 'dispatched': call.name}),
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
}
