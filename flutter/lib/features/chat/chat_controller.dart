import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Future<String> reply(String prompt, List<ChatMessage> history);
}

/// Canned, domain-flavoured markdown replies until the RAG endpoint exists.
class MockChatResponder implements ChatResponder {
  @override
  Future<String> reply(String prompt, List<ChatMessage> history) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final p = prompt.toLowerCase();
    if (p.contains('blood pressure') || p.contains('bp')) {
      return 'Your pre-dialysis systolic has trended **down** over the last '
          '2 weeks:\n\n| Week | Avg pre-sys |\n|---|---|\n| This | 132 |\n'
          '| Last | 138 |\n\n_(mock reply — the assistant backend isn’t wired yet.)_';
    }
    if (p.contains('delivery') || p.contains('order')) {
      return 'Your next **call date** is in a few days, with delivery ~7 days '
          'after.\n\n_(mock reply — chat backend pending.)_';
    }
    if (p.contains('hrv') || p.contains('heart')) {
      return 'Recent **HRV (daily)** is stable around your baseline.\n\n'
          '_(mock reply — chat backend pending.)_';
    }
    return 'I can summarise your BP, blood tests, fitness and inventory once the '
        'assistant backend is connected.\n\n_(mock reply — `/api/chat` is a '
        'placeholder for now.)_';
  }
}

final chatResponderProvider =
    Provider<ChatResponder>((_) => MockChatResponder());

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(ChatRole.user, trimmed),
        const ChatMessage(ChatRole.assistant, '', thinking: true),
      ],
      sending: true,
    );
    try {
      final reply = await ref
          .read(chatResponderProvider)
          .reply(trimmed, state.messages);
      _replaceThinking(ChatMessage(ChatRole.assistant, reply));
    } catch (_) {
      _replaceThinking(const ChatMessage(
          ChatRole.assistant, 'Sorry — could not get a response.'));
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
