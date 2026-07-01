import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';
import 'store.dart';

/// The lifecycle phase of the treatment flow. The router mirrors this in the
/// URL (`/treatment`, `/treatment/pre`, `/treatment/active`, `/treatment/post`)
/// so the browser back button behaves; this controller owns the *data* that has
/// to survive those route pushes (previously held in `TreatmentFlow`'s State).
enum TreatmentPhase { idle, pre, active, post }

class TreatmentFlowState {
  const TreatmentFlowState({
    this.phase = TreatmentPhase.idle,
    this.existingIds = const [],
    this.session,
    this.readings = const [],
    this.heparinUsed = true,
    this.epoUsed = true,
    this.countdownStartedAt,
    this.targetMin,
    this.comment,
    this.consumed,
  });

  final TreatmentPhase phase;
  final List<String> existingIds;
  final Session? session;
  final List<PendingReading> readings;
  final bool heparinUsed;
  final bool epoUsed;
  final int? countdownStartedAt;
  final int? targetMin;
  final String? comment;
  final SessionConsumed? consumed;

  TreatmentFlowState copyWith({
    TreatmentPhase? phase,
    List<String>? existingIds,
    Session? session,
    List<PendingReading>? readings,
    bool? heparinUsed,
    bool? epoUsed,
    int? countdownStartedAt,
    String? comment,
    SessionConsumed? consumed,
    int? targetMin,
  }) =>
      TreatmentFlowState(
        phase: phase ?? this.phase,
        existingIds: existingIds ?? this.existingIds,
        session: session ?? this.session,
        readings: readings ?? this.readings,
        heparinUsed: heparinUsed ?? this.heparinUsed,
        epoUsed: epoUsed ?? this.epoUsed,
        countdownStartedAt: countdownStartedAt ?? this.countdownStartedAt,
        targetMin: targetMin ?? this.targetMin,
        comment: comment ?? this.comment,
        consumed: consumed ?? this.consumed,
      );
}

final treatmentFlowProvider =
    NotifierProvider<TreatmentFlowController, TreatmentFlowState>(
        TreatmentFlowController.new);

class TreatmentFlowController extends Notifier<TreatmentFlowState> {
  TreatmentStore get _store => ref.read(treatmentStoreProvider);

  @override
  TreatmentFlowState build() {
    // Restore an in-progress session (survives reload / relaunch).
    final active = _store.getActiveState();
    if (active == null) return const TreatmentFlowState();
    final phase = switch (active.screen) {
      'pre' => TreatmentPhase.pre,
      'active' => TreatmentPhase.active,
      'post' => TreatmentPhase.post,
      _ => TreatmentPhase.idle,
    };
    if (phase == TreatmentPhase.idle) return const TreatmentFlowState();

    // Demote any in-flight reading to error ("interrupted") on restore.
    final readings = (active.readings ?? []).map((p) {
      if (p.status == SaveStatus.pending) {
        return PendingReading(p.reading,
            status: SaveStatus.error, errorMsg: 'interrupted');
      }
      return p;
    }).toList();

    return TreatmentFlowState(
      phase: phase,
      existingIds: active.existingIds ?? const [],
      session: active.session,
      readings: readings,
      heparinUsed: active.heparinUsed ?? true,
      epoUsed: active.epoUsed ?? true,
      countdownStartedAt: active.countdownStartedAt,
      targetMin: active.targetMin,
      comment: active.comment,
      consumed: active.consumed,
    );
  }

  void goPre(List<String> existingIds) {
    state = TreatmentFlowState(
        phase: TreatmentPhase.pre, existingIds: existingIds);
    _persist('pre');
  }

  void startActive(Session session, bool heparinUsed, bool epoUsed) {
    state = TreatmentFlowState(
      phase: TreatmentPhase.active,
      session: session,
      readings: const [],
      heparinUsed: heparinUsed,
      epoUsed: epoUsed,
    );
    _persist('active');
  }

  void updateReadings(List<PendingReading> readings) {
    state = state.copyWith(readings: readings);
    _persist('active');
  }

  void updateCountdown(int? startedAt, int targetMin) {
    state = state.copyWith(countdownStartedAt: startedAt, targetMin: targetMin);
    _persist('active');
  }

  void setHeparin(bool v) {
    state = state.copyWith(heparinUsed: v);
    _persist('active');
  }

  void setEpo(bool v) {
    state = state.copyWith(epoUsed: v);
    _persist('active');
  }

  void setComment(String? v) {
    state = state.copyWith(comment: v);
    _persist(state.phase == TreatmentPhase.post ? 'post' : 'active');
  }

  void goPost(SessionConsumed consumed) {
    state = state.copyWith(phase: TreatmentPhase.post, consumed: consumed);
    _persist('post');
  }

  void backToActive() {
    state = state.copyWith(phase: TreatmentPhase.active);
    _persist('active');
  }

  void finish() {
    _store.clearActiveState();
    state = const TreatmentFlowState();
  }

  void _persist(String screen) {
    _store.saveActiveState(ActiveState(
      screen: screen,
      session: state.session,
      existingIds: state.existingIds,
      readings: state.readings,
      heparinUsed: state.heparinUsed,
      epoUsed: state.epoUsed,
      consumed: state.consumed,
      countdownStartedAt: state.countdownStartedAt,
      targetMin: state.targetMin,
      comment: state.comment,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}
