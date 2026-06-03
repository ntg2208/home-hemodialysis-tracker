import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/treatment/treatment_auth.dart';
import '../../firebase/firebase_init.dart';
import 'chat_controller.dart';

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatConversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  }) =>
      ChatConversation(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'messages': messages
            .where((m) => !m.thinking)
            .map((m) => {
                  'role': m.role == ChatRole.user ? 'user' : 'assistant',
                  'text': m.text,
                })
            .toList(),
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
      };

  factory ChatConversation.fromMap(Map<String, dynamic> m) {
    final rawMsgs = m['messages'] as List? ?? [];
    return ChatConversation(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      messages: rawMsgs.map((e) {
        final map = e as Map;
        final role =
            map['role'] == 'user' ? ChatRole.user : ChatRole.assistant;
        return ChatMessage(role, map['text'] as String? ?? '');
      }).toList(),
      createdAt: (m['created_at'] as Timestamp).toDate(),
      updatedAt: (m['updated_at'] as Timestamp).toDate(),
    );
  }
}

class ConversationStore {
  ConversationStore(this._auth);
  final TreatmentAuth _auth;

  CollectionReference<Map<String, dynamic>> get _col =>
      firestore.collection('chat_conversations');

  Future<List<ChatConversation>> getRecent({int limit = 50}) async {
    await _auth.ensure();
    final snap = await _col
        .orderBy('updated_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => ChatConversation.fromMap(d.data())).toList();
  }

  Future<void> save(ChatConversation conv) async {
    await _auth.ensure();
    await _col.doc(conv.id).set(conv.toMap());
  }

  Future<void> delete(String id) async {
    await _auth.ensure();
    await _col.doc(id).delete();
  }

  Future<void> deleteAll() async {
    await _auth.ensure();
    final snap = await _col.get();
    final batch = firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
