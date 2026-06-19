import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_server/mcp_server.dart';

import '../chat/app_tools.dart';
import '../chat/command_dispatch.dart';
import '../chat/command_validator.dart';
import '../chat/screen_context.dart';

/// Bridge: parse → validate against live TreatmentState → dispatch.
/// Returns an MCP [CallToolResult]. Pure with respect to [ref];
/// unit-testable with a [ProviderContainer].
Future<CallToolResult> handleToolCall(
    String name, Map<String, dynamic> args, Ref ref) async {
  final cmd = parseAppCommand(name, args);
  if (cmd == null) {
    return CallToolResult(
      content: [TextContent(text: 'Unknown tool: $name')],
      isError: true,
    );
  }
  final state = ref.read(screenContextProvider).treatmentState;
  final error = validateCommand(cmd, state);
  if (error != null) {
    return CallToolResult(
      content: [TextContent(text: error)],
      isError: true,
    );
  }
  dispatchCommand(cmd, ref);
  return CallToolResult(
    content: [TextContent(text: 'Done: $name')],
    isError: false,
  );
}

/// Owns the embedded MCP server lifecycle. Provider-scoped so it holds a [Ref]
/// that handler closures use to dispatch into the app.
class HdMcpServer {
  HdMcpServer(this.ref);
  final Ref ref;
  Server? _server;
  SseServerTransport? _transport;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = Server(
        name: 'HD Tracker',
        version: '1.0.0',
        capabilities: const ServerCapabilities(tools: ToolsCapability()),
      );
      for (final t in appToolSpecs) {
        server.addTool(
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema,
          handler: (args) async => handleToolCall(t.name, args, ref),
        );
      }
      final transport = SseServerTransport(
        endpoint: '/sse',
        messagesEndpoint: '/messages',
        host: '0.0.0.0',
        port: 8080,
      );
      server.connect(transport);
      _transport = transport;
      _server = server;
      print('MCP server started on :8080');
    } catch (e, stack) {
      print('MCP server start failed: $e\n$stack');
      rethrow;
    }
  }

  void stop() {
    _transport?.close();
    _transport = null;
    _server?.dispose();
    _server = null;
  }
}

final hdMcpServerProvider = Provider<HdMcpServer>((ref) => HdMcpServer(ref));
