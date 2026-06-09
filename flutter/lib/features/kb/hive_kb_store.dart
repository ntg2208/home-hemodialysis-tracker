import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'kb_store.dart';

class HiveKbStore implements KbRepository {
  Box get _box => Hive.box(communityKbBox);

  @override
  Future<List<KbEntry>> getAll() async {
    return _box.values
        .map((v) => KbEntry.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> save(KbEntry e) async =>
      _box.put(e.id, e.toJson());

  @override
  Future<void> delete(String id) async =>
      _box.delete(id);
}
