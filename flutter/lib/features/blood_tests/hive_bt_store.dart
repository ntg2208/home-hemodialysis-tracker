import 'bt_store.dart';
import 'models.dart';

/// Community blood test store. Uses a dedicated Hive box as the primary store.
/// Always returns lastSynced = now so the screen never triggers a remote fetch.
class HiveBtStore extends BtStore {
  HiveBtStore(super.box);

  static const _rowsKey = 'bt_rows';
  static const _coveredKey = 'bt_covered_from';

  @override
  BtCache readCache() {
    final raw = box.get(_rowsKey);
    final rows = raw is List
        ? raw
            .map((e) => BloodTestRow.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <BloodTestRow>[];
    return BtCache(
      rows,
      box.get(_coveredKey) as String?,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> writeCache(
      List<BloodTestRow> rows, String coveredFrom, int lastSynced) async {
    await box.put(_rowsKey, rows.map((r) => r.toJson()).toList());
    await box.put(_coveredKey, coveredFrom);
  }

  Future<void> upsertRow(BloodTestRow row) async {
    final key = '${row.datetime.substring(0, 10)}_${row.marker}';
    final existing = readCache();
    final updated = [
      ...existing.rows.where(
          (r) => '${r.datetime.substring(0, 10)}_${r.marker}' != key),
      row,
    ];
    await writeCache(updated, existing.coveredFrom ?? '', 0);
  }

  Future<void> deleteRow(String date, String marker) async {
    final key = '${date}_$marker';
    final existing = readCache();
    final updated = existing.rows
        .where((r) => '${r.datetime.substring(0, 10)}_${r.marker}' != key)
        .toList();
    await writeCache(updated, existing.coveredFrom ?? '', 0);
  }
}
