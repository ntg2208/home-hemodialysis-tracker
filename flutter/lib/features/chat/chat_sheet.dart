import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Opens the Chat bottom sheet. Placeholder until Task 19 (full chat UI + mock).
void showChatSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final t = ctx.hd;
      return FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Center(
            child: Text('Assistant — coming soon',
                style: TextStyle(color: t.textMuted)),
          ),
        ),
      );
    },
  );
}
