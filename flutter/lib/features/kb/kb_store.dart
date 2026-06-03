// flutter/lib/features/kb/kb_store.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../features/treatment/treatment_auth.dart';
import '../../firebase/firebase_init.dart';

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
  final String source; // 'user' | 'ai-proposed'
  final DateTime createdAt;
  final DateTime updatedAt;

  static String newId() => const Uuid().v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'source': source,
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
      };

  factory KbEntry.fromMap(Map<String, dynamic> m) => KbEntry(
        id: m['id'] as String,
        title: m['title'] as String,
        content: m['content'] as String,
        source: m['source'] as String? ?? 'user',
        createdAt: (m['created_at'] as Timestamp).toDate(),
        updatedAt: (m['updated_at'] as Timestamp).toDate(),
      );
}

class KbStore {
  KbStore(this._auth);
  final TreatmentAuth _auth;

  CollectionReference<Map<String, dynamic>> get _col =>
      firestore.collection('kb_entries');

  Future<List<KbEntry>> getAll() async {
    await _auth.ensure();
    final snap =
        await _col.orderBy('updated_at', descending: true).get();
    return snap.docs
        .map((d) => KbEntry.fromMap(d.data()))
        .toList();
  }

  Future<void> save(KbEntry e) async {
    await _auth.ensure();
    await _col.doc(e.id).set(e.toMap());
  }

  Future<void> delete(String id) async {
    await _auth.ensure();
    await _col.doc(id).delete();
  }
}
