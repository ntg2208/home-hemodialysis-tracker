import 'command_dispatch.dart';
import 'screen_context.dart';

// Per-field clinical sanity ranges: (min, max) inclusive.
const _ranges = <String, (num, num)>{
  'weight': (30, 200),
  'bp_sys': (50, 260),
  'bp_dia': (30, 160),
  'pulse': (30, 200),
  'uf_goal': (0, 6),
  'uf_rate': (0, 2000),
  'blood_flow': (50, 600),
  'total_uf': (0, 6),
};

/// Returns null if all numeric values in [cmd] are within clinical sanity ranges,
/// or an error string describing the first out-of-range field.
/// Called alongside [validateCommand]; error is returned as a FunctionResponse
/// so the model can re-ask with a corrected value.
String? validateValues(AppCommand cmd) {
  final checks = switch (cmd) {
    PrefillPreTreatment(:final weight, :final bpSys, :final bpDia, :final pulse, :final ufGoal, :final ufRate) => {
        'weight': weight,
        'bp_sys': bpSys,
        'bp_dia': bpDia,
        'pulse': pulse,
        'uf_goal': ufGoal,
        'uf_rate': ufRate,
      },
    PrefillReading(:final bpSys, :final bpDia, :final pulse, :final bloodFlow) => {
        'bp_sys': bpSys,
        'bp_dia': bpDia,
        'pulse': pulse,
        'blood_flow': bloodFlow,
      },
    PrefillPostTreatment(:final weight, :final bpSys, :final bpDia, :final pulse, :final totalUf) ||
    EndSession(:final weight, :final bpSys, :final bpDia, :final pulse, :final totalUf) => {
        'weight': weight,
        'bp_sys': bpSys,
        'bp_dia': bpDia,
        'pulse': pulse,
        'total_uf': totalUf,
      },
    _ => <String, num?>{},
  };

  for (final entry in checks.entries) {
    final value = entry.value;
    if (value == null) continue;
    final range = _ranges[entry.key];
    if (range != null && (value < range.$1 || value > range.$2)) {
      return '${entry.key}=$value looks out of range '
          '(expected ${range.$1}–${range.$2}). Please confirm the value.';
    }
  }
  return null;
}

/// Returns null if [cmd] is valid in [state], or an error string if blocked.
/// Called by GeminiChatResponder before dispatching; error is sent back as
/// the FunctionResponse so Gemini narrates it to the user.
String? validateCommand(AppCommand cmd, TreatmentState state) => switch (cmd) {
      PrefillPreTreatment() when state != TreatmentState.idle =>
        state == TreatmentState.active
            ? 'A session is already in progress. Add a reading or end the session first.'
            : 'Cannot start a new session while the current form is open.',
      PrefillReading() when state != TreatmentState.active =>
        state == TreatmentState.idle
            ? 'There is no active session. Start a session first, then add readings.'
            : 'Cannot add a reading -- the session is not yet active.',
      PrefillPostTreatment() when state != TreatmentState.postForm =>
        state == TreatmentState.idle
            ? 'There is no session to finish. Start one first.'
            : 'Cannot fill post-treatment details until the active session is ended.',
      EndSession() when state != TreatmentState.active =>
        state == TreatmentState.idle
            ? 'There is no active session to end.'
            : 'The session cannot be ended from this state.',
      _ => null,
    };
