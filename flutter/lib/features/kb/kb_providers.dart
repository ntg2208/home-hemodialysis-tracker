// flutter/lib/features/kb/kb_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart' show testModeProvider;
import '../../flavor.dart';
import '../../test_mode/synthetic_repos.dart';
import '../chat/chat_conversation.dart';
import '../chat/hive_conversation_store.dart';
import '../treatment/providers.dart';
import 'hive_kb_store.dart';
import 'kb_store.dart';

final kbStoreProvider = Provider<KbRepository>((ref) {
  if (kCommunity) return HiveKbStore();
  if (ref.watch(testModeProvider)) return SyntheticKbStore();
  return KbStore(ref.read(treatmentAuthProvider));
});

final conversationStoreProvider = Provider<ConversationRepository>((ref) {
  if (kCommunity) return HiveConversationStore();
  return ConversationStore(ref.read(treatmentAuthProvider));
});
