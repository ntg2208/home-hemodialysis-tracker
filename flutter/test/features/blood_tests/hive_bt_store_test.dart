import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_hd/features/blood_tests/hive_bt_store.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/flavor.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_bt_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(communityBtBox);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(communityBtBox).clear();
  });

  test('empty store returns empty cache with null coveredFrom', () {
    final store = HiveBtStore(Hive.box(communityBtBox));
    final cache = store.readCache();
    expect(cache.rows, isEmpty);
    expect(cache.coveredFrom, isNull);
  });

  test('writeCache then readCache round-trips rows', () async {
    final store = HiveBtStore(Hive.box(communityBtBox));
    final row = BloodTestRow(
      marker: 'creatinine',
      datetime: '2026-06-01T09:00:00.000Z',
      value: 980,
      unit: 'umol/L',
      refLow: 64,
      refHigh: 104,
      timing: 'pre',
      note: '',
      source: 'manual',
      labId: '',
      phase: '',
      createdAt: '2026-06-01',
      qualitative: false,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.writeCache([row], '2026-01-01', now);
    final cache = store.readCache();
    expect(cache.rows.length, 1);
    expect(cache.rows.first.marker, 'creatinine');
    expect(cache.lastSynced, greaterThan(now - 1000));
  });
}
