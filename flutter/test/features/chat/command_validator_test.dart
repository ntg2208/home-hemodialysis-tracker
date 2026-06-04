import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/command_dispatch.dart';
import 'package:home_hd/features/chat/command_validator.dart';
import 'package:home_hd/features/chat/screen_context.dart';

void main() {
  group('validateCommand', () {
    test('NavigateTo is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(NavigateTo('/blood-tests'), state), isNull);
      }
    });

    test('FilterBloodTests is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(FilterBloodTests(marker: 'haemoglobin'), state), isNull);
      }
    });

    test('FilterFitness is always valid', () {
      for (final state in TreatmentState.values) {
        expect(validateCommand(FilterFitness(type: 'steps'), state), isNull);
      }
    });

    test('PrefillPreTreatment valid only when idle', () {
      expect(validateCommand(PrefillPreTreatment(weight: 72.4), TreatmentState.idle), isNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.active), isNotNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.preForm), isNotNull);
      expect(validateCommand(PrefillPreTreatment(), TreatmentState.postForm), isNotNull);
    });

    test('PrefillPreTreatment active gives session-in-progress message', () {
      final error = validateCommand(PrefillPreTreatment(), TreatmentState.active);
      expect(error, contains('already in progress'));
    });

    test('PrefillReading valid only when active', () {
      expect(validateCommand(PrefillReading(bpSys: 130), TreatmentState.active), isNull);
      expect(validateCommand(PrefillReading(), TreatmentState.idle), isNotNull);
      expect(validateCommand(PrefillReading(), TreatmentState.preForm), isNotNull);
      expect(validateCommand(PrefillReading(), TreatmentState.postForm), isNotNull);
    });

    test('PrefillReading idle gives no-session message', () {
      final error = validateCommand(PrefillReading(), TreatmentState.idle);
      expect(error, contains('Start a session first'));
    });

    test('PrefillPostTreatment valid only when postForm', () {
      expect(validateCommand(PrefillPostTreatment(weight: 70.0), TreatmentState.postForm), isNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.idle), isNotNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.active), isNotNull);
      expect(validateCommand(PrefillPostTreatment(), TreatmentState.preForm), isNotNull);
    });
  });
}
