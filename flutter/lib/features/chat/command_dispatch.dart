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

class EndSession extends AppCommand {
  EndSession({this.weight, this.bpSys, this.bpDia, this.pulse, this.totalUf});
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

// Flag set just before an AI navigation dispatch so BranchSwitcher can use
// a slower crossfade to signal automated (vs. user-triggered) navigation.
class AiNavigationActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setActive(bool v) => state = v;
}

final aiNavigationActiveProvider =
    NotifierProvider<AiNavigationActiveNotifier, bool>(
  AiNavigationActiveNotifier.new,
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

// End session command — bool flag, true = triggered, false = idle
class EndSessionNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void trigger() => state = true;
  void consume() => state = false;
}

final endSessionProvider = NotifierProvider<EndSessionNotifier, bool>(
  EndSessionNotifier.new,
);

// Signal for the chat sheet to close itself before navigation fires.
// Set by dispatchCommand for any command that triggers navigation or a
// screen transition; consumed (reset) by the sheet when it pops.
class ChatSheetCloseNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void close() => state = true;
  void reset() => state = false;
}

final chatSheetCloseSignalProvider =
    NotifierProvider<ChatSheetCloseNotifier, bool>(
  ChatSheetCloseNotifier.new,
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
      ref.read(chatSheetCloseSignalProvider.notifier).close();
      ref.read(aiNavigationActiveProvider.notifier).setActive(true);
      ref.read(pendingNavigationProvider.notifier).set(route);
    case FilterBloodTests():
      ref.read(chatSheetCloseSignalProvider.notifier).close();
      ref.read(aiNavigationActiveProvider.notifier).setActive(true);
      ref.read(pendingNavigationProvider.notifier).set('/blood-tests');
      ref.read(btFilterCommandProvider.notifier).set(cmd);
    case FilterFitness():
      ref.read(chatSheetCloseSignalProvider.notifier).close();
      ref.read(aiNavigationActiveProvider.notifier).setActive(true);
      ref.read(pendingNavigationProvider.notifier).set('/fitness');
      ref.read(fitnessFilterCommandProvider.notifier).set(cmd);
    case PrefillPreTreatment():
      ref.read(chatSheetCloseSignalProvider.notifier).close();
      ref.read(aiNavigationActiveProvider.notifier).setActive(true);
      ref.read(pendingNavigationProvider.notifier).set('/treatment');
      ref.read(prefillPreCommandProvider.notifier).set(cmd);
    case PrefillReading():
      ref.read(prefillReadingCommandProvider.notifier).set(cmd);
    case PrefillPostTreatment():
      ref.read(prefillPostCommandProvider.notifier).set(cmd);
    case EndSession(:final weight, :final bpSys, :final bpDia, :final pulse, :final totalUf):
      ref.read(chatSheetCloseSignalProvider.notifier).close();
      ref.read(endSessionProvider.notifier).trigger();
      // Pre-fill the post-treatment form with any fields supplied in the command.
      if (weight != null || bpSys != null || bpDia != null || pulse != null || totalUf != null) {
        ref.read(prefillPostCommandProvider.notifier).set(PrefillPostTreatment(
          weight: weight, bpSys: bpSys, bpDia: bpDia, pulse: pulse, totalUf: totalUf,
        ));
      }
  }
}
