import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Command sealed hierarchy
// ---------------------------------------------------------------------------

sealed class AppCommand {}

class NavigateTo extends AppCommand {
  NavigateTo(this.route);
  final String route;
}

class FilterBloodTests extends AppCommand {
  FilterBloodTests({this.marker, this.phase, this.months, this.tab});
  final String? marker;
  final String? phase;
  final int? months;
  final String? tab; // 'scorecard' | 'trend'
}

class FilterFitness extends AppCommand {
  FilterFitness({this.type, this.days});
  final String? type;
  final int? days;
}

class PrefillPreTreatment extends AppCommand {
  PrefillPreTreatment({
    this.weight,
    this.bpSys,
    this.bpDia,
    this.pulse,
    this.ufGoal,
    this.ufRate,
  });
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? ufGoal, ufRate;
}

class PrefillReading extends AppCommand {
  PrefillReading({
    this.bpSys,
    this.bpDia,
    this.pulse,
    this.bloodFlow,
    this.vp,
    this.ap,
  });
  final int? bpSys, bpDia, pulse, bloodFlow, vp, ap;
}

class PrefillPostTreatment extends AppCommand {
  PrefillPostTreatment({
    this.weight,
    this.bpSys,
    this.bpDia,
    this.pulse,
    this.totalUf,
  });
  final double? weight;
  final int? bpSys, bpDia, pulse;
  final double? totalUf;
}

// ---------------------------------------------------------------------------
// Riverpod 3.x Notifier + NotifierProvider per command type
// ---------------------------------------------------------------------------

// Navigation — stores a route string
class PendingNavigationNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? route) => state = route;
}

final pendingNavigationProvider =
    NotifierProvider<PendingNavigationNotifier, String?>(
  PendingNavigationNotifier.new,
);

// Blood test filter command
class BtFilterCommandNotifier extends Notifier<FilterBloodTests?> {
  @override
  FilterBloodTests? build() => null;
  void set(FilterBloodTests? cmd) => state = cmd;
}

final btFilterCommandProvider =
    NotifierProvider<BtFilterCommandNotifier, FilterBloodTests?>(
  BtFilterCommandNotifier.new,
);

// Fitness filter command
class FitnessFilterCommandNotifier extends Notifier<FilterFitness?> {
  @override
  FilterFitness? build() => null;
  void set(FilterFitness? cmd) => state = cmd;
}

final fitnessFilterCommandProvider =
    NotifierProvider<FitnessFilterCommandNotifier, FilterFitness?>(
  FitnessFilterCommandNotifier.new,
);

// Prefill pre-treatment command
class PrefillPreCommandNotifier extends Notifier<PrefillPreTreatment?> {
  @override
  PrefillPreTreatment? build() => null;
  void set(PrefillPreTreatment? cmd) => state = cmd;
}

final prefillPreCommandProvider =
    NotifierProvider<PrefillPreCommandNotifier, PrefillPreTreatment?>(
  PrefillPreCommandNotifier.new,
);

// Prefill reading command
class PrefillReadingCommandNotifier extends Notifier<PrefillReading?> {
  @override
  PrefillReading? build() => null;
  void set(PrefillReading? cmd) => state = cmd;
}

final prefillReadingCommandProvider =
    NotifierProvider<PrefillReadingCommandNotifier, PrefillReading?>(
  PrefillReadingCommandNotifier.new,
);

// Prefill post-treatment command
class PrefillPostCommandNotifier extends Notifier<PrefillPostTreatment?> {
  @override
  PrefillPostTreatment? build() => null;
  void set(PrefillPostTreatment? cmd) => state = cmd;
}

final prefillPostCommandProvider =
    NotifierProvider<PrefillPostCommandNotifier, PrefillPostTreatment?>(
  PrefillPostCommandNotifier.new,
);

// ---------------------------------------------------------------------------
// dispatchCommand — routes an AppCommand to the correct provider
// ---------------------------------------------------------------------------

/// Dispatch an [AppCommand] to its NotifierProvider.
/// Called by [GeminiChatResponder] after [validateCommand] clears it.
/// Takes [Ref] (not [WidgetRef]) so it can be called from a Notifier's ref.
void dispatchCommand(AppCommand cmd, Ref ref) {
  switch (cmd) {
    case NavigateTo(:final route):
      ref.read(pendingNavigationProvider.notifier).set(route);
    case FilterBloodTests():
      ref.read(btFilterCommandProvider.notifier).set(cmd);
    case FilterFitness():
      ref.read(fitnessFilterCommandProvider.notifier).set(cmd);
    case PrefillPreTreatment():
      // Also navigate to /treatment so the form is visible.
      ref.read(pendingNavigationProvider.notifier).set('/treatment');
      ref.read(prefillPreCommandProvider.notifier).set(cmd);
    case PrefillReading():
      ref.read(prefillReadingCommandProvider.notifier).set(cmd);
    case PrefillPostTreatment():
      ref.read(prefillPostCommandProvider.notifier).set(cmd);
  }
}
