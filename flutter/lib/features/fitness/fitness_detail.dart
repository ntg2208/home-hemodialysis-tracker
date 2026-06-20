import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'baseline.dart';
import 'fitness_api.dart';
import 'metric_tiles.dart';
import 'providers.dart';

/// Routes to the right detail screen for a tile.
Widget detailFor(MetricTileDef def) =>
    def.isSleep ? const SleepDetailScreen() : TrendDetailScreen(def: def);

// ── Shared scaffold ───────────────────────────────────────────────────────────

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        foregroundColor: t.textPrimary,
        elevation: 0,
        title: Text(title),
      ),
      body: child,
    );
  }
}

Widget _card(HdTokens t, Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );

Widget _sectionLabel(HdTokens t, String s) => Text(
      s,
      style: TextStyle(fontSize: 11, letterSpacing: 1, color: t.textMuted),
    );

Widget _errorView(HdTokens t, VoidCallback retry) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: t.warning, size: 36),
          const SizedBox(height: 8),
          Text('Could not load data.', style: TextStyle(color: t.textPrimary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );

// ── Trend detail (HRV / RHR / Respiratory) ────────────────────────────────────

class TrendDetailScreen extends ConsumerStatefulWidget {
  const TrendDetailScreen({super.key, required this.def});
  final MetricTileDef def;
  @override
  ConsumerState<TrendDetailScreen> createState() => _TrendDetailScreenState();
}

class _TrendDetailScreenState extends ConsumerState<TrendDetailScreen> {
  late Future<FitnessSeries> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(fitnessApiProvider).fetchSeries(widget.def.key);
  }

  void _reload() => setState(() {
        _future = ref.read(fitnessApiProvider).fetchSeries(widget.def.key);
      });

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return _DetailScaffold(
      title: widget.def.label,
      child: FutureBuilder<FitnessSeries>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: t.accent));
          }
          if (snap.hasError || snap.data == null) return _errorView(t, _reload);
          final series = snap.data!;
          if (series.points.isEmpty) {
            return Center(
              child: Text('No recent data.', style: TextStyle(color: t.textMuted)),
            );
          }
          final values = series.points.map((p) => p.value).toList();
          final latest = values.last;
          final base = median(values.sublist(0, values.length - 1).isEmpty
              ? values
              : values.sublist(0, values.length - 1));
          final trend = trendFromSeries(values);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                t,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latest.toStringAsFixed(latest.truncateToDouble() == latest ? 0 : 1),
                            style: TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w700, color: t.textPrimary),
                          ),
                          Text('latest · ${series.points.last.date}',
                              style: TextStyle(fontSize: 12, color: t.textMuted)),
                        ],
                      ),
                    ),
                    if (trend != null) _trendChip(t, trend, base),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                t,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(t, 'LAST ${values.length} READINGS'),
                    const SizedBox(height: 12),
                    SizedBox(height: 200, child: _line(t, values, base)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _trendChip(HdTokens t, Trend trend, double? base) {
    final (icon, color, word) = switch (trend) {
      Trend.up => (Icons.arrow_upward, t.accent, 'above'),
      Trend.down => (Icons.arrow_downward, t.accent, 'below'),
      Trend.steady => (Icons.remove, t.textMuted, 'steady'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(icon, color: color, size: 22),
        Text('$word baseline', style: TextStyle(fontSize: 11, color: t.textMuted)),
        if (base != null)
          Text('7-day median ${base.toStringAsFixed(base.truncateToDouble() == base ? 0 : 1)}',
              style: TextStyle(fontSize: 11, color: t.textMuted)),
      ],
    );
  }

  Widget _line(HdTokens t, List<double> values, double? base) {
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: t.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: t.accent.withValues(alpha: 0.12)),
          ),
        ],
        extraLinesData: base == null
            ? const ExtraLinesData()
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: base,
                  color: t.textMuted.withValues(alpha: 0.6),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ]),
      ),
    );
  }
}

// ── Sleep detail ──────────────────────────────────────────────────────────────

const _stageColors = <String, Color>{
  'DEEP': Color(0xFF3949AB),
  'LIGHT': Color(0xFF42A5F5),
  'REM': Color(0xFF26A69A),
  'AWAKE': Color(0xFFFFB74D),
};
Color _stageColor(String s) => _stageColors[s] ?? const Color(0xFF9E9E9E);

String _fmtMins(int? m) {
  if (m == null) return '—';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

class SleepDetailScreen extends ConsumerStatefulWidget {
  const SleepDetailScreen({super.key});
  @override
  ConsumerState<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends ConsumerState<SleepDetailScreen> {
  late Future<FitnessSleep> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(fitnessApiProvider).fetchSleep();
  }

  void _reload() => setState(() => _future = ref.read(fitnessApiProvider).fetchSleep());

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return _DetailScaffold(
      title: 'Sleep',
      child: FutureBuilder<FitnessSleep>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: t.accent));
          }
          if (snap.hasError || snap.data == null) return _errorView(t, _reload);
          final nights = snap.data!.nights;
          if (nights.isEmpty) {
            return Center(child: Text('No recent nights.', style: TextStyle(color: t.textMuted)));
          }
          final latest = nights.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                t,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(t, 'LATEST NIGHT · ${latest.date}'),
                    const SizedBox(height: 8),
                    Text(_fmtMins(latest.minutesAsleep),
                        style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w700, color: t.textPrimary)),
                    Text('asleep', style: TextStyle(fontSize: 12, color: t.textMuted)),
                    const SizedBox(height: 14),
                    if (latest.hasStages) ...[
                      _hypnogram(latest),
                      const SizedBox(height: 14),
                      ...latest.stages.map((s) => _stageRow(t, s)),
                    ] else
                      Text('No stage data for this night.',
                          style: TextStyle(fontSize: 13, color: t.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                t,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(t, 'NIGHTLY TOTAL · LAST ${nights.length}'),
                    const SizedBox(height: 12),
                    SizedBox(height: 180, child: _nightlyBars(t, nights)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stageRow(HdTokens t, SleepStage s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(
                color: _stageColor(s.type), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text(s.type, style: TextStyle(fontSize: 13, color: t.textSecondary))),
            Text(_fmtMins(s.minutes), style: TextStyle(fontSize: 13, color: t.textPrimary)),
          ],
        ),
      );

  /// Proportional horizontal stage timeline for the night.
  Widget _hypnogram(SleepNight n) {
    int dur(HypnogramSegment seg) {
      final a = DateTime.tryParse(seg.start);
      final b = DateTime.tryParse(seg.end);
      if (a == null || b == null) return 0;
      return b.difference(a).inMinutes.clamp(0, 24 * 60);
    }

    final segs = n.hypnogram.where((s) => dur(s) > 0).toList();
    if (segs.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 14,
        child: Row(
          children: segs
              .map((s) => Expanded(flex: dur(s), child: Container(color: _stageColor(s.type))))
              .toList(),
        ),
      ),
    );
  }

  Widget _nightlyBars(HdTokens t, List<SleepNight> nights) {
    // Oldest → newest left-to-right.
    final ordered = nights.reversed.toList();
    final groups = [
      for (var i = 0; i < ordered.length; i++)
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: (ordered[i].minutesAsleep ?? 0) / 60.0,
            color: t.accent,
            width: 10,
            borderRadius: BorderRadius.circular(2),
          ),
        ]),
    ];
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: groups,
      ),
    );
  }
}
