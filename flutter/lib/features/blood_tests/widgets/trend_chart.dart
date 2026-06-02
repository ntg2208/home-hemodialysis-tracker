import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../chart_data.dart';
import '../markers.dart';
import '../models.dart';

// Phase boundaries (in-center → home-hd transitions), drawn as dashed verticals.
const _phaseBoundaries = ['2023-10-16', '2026-02-01'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Trend tab line chart. fl_chart port of the @nivo/line chart in
/// frontend/src/routes/BloodTests/components/TrendChart.tsx — reference-range
/// band, phase-boundary lines, per-point colouring by pre/post timing.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.marker, required this.rows});
  final String marker;
  final List<BloodTestRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final series = toSeries(rows);

    if (series.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No numeric readings for ${displayName(marker)} in this range.',
            style: TextStyle(color: t.textMuted)),
      );
    }

    final refRange = getReferenceRange(rows);
    final hasPrePost =
        series.any((d) => d.timing == 'pre' || d.timing == 'post');
    final last = series.last;

    var minX = series.first.dateMs;
    var maxX = series.last.dateMs;
    if (maxX == minX) {
      // Single-point (or single-date) series: pad the X span by ±1 day so
      // fl_chart's (x-minX)/(maxX-minX) mapping never divides by zero.
      const dayMs = 86400000.0;
      minX -= dayMs;
      maxX += dayMs;
    }
    final spanX = maxX - minX;

    var minY = series.map((d) => d.value).reduce((a, b) => a < b ? a : b);
    var maxY = series.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    if (refRange != null) {
      minY = minY < refRange.low ? minY : refRange.low;
      maxY = maxY > refRange.high ? maxY : refRange.high;
    }
    final padY = (maxY - minY) == 0 ? (maxY.abs() * 0.1 + 1) : (maxY - minY) * 0.12;
    minY -= padY;
    maxY += padY;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(displayName(marker),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
            const Spacer(),
            Text('${_n(last.value)} ${last.unit}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: pointColor(last.timing))),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: LineChart(LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: t.border.withValues(alpha: 0.4), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, meta) => Text(_n(v),
                        style: TextStyle(fontSize: 10, color: t.textMuted)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: spanX / 3,
                    getTitlesWidget: (v, meta) {
                      final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${_months[d.month - 1]} ${d.year % 100}',
                            style: TextStyle(fontSize: 10, color: t.textMuted)),
                      );
                    },
                  ),
                ),
              ),
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  if (refRange != null)
                    HorizontalRangeAnnotation(
                      y1: refRange.low,
                      y2: refRange.high,
                      color: lineColor.withValues(alpha: 0.08),
                    ),
                ],
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (refRange != null)
                    HorizontalLine(
                        y: refRange.low,
                        color: lineColor.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [4, 3]),
                  if (refRange != null)
                    HorizontalLine(
                        y: refRange.high,
                        color: lineColor.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [4, 3]),
                ],
                verticalLines: [
                  for (final b in _phaseBoundaries)
                    if (_inRange(b, minX, maxX))
                      VerticalLine(
                        x: DateTime.parse(b).millisecondsSinceEpoch.toDouble(),
                        color: t.textMuted,
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                ],
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => t.panel,
                  getTooltipItems: (spots) => spots.map((s) {
                    final d = series[s.spotIndex];
                    final flag = d.inRange == false
                        ? (d.refHigh != null && d.value > d.refHigh!
                            ? ' ↑ high'
                            : ' ↓ low')
                        : '';
                    final timing = d.timing == 'pre'
                        ? 'Pre'
                        : d.timing == 'post'
                            ? 'Post'
                            : '';
                    final sub = [timing, flag.trim()].where((x) => x.isNotEmpty).join(' · ');
                    return LineTooltipItem(
                      '${_n(d.value)} ${d.unit}${sub.isNotEmpty ? '\n$sub' : ''}',
                      TextStyle(
                          color: d.inRange == false ? t.danger : t.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final d in series) FlSpot(d.dateMs, d.value),
                  ],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: lineColor,
                  barWidth: 3,
                  belowBarData: BarAreaData(
                      show: true, color: lineColor.withValues(alpha: 0.12)),
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: pointColor(series[index].timing),
                      strokeWidth: 2,
                      strokeColor: t.bg,
                    ),
                  ),
                ),
              ],
            )),
          ),
          if (hasPrePost) ...[
            const SizedBox(height: 8),
            Row(children: [
              _legendDot(pointColor('pre'), 'Pre', t),
              const SizedBox(width: 16),
              _legendDot(pointColor('post'), 'Post', t),
            ]),
          ],
        ],
      ),
    );
  }

  bool _inRange(String dateStr, double minX, double maxX) {
    final x = DateTime.parse(dateStr).millisecondsSinceEpoch.toDouble();
    return x >= minX && x <= maxX;
  }

  Widget _legendDot(Color color, String label, HdTokens t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ],
      );
}

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
