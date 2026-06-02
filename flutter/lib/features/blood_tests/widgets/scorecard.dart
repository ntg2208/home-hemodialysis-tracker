import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../logic.dart';
import '../markers.dart';
import '../models.dart';
import 'scorecard_tile.dart';

/// Scorecard tab: favourites pinned on top, then markers grouped by panel.
class Scorecard extends StatelessWidget {
  const Scorecard({
    super.key,
    required this.rows,
    required this.favorites,
    required this.onSelectMarker,
    required this.onToggleFavorite,
  });

  final List<BloodTestRow> rows;
  final Set<String> favorites;
  final ValueChanged<String> onSelectMarker;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No results for these filters.',
            style: TextStyle(color: t.textMuted)),
      );
    }

    final byMarker = <String, List<BloodTestRow>>{};
    for (final r in rows) {
      byMarker.putIfAbsent(r.marker, () => []).add(r);
    }
    final summaries = byMarker.entries
        .map((e) => summarize(e.key, e.value))
        .toList()
      ..sort((a, b) => a.marker.compareTo(b.marker));

    final byPanel = <String, List<MarkerSummary>>{};
    for (final s in summaries) {
      byPanel.putIfAbsent(panelFor(s.marker), () => []).add(s);
    }
    final favSummaries =
        summaries.where((s) => favorites.contains(s.marker)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (favSummaries.isNotEmpty) ...[
          _heading(t, 'FAVOURITES', color: t.warning, icon: Icons.star),
          ...favSummaries.map((s) => ScorecardTile(
                summary: s,
                starred: true,
                onSelect: () => onSelectMarker(s.marker),
                onToggleStar: () => onToggleFavorite(s.marker),
              )),
          const SizedBox(height: 16),
        ],
        for (final panel in panels.where(byPanel.containsKey)) ...[
          _heading(t, panel.toUpperCase()),
          ...byPanel[panel]!.map((s) => ScorecardTile(
                summary: s,
                starred: favorites.contains(s.marker),
                onSelect: () => onSelectMarker(s.marker),
                onToggleStar: () => onToggleFavorite(s.marker),
              )),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _heading(HdTokens t, String text, {Color? color, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color ?? t.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: color ?? t.textSecondary)),
        ]),
      );
}
