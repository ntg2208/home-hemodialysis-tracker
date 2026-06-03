// flutter/lib/features/chat/chat_context.dart  (STUB — replaced in Task 9)
import '../kb/kb_store.dart';

class ChatContextBuilder {
  const ChatContextBuilder({
    required this.kbEntries,
    required this.lastSession,
    required this.lastReadings,
    required this.bloodTestRows,
    required this.fitnessSummary,
    required this.inventory,
  });
  final List<KbEntry> kbEntries;
  final dynamic lastSession;
  final List<dynamic> lastReadings;
  final List<dynamic> bloodTestRows;
  final Map<String, dynamic>? fitnessSummary;
  final dynamic inventory;

  String build() => 'You are a home HD assistant. (context loading…)';
}
