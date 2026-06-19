import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:home_hd/features/chat/command_dispatch.dart';
import 'package:home_hd/features/chat/screen_context.dart';
import 'package:home_hd/features/mcp/hd_mcp_server.dart';

// Expose a Ref via a Provider so handleToolCall can be tested with a container.
final _refProvider = Provider<Ref>((ref) => ref);

(ProviderContainer, Ref) _setup(TreatmentState state) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  // screenContextProvider is a NotifierProvider — call its notifier to set state
  c.read(screenContextProvider.notifier).setTreatmentState(state);
  return (c, c.read(_refProvider));
}

void main() {
  test('valid navigate_to dispatches and returns ok', () async {
    final (c, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('navigate_to', {'route': '/fitness'}, ref);
    expect(res.isError, isNot(true)); // null or false = ok
    expect(c.read(pendingNavigationProvider), '/fitness');
  });

  test('prefill_reading while idle returns a validation error, no dispatch', () async {
    final (c, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('prefill_reading', {'bp_sys': 120}, ref);
    expect(res.isError, isTrue);
    expect((res.content[0] as TextContent).text, isNotEmpty);
    expect(c.read(prefillReadingCommandProvider), isNull);
  });

  test('unknown tool returns an error', () async {
    final (_, ref) = _setup(TreatmentState.idle);
    final res = await handleToolCall('nope', {}, ref);
    expect(res.isError, isTrue);
    expect((res.content[0] as TextContent).text, contains('Unknown tool: nope'));
  });
}
