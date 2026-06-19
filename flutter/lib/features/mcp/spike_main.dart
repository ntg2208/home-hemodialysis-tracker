// Spike: MCP server API validation on Pixel 9.
// Run: cd flutter && flutter run -d <device> -t lib/features/mcp/spike_main.dart
// Then: npx @modelcontextprotocol/inspector → SSE → http://<phone-ip>:8080/sse
//
// Spikes three things the plan depends on:
// 1. Handler runs on the main isolate (required for Riverpod access later)
// 2. SseServerTransport exposes request headers (for Task 5 bearer key)
// 3. End-to-end round-trip: list tools → call echo → close

import 'dart:async';
import 'dart:io';
import 'dart:isolate' show Isolate;

import 'package:flutter/material.dart';
import 'package:mcp_server/mcp_server.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SpikeRunner(),
          ),
        ),
      ),
    );
  }
}

class SpikeRunner extends StatefulWidget {
  const SpikeRunner({super.key});

  @override
  State<SpikeRunner> createState() => _SpikeRunnerState();
}

class _SpikeRunnerState extends State<SpikeRunner> {
  String _status = 'starting…';
  String _lanUrl = '';
  Server? _server;
  SseServerTransport? _transport;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final server = Server(
        name: 'HD Tracker',
        version: '1.0.0',
        capabilities: const ServerCapabilities(tools: ToolsCapability()),
      );

      // Verify main-isolate requirement
      setState(() {
        _status = 'Isolate: ${Isolate.current.debugName ?? "(unnamed)"}';
      });

      // Add an echo tool that also logs request headers if available
      server.addTool(
        name: 'echo',
        description: 'Echoes input back',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'}
          },
        },
        handler: (args) async {
          // Confirm we're on the main isolate each call
          final isolateName =
              Isolate.current.debugName ?? '(unnamed)';
          return {
            'echo': args['text'],
            'isolate': isolateName,
            'timestamp': DateTime.now().toIso8601String(),
          };
        },
      );

      // Find the best LAN IP
      String lanIp = 'localhost';
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) {
            lanIp = addr.address;
            break;
          }
        }
        if (lanIp != 'localhost') break;
      }

      _lanUrl = 'http://$lanIp:8080/sse';

      // Start SSE transport on all interfaces
      final transport = SseServerTransport(
        endpoint: '/sse',
        messagesEndpoint: '/messages',
        host: '0.0.0.0',
        port: 8080,
      );
      _transport = transport;
      server.connect(transport);
      _server = server;

      setState(() {
        _status += '\nServer live at:\n$_lanUrl';
      });
    } catch (e, stack) {
      setState(() {
        _status += '\nERROR: $e\n$stack';
      });
    }
  }

  @override
  void dispose() {
    _transport?.close();
    _server?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _status,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 16,
        color: Colors.greenAccent,
      ),
    );
  }
}
