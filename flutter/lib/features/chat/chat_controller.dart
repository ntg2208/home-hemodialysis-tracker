import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/cache_store.dart';
import '../blood_tests/bt_store.dart';
import '../blood_tests/providers.dart';
import '../kb/kb_providers.dart';
import '../treatment/providers.dart';
import 'gemini_client.dart';
import 'command_dispatch.dart' show dispatchCommand;
import 'screen_context.dart' show screenContextProvider;
import 'chat_conversation.dart';

/// Chat state + a mock responder. The backend `/api/chat` does not exist yet
/// (api/src/handlers/chat.ts is a placeholder), so replies come from
/// [MockChatResponder] behind the [ChatResponder] interface — swap the provider
/// override for a real REST-backed responder when the endpoint lands.

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage(this.role, this.text,
      {this.thinking = false, this.kbUpdate});
  final ChatRole role;
  final String text;
  final bool thinking; // assistant typing indicator placeholder
  final KbUpdateProposal? kbUpdate;
}

enum ChatMode { active, history, viewing }

class KbUpdateProposal {
  const KbUpdateProposal({required this.title, required this.content});
  final String title;
  final String content;
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.sending = false,
    this.mode = ChatMode.active,
    this.conversations = const [],
    this.viewingConversation,
    this.currentConversationId,
  });

  final List<ChatMessage> messages;
  final bool sending;
  final ChatMode mode;
  final List<ChatConversation> conversations;
  final ChatConversation? viewingConversation;
  final String? currentConversationId;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    ChatMode? mode,
    List<ChatConversation>? conversations,
    ChatConversation? viewingConversation,
    String? currentConversationId,
    bool clearViewingConversation = false,
    bool clearCurrentConversationId = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        mode: mode ?? this.mode,
        conversations: conversations ?? this.conversations,
        viewingConversation: clearViewingConversation
            ? null
            : viewingConversation ?? this.viewingConversation,
        currentConversationId: clearCurrentConversationId
            ? null
            : currentConversationId ?? this.currentConversationId,
      );
}

abstract class ChatResponder {
  Stream<String> reply(String prompt, List<ChatMessage> history);
}

/// Canned, domain-flavoured markdown replies until the RAG endpoint exists.
class MockChatResponder implements ChatResponder {
  @override
  Stream<String> reply(String prompt, List<ChatMessage> history) async* {
    await Future.delayed(const Duration(milliseconds: 700));
    final p = prompt.toLowerCase();
    if (p.contains('blood pressure') || p.contains('bp')) {
      yield 'Your pre-dialysis systolic has trended **down** over the last '
          '2 weeks:\n\n| Week | Avg pre-sys |\n|---|---|\n| This | 132 |\n'
          '| Last | 138 |\n\n_(mock reply — AI backend not connected yet.)_';
    } else if (p.contains('delivery') || p.contains('order')) {
      yield 'Your next **call date** is in a few days, with delivery ~7 days '
          'after.\n\n_(mock reply — AI backend not connected yet.)_';
    } else if (p.contains('hrv') || p.contains('heart')) {
      yield 'Recent **HRV (daily)** is stable around your baseline.\n\n'
          '_(mock reply — AI backend not connected yet.)_';
    } else {
      yield 'I can summarise your BP, blood tests, fitness and inventory '
          'once the AI assistant is enabled in Settings.\n\n'
          '_(mock reply — enable AI in Settings to connect.)_';
    }
  }
}

