// flutter/lib/features/kb/kb_store.dart  (STUB — replaced in Task 6)
class KbEntry {
  const KbEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final String content;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class KbStore {
  Future<List<KbEntry>> getAll() async => [];
}
