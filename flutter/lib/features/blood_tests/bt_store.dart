import 'package:hive/hive.dart';

import 'models.dart';

/// Blood-test cache + favourites, backed by the shared Hive cache box.
/// Port of BloodTests/storage.ts (rows/coveredFrom/lastSynced) plus the
/// `blood_test_favorites` localStorage set from index.tsx.
class BtCache {
  const BtCache(this.rows, this.coveredFrom, this.lastSynced);
  final List<BloodTestRow> rows;
  final String? coveredFrom; // earliest cached month; '' = all time; null = empty
  final int? lastSynced;
}

class BtStore {
  BtStore(this._box);
  final Box _box;

  static const _rowsKey = 'bt_rows';
  static const _coveredKey = 'bt_covered_from';
  static const _syncedKey = 'bt_last_synced';
  static const _favKey = 'bt_favorites';

  BtCache readCache() {
    final raw = _box.get(_rowsKey);
    final rows = raw is List
        ? raw
            .map((e) => BloodTestRow.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <BloodTestRow>[];
    return BtCache(
      rows,
      _box.get(_coveredKey) as String?,
      (_box.get(_syncedKey) as num?)?.toInt(),
    );
  }

  Future<void> writeCache(
      List<BloodTestRow> rows, String coveredFrom, int lastSynced) async {
    await _box.put(_rowsKey, rows.map((r) => r.toJson()).toList());
    await _box.put(_coveredKey, coveredFrom);
    await _box.put(_syncedKey, lastSynced);
  }

  Set<String> readFavorites() {
    final raw = _box.get(_favKey);
    return raw is List ? raw.cast<String>().toSet() : <String>{};
  }

  Future<void> writeFavorites(Set<String> favs) =>
      _box.put(_favKey, favs.toList());
}
