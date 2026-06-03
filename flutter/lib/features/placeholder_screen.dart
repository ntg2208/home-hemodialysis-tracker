import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/shell.dart';
import '../app/theme.dart';

/// Temporary drawer-destination screens, replaced phase by phase.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.note});
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.findAncestorWidgetOfExactType<StatefulNavigationShell>()?.goBranch(0);
      },
      child: HdScaffold(
        title: title,
        body: Center(
          child: Text(note ?? '$title — coming soon',
              style: TextStyle(color: context.hd.textMuted)),
        ),
      ),
    );
  }
}
