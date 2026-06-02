import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Full-width pill CTA with a saving spinner and an inline error+Retry box.
/// Port of frontend SaveButton.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.saving,
    required this.onPressed,
    required this.label,
    this.error,
    this.icon,
    this.enabled = true,
  });

  final bool saving;
  final VoidCallback onPressed;
  final String label;
  final String? error;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: (saving || !enabled) ? null : onPressed,
          icon: saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.accentOn))
              : (icon != null ? Icon(icon) : const SizedBox.shrink()),
          label: Text(saving ? 'Saving…' : label),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.danger.withValues(alpha: 0.15),
              border: Border.all(color: t.danger),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                    child: Text(error!,
                        style: TextStyle(color: t.danger, fontSize: 13))),
                TextButton(
                    onPressed: saving ? null : onPressed,
                    child: const Text('Retry')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
