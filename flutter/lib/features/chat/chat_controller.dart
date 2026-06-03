import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/cache_store.dart';
import '../blood_tests/bt_store.dart';
import '../blood_tests/providers.dart';
import '../kb/kb_providers.dart';
import '../treatment/providers.dart';
import 'gemini_client.dart';
// import 'chat_conversation.dart'; // needed in Task 12

/// Chat state + a mock responder. The backend `/api/chat` does not exist yet
/// (api/src/handlers/chat.ts is a placeholder), so replies come from
/// [MockChatResponder] behind the [ChatResponder] interface — swap the provider
/// override for a real REST-backed responder when the endpoint lands.

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage(this.role, this.text, {this.thinking = false});
  final ChatRole role;
  final String text;
  final bool thinking; // assistant typing indicator placeholder
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false});
  final List<ChatMessage> messages;
  final bool sending;

  ChatState copyWith({List<ChatMessage>? messages, bool? sending}) =>
      ChatState(messages: messages ?? this.messages, sending: sending ?? this.sending);
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
  if (!ai.ready) return MockChatResponder();
  return GeminiChatResponder(
    apiKey: ai.apiKey!,
    auth: ref.read(treatmentAuthProvider),
    kbStore: ref.read(kbStoreProvider),
    treatmentRepo: ref.read(treatmentRepoProvider),
    btStore: ref.read(btStoreProvider),
    cacheStore: ref.read(cacheStoreProvider),
  );
});

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

    try {
      var accumulated = '';
      final stream = ref.read(chatResponderProvider).reply(trimmed, baseMessages);
      await for (final chunk in stream) {
        accumulated += chunk;
        final updated = [...state.messages];
        if (assistantIdx < updated.length) {
          updated[assistantIdx] = ChatMessage(ChatRole.assistant, accumulated);
          state = state.copyWith(messages: updated);
        }
      }
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

  void newChat() => state = const ChatState();
}
