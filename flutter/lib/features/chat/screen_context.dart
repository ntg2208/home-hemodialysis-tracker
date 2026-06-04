import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../treatment/models.dart';

enum TreatmentState { idle, preForm, active, postForm }

class AppScreenContext {
  const AppScreenContext({
    this.currentRoute = '/treatment',
    this.treatmentState = TreatmentState.idle,
    this.activeSession,
    this.sessionReadings = const [],
    this.openForm,
  });

  final String currentRoute;
  final TreatmentState treatmentState;
  final Session? activeSession;
  final List<Reading> sessionReadings;
  final Map<String, dynamic>? openForm;

  AppScreenContext copyWith({
    String? currentRoute,
    TreatmentState? treatmentState,
    Session? activeSession,
    bool clearActiveSession = false,
    List<Reading>? sessionReadings,
    Map<String, dynamic>? openForm,
    bool clearOpenForm = false,
  }) =>
      AppScreenContext(
        currentRoute: currentRoute ?? this.currentRoute,
        treatmentState: treatmentState ?? this.treatmentState,
        activeSession:
            clearActiveSession ? null : activeSession ?? this.activeSession,
        sessionReadings: sessionReadings ?? this.sessionReadings,
        openForm: clearOpenForm ? null : openForm ?? this.openForm,
      );

  List<String> get validCommands => [
        'navigate_to',
        'filter_blood_tests',
        'filter_fitness',
        if (treatmentState == TreatmentState.idle) 'prefill_pre_treatment',
        if (treatmentState == TreatmentState.active) 'prefill_reading',
        if (treatmentState == TreatmentState.postForm)
          'prefill_post_treatment',
      ];

  String toPromptSection() {
    final buf = StringBuffer();
    buf.writeln('--- CURRENT APP STATE ---');
    buf.writeln('Screen: $currentRoute');
    buf.writeln('Treatment state: ${treatmentState.name.toUpperCase()}');
    buf.writeln('Valid commands: ${validCommands.join(', ')}');

    final session = activeSession;
    if (session != null) {
      buf.writeln('Active session: ${session.sessionId}');
      if (session.preWeight != null) {
        buf.writeln(
            'Pre: weight=${session.preWeight}kg, BP=${session.preBpSys}/${session.preBpDia}, pulse=${session.prePulse}, UF goal=${session.ufGoal}L');
      }
      if (sessionReadings.isNotEmpty) {
        buf.writeln('Readings recorded: ${sessionReadings.length}');
        for (final r in sessionReadings.take(5)) {
          buf.writeln(
              '  ${r.time} -- BP ${r.bpSys}/${r.bpDia}, pulse ${r.pulse}, BF ${r.bloodFlow}');
        }
      }
    }

    final form = openForm;
    if (form != null) {
      final screen = form['screen'] as String? ?? 'unknown';
      buf.writeln('Open form: $screen');
      form.forEach((key, value) {
        if (key == 'screen') return;
        final display = value == null ? '-- (empty)' : '$value';
        buf.writeln('  $key: $display');
      });
    }

    buf.writeln('''
RULES:
- Only call tools listed in "Valid commands". If the user requests an invalid command, explain why and what they should do instead.
- For prefill commands: fill only the provided fields. Leave unspecified fields at their current values. Do not guess.
- After dispatching a command, describe what you did in plain language.
- If required fields are missing for a command, ask for them before calling the tool.''');

    return buf.toString().trim();
  }
}

class ScreenContextNotifier extends Notifier<AppScreenContext> {
  @override
  AppScreenContext build() => const AppScreenContext();

  void setRoute(String route) => state = state.copyWith(currentRoute: route);

  void setTreatmentState(
    TreatmentState ts, {
    Session? activeSession,
    bool clearSession = false,
    List<Reading>? readings,
  }) =>
      state = state.copyWith(
        treatmentState: ts,
        activeSession: activeSession,
        clearActiveSession: clearSession,
        sessionReadings:
            readings ?? (clearSession ? [] : state.sessionReadings),
      );

  void setOpenForm(Map<String, dynamic>? form) =>
      state = state.copyWith(openForm: form, clearOpenForm: form == null);

  void updateReadings(List<Reading> readings) =>
      state = state.copyWith(sessionReadings: readings);
}

final screenContextProvider =
    NotifierProvider<ScreenContextNotifier, AppScreenContext>(
  ScreenContextNotifier.new,
);
