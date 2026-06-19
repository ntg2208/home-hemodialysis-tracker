import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/features/mcp/mcp_settings.dart';

void main() {
  setUp(() async {
    Hive.init('./.test_hive');
    await Hive.openBox('treatment');
  });
  tearDown(() async => Hive.deleteFromDisk());

  test('mcpServerEnabled defaults to false and persists when set', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(mcpServerEnabledProvider), isFalse);
    c.read(mcpServerEnabledProvider.notifier).set(true);
    expect(c.read(mcpServerEnabledProvider), isTrue);
    expect(Hive.box('treatment').get('mcp_server_enabled'), isTrue);
  });
}
