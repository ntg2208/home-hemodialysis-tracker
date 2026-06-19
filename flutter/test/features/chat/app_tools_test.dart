import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/app_tools.dart';
import 'package:home_hd/features/chat/command_dispatch.dart';

void main() {
  test('parseAppCommand maps navigate_to', () {
    final cmd = parseAppCommand('navigate_to', {'route': '/fitness'});
    expect(cmd, isA<NavigateTo>());
    expect((cmd as NavigateTo).route, '/fitness');
  });

  test('parseAppCommand coerces numeric prefill fields', () {
    final cmd = parseAppCommand(
        'prefill_pre_treatment', {'weight': 72.4, 'bp_sys': 140, 'bp_dia': 85});
    expect(cmd, isA<PrefillPreTreatment>());
    final p = cmd as PrefillPreTreatment;
    expect(p.weight, 72.4);
    expect(p.bpSys, 140);
    expect(p.bpDia, 85);
  });

  test('parseAppCommand returns null for unknown / retriever tools', () {
    expect(parseAppCommand('not_a_tool', {}), isNull);
    expect(parseAppCommand('get_blood_markers', {}), isNull);
  });

  test('appToolSpecs lists exactly the seven command tools', () {
    expect(appToolSpecs.map((t) => t.name).toSet(), {
      'navigate_to',
      'filter_blood_tests',
      'filter_fitness',
      'prefill_pre_treatment',
      'prefill_reading',
      'prefill_post_treatment',
      'end_session',
    });
  });
}
