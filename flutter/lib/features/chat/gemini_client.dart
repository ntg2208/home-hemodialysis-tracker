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

enum ChatError { network, invalidKey, rateLimited, serverError }

class GeminiChatResponder implements ChatResponder {
  GeminiChatResponder({
    required this.apiKey,
    required this.auth,
    required this.kbStore,
    required this.treatmentRepo,
    required this.btStore,
    required this.cacheStore,
  });

  final String apiKey;
  final TreatmentAuth auth;
  final KbStore kbStore;
  final TreatmentRepo treatmentRepo;
  final BtStore btStore;
  final CacheStore cacheStore;

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
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(systemPrompt),
      generationConfig:
          GenerationConfig(temperature: 0.4, maxOutputTokens: 1024),
    );

    final sdkHistory = history
        .where((m) => !m.thinking && m.text.isNotEmpty)
        .map((m) => Content(
            m.role == ChatRole.user ? 'user' : 'model', [TextPart(m.text)]))
        .toList();

    final chat = model.startChat(history: sdkHistory);

    try {
      final stream = chat.sendMessageStream(Content.text(prompt));
      await for (final chunk in stream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) yield text;
      }
    } on GenerativeAIException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('api key') ||
          msg.contains('permission') ||
          msg.contains('401') ||
          msg.contains('403')) {
        throw ChatError.invalidKey;
      } else if (msg.contains('quota') ||
          msg.contains('rate') ||
          msg.contains('429')) {
        throw ChatError.rateLimited;
      } else {
        throw ChatError.serverError;
      }
    } catch (_) {
      throw ChatError.network;
    }
  }
}
