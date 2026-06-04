import 'command_dispatch.dart';
import 'screen_context.dart';

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
      _ => null,
    };
