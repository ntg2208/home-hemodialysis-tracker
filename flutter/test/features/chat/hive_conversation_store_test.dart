import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/chat_conversation.dart';
import 'package:home_hd/features/chat/chat_controller.dart';

void main() {
  test('ChatConversation toJson/fromJson roundtrip', () {
    final conv = ChatConversation(
      id: 'conv-1',
      title: 'Test',
      messages: [ChatMessage(ChatRole.user, 'hello')],
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );
    final json = conv.toJson();
    expect(json['created_at'], isA<String>());
    final restored = ChatConversation.fromJson(json);
    expect(restored.id, conv.id);
    expect(restored.messages.first.text, 'hello');
  });
}
