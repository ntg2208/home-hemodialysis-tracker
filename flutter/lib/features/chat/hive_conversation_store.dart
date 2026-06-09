import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'chat_conversation.dart';

class HiveConversationStore implements ConversationRepository {
  Box get _box => Hive.box(communityChatBox);

  @override
  Future<List<ChatConversation>> getRecent({int limit = 50}) async {
    final all = _box.values
        .map((v) =>
            ChatConversation.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all.take(limit).toList();
  }

  @override
  Future<void> save(ChatConversation conv) async =>
      _box.put(conv.id, conv.toJson());

  @override
  Future<void> delete(String id) async => _box.delete(id);

  @override
  Future<void> deleteAll() async => _box.clear();
}
