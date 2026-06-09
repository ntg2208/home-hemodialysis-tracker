import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_hd/features/treatment/hive_treatment_repo.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/flavor.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(communitySessionsBox);
    await Hive.openBox(communityReadingsBox);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(communitySessionsBox).clear();
    await Hive.box(communityReadingsBox).clear();
  });

  test('saveSession and getAll round-trips', () async {
    final repo = HiveTreatmentRepo();
    final s = Session(
      sessionId: 'test-1',
      date: '2026-06-01',
      preWeight: 62.0,
      postWeight: 59.5,
      ufGoal: 2.5,
      ufRate: 10.0,
      preBpSys: 140,
      preBpDia: 85,
      prePulse: 72,
      postBpSys: 128,
      postBpDia: 78,
      postPulse: 68,
      durationMin: 255,
      dialysateVolume: 30.0,
      totalUf: 2.4,
    );
    await repo.saveSession(s);
    final result = await repo.getAll();
    expect(result.sessions.length, 1);
    expect(result.sessions.first.sessionId, 'test-1');
  });

  test('deleteSession removes session', () async {
    final repo = HiveTreatmentRepo();
    final s = Session(
      sessionId: 'del-1',
      date: '2026-06-01',
      preWeight: 62.0,
      postWeight: 59.5,
      ufGoal: 2.5,
      ufRate: 10.0,
      preBpSys: 140,
      preBpDia: 85,
      prePulse: 72,
      postBpSys: 128,
      postBpDia: 78,
      postPulse: 68,
      durationMin: 255,
      dialysateVolume: 30.0,
      totalUf: 2.4,
    );
    await repo.saveSession(s);
    await repo.deleteSession('del-1');
    final result = await repo.getAll();
    expect(result.sessions.where((x) => x.sessionId == 'del-1'), isEmpty);
  });

  test('saveReading and getReadings round-trips', () async {
    final repo = HiveTreatmentRepo();
    final r = Reading(
      readingId: 'r1',
      sessionId: 's1',
      seq: 1,
      time: '10:00',
      bpSys: 140,
      bpDia: 85,
      pulse: 72,
      bloodFlow: 350,
      venousPressure: 120,
      arterialPressure: -80,
    );
    await repo.saveReading(r);
    final readings = await repo.getReadings('s1');
    expect(readings.length, 1);
    expect(readings.first.readingId, 'r1');
  });
}
