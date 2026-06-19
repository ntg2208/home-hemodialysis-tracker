import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mcp/mcp_settings.dart';

class McpSettingsSection extends ConsumerWidget {
  const McpSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(mcpServerEnabledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Allow external AI clients (same WiFi)'),
          subtitle: const Text(
            'Lets Claude Code / Gemini CLI drive the app over your local '
            'network. Android app only — keep it running. '
            'For other networks, use Tailscale.',
          ),
          value: enabled,
          onChanged: (v) =>
              ref.read(mcpServerEnabledProvider.notifier).set(v),
        ),
        if (enabled)
          FutureBuilder<String>(
            future: mcpLanUrl(),
            builder: (context, snap) => ListTile(
              dense: true,
              title: const Text('Connect URL'),
              subtitle: Text(
                snap.data ?? '…',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
