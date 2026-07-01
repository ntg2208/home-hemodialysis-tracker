import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/treatment_flow_controller.dart';

const _session = Session(sessionId: '2026-06-02', date: '2026-06-02', preWeight: 60);

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_flowctl').path);
    await Hive.openBox(treatmentBoxName);
  });

  setUp(() async {
    await Hive.box(treatmentBoxName).clear();
  });

  ProviderContainer _container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts empty when no active session is persisted', () {
    final c = _container();
    final s = c.read(treatmentFlowProvider);
    expect(s.session, isNull);
    expect(s.phase, TreatmentPhase.idle);
  });

  test('startActive stores the session and persists phase=active', () {
    final c = _container();
    c.read(treatmentFlowProvider.notifier).startActive(_session, true, false);
    final s = c.read(treatmentFlowProvider);
    expect(s.session, _session);
    expect(s.phase, TreatmentPhase.active);
    expect(c.read(treatmentStoreProvider).getActiveState()?.screen, 'active');
  });

  test('goPost carries the session + consumed and persists phase=post', () {
    final c = _container();
    c.read(treatmentFlowProvider.notifier).startActive(_session, true, true);
    const consumed = SessionConsumed(needles: 2, onOffPacks: 1, heparinUsed: true);
    c.read(treatmentFlowProvider.notifier).goPost(consumed);
    final s = c.read(treatmentFlowProvider);
    expect(s.phase, TreatmentPhase.post);
    expect(s.consumed, consumed);
    expect(c.read(treatmentStoreProvider).getActiveState()?.screen, 'post');
  });

  test('finish clears persisted state and returns to idle', () {
    final c = _container();
    c.read(treatmentFlowProvider.notifier).startActive(_session, true, true);
    c.read(treatmentFlowProvider.notifier).finish();
    expect(c.read(treatmentFlowProvider).phase, TreatmentPhase.idle);
    expect(c.read(treatmentStoreProvider).getActiveState(), isNull);
  });

  test('restores phase from a persisted active session on first read', () {
    // Seed the store as if a session were in progress, then a fresh container
    // must come up already in the active phase.
    final seed = _container();
    seed.read(treatmentFlowProvider.notifier).startActive(_session, true, true);

    final fresh = _container();
    final s = fresh.read(treatmentFlowProvider);
    expect(s.phase, TreatmentPhase.active);
    expect(s.session?.sessionId, _session.sessionId);
  });
}
