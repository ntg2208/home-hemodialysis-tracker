import 'package:hive/hive.dart';

/// Generic stale-while-revalidate JSON cache backed by a Hive box. Replaces the
/// per-feature localStorage caches in the React app. One box shared across
/// read-heavy features (fitness, blood tests).
class CacheStore {
  CacheStore(this._box);
  final Box _box;

  /// Cached JSON for [key] if present and within [ttl]; otherwise null.
  Map<String, dynamic>? read(String key, Duration ttl) {
    final raw = _box.get(key);
    if (raw is! Map) return null;
    final cachedAt = (raw['cachedAt'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - cachedAt > ttl.inMilliseconds) {
      return null;
    }
    final data = raw['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// Returns cached JSON for [key] regardless of age. Used as a fallback when
  /// the network is unavailable and fresh data can't be fetched.
  Map<String, dynamic>? readStale(String key) {
    final raw = _box.get(key);
    if (raw is! Map) return null;
    final data = raw['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<void> write(String key, Map<String, dynamic> data) => _box.put(key, {
        'data': data,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      });
}