final chatResponderProvider = Provider<ChatResponder>((ref) {
  final ai = ref.watch(aiSettingsControllerProvider);
  ref.watch(testModeProvider); // rebuild when test mode toggles
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

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;

    final baseMessages = [
      ...state.messages,
      ChatMessage(ChatRole.user, trimmed),
      const ChatMessage(ChatRole.assistant, '', thinking: true),
    ];
    final assistantIdx = baseMessages.length - 1;

    state = state.copyWith(messages: baseMessages, sending: true);

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

    try {
      var accumulated = '';
      final stream = responder.reply(trimmed, baseMessages);
      await for (final chunk in stream) {
        accumulated += chunk;
        final updated = [...state.messages];
        if (assistantIdx < updated.length) {
          updated[assistantIdx] = ChatMessage(ChatRole.assistant, accumulated);
          state = state.copyWith(messages: updated);
        }
      }
      // Parse KB update proposal from completed response
      final proposal = parseKbUpdate(accumulated);
      if (proposal != null) {
        accumulated = stripKbUpdate(accumulated);
        final updated = [...state.messages];
        if (assistantIdx < updated.length) {
          updated[assistantIdx] =
              ChatMessage(ChatRole.assistant, accumulated, kbUpdate: proposal);
          state = state.copyWith(messages: updated);
        }
      }
      // Auto-save after each assistant reply
      unawaited(_saveCurrentIfNonEmpty());
      if (accumulated.isEmpty) {
        final updated = [...state.messages];
        if (assistantIdx < updated.length) {
          updated[assistantIdx] =
              const ChatMessage(ChatRole.assistant, 'No response received.');
          state = state.copyWith(messages: updated);
        }
      }
    } catch (e) {
      final updated = [...state.messages];
      if (assistantIdx < updated.length) {
        final msg = switch (e) {
          ChatError.invalidKey =>
            'API key rejected — check your key in Settings.',
          ChatError.rateLimited =>
            'Too many requests — try again in a moment.',
          ChatError.serverError =>
            'AI service error — try again.',
          _ => 'Could not reach the AI service — check your connection.',
        };
        updated[assistantIdx] = ChatMessage(ChatRole.assistant, msg);
        state = state.copyWith(messages: updated);
      }
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  void _replaceThinking(ChatMessage msg) {
    final msgs = [...state.messages];
    final i = msgs.indexWhere((m) => m.thinking);
    if (i >= 0) {
      msgs[i] = msg;
    } else {
      msgs.add(msg);
    }
    state = state.copyWith(messages: msgs, sending: false);
  }

  // ── History ──────────────────────────────────────────────

  Future<void> openHistory() async {
    await _saveCurrentIfNonEmpty();
    final store = ref.read(conversationStoreProvider);
    try {
      final convs = await store.getRecent();
      state = state.copyWith(mode: ChatMode.history, conversations: convs);
    } catch (_) {
      state = state.copyWith(mode: ChatMode.history, conversations: []);
    }
  }

  void viewConversation(ChatConversation conv) {
    state = state.copyWith(mode: ChatMode.viewing, viewingConversation: conv);
  }

  void backToHistory() {
    state = state.copyWith(
        mode: ChatMode.history, clearViewingConversation: true);
  }

  Future<void> newChat() async {
    await _saveCurrentIfNonEmpty();
    state = const ChatState();
  }

  Future<void> onClose() => _saveCurrentIfNonEmpty();

  Future<void> deleteAllHistory() async {
    await ref.read(conversationStoreProvider).deleteAll();
    state = state.copyWith(conversations: []);
  }

  // ── Auto-save ─────────────────────────────────────────────

  Future<void> _saveCurrentIfNonEmpty() async {
    final msgs = state.messages.where((m) => !m.thinking).toList();
    if (msgs.isEmpty) return;
    final now = DateTime.now();
    final title = msgs.first.role == ChatRole.user
        ? (msgs.first.text.length > 60
            ? '${msgs.first.text.substring(0, 60)}…'
            : msgs.first.text)
        : 'Conversation';
    final id = state.currentConversationId ?? _newConvId();
    final conv = ChatConversation(
      id: id,
      title: title,
      messages: msgs,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await ref.read(conversationStoreProvider).save(conv);
      state = state.copyWith(currentConversationId: id);
    } catch (_) {/* non-fatal — conversation save failures are silent */}
  }

  String _newConvId() =>
      'conv_${DateTime.now().millisecondsSinceEpoch}';
}

/// Parses a <!--KB_UPDATE {"title":"...","content":"..."}--> comment from the
/// end of a model response. Returns null if not present or malformed.
KbUpdateProposal? parseKbUpdate(String text) {
  final pattern =
      RegExp(r'<!--KB_UPDATE\s+(\{.*?\})\s*-->', dotAll: true);
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  try {
    final map = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final title = map['title'] as String?;
    final content = map['content'] as String?;
    if (title == null || content == null) return null;
    return KbUpdateProposal(title: title, content: content);
  } catch (_) {
    return null;
  }
}

/// Strips the <!--KB_UPDATE --> comment from visible text.
String stripKbUpdate(String text) => text
    .replaceAll(
        RegExp(r'\n?<!--KB_UPDATE\s+\{.*?\}\s*-->', dotAll: true), '')
    .trim();
