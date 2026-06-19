import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mcp/mcp_auth.dart';
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
        if (enabled) ...[
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
          ref.watch(mcpBearerKeyProvider).when(
            data: (key) => ListTile(
              dense: true,
              title: const Text('Bearer key'),
              subtitle: Text(
                '(only needed for public tunnels — not for same-WiFi or Tailscale)',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withAlpha(0x99)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: key));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bearer key copied')),
                  );
                },
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}
