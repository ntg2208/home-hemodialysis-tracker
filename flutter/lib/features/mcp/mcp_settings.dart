import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'hd_mcp_server.dart';

const _kBox = 'treatment';
const _kKey = 'mcp_server_enabled';

class McpServerEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => Hive.box(_kBox).get(_kKey, defaultValue: false) as bool;

  void set(bool v) {
    Hive.box(_kBox).put(_kKey, v);
    state = v;
  }
}

final mcpServerEnabledProvider =
    NotifierProvider<McpServerEnabledNotifier, bool>(
  McpServerEnabledNotifier.new,
);

/// Best-effort LAN URL for display. Picks the first non-loopback IPv4.
Future<String> mcpLanUrl() async {
  final interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4);
  for (final ni in interfaces) {
    for (final addr in ni.addresses) {
      if (!addr.isLoopback) return 'http://${addr.address}:8080/sse';
    }
  }
  return 'http://localhost:8080/sse';
}

/// Ensure the server follows the enabled flag. Call from a long-lived
/// ConsumerWidget/ConsumerState build to keep the listener alive.
void watchMcpLifecycle(WidgetRef ref) {
  ref.listen(mcpServerEnabledProvider, (_, enabled) {
    final server = ref.read(hdMcpServerProvider);
    if (enabled) {
      server.start();
    } else {
      server.stop();
    }
  });
  // Also sync on first build (listen fires only on changes).
  final server = ref.read(hdMcpServerProvider);
  if (ref.read(mcpServerEnabledProvider)) {
    server.start();
  }
}
