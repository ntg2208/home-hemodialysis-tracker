import 'package:flutter/material.dart';

import 'fitness_api.dart';

/// One insight tile in the Fitness grid. Adding a future metric (Steps, SpO₂…)
/// is one entry here plus a detail builder — no screen changes.
class MetricTileDef {
  const MetricTileDef({
    required this.key,
    required this.label,
    required this.icon,
    this.isSleep = false,
  });

  final String key; // matches the summary type / series type
  final String label;
  final IconData icon;
  final bool isSleep; // sleep gets the stage detail; others get a trend line
}

/// First version: Sleep, HRV, Resting HR, Respiratory rate (in display order).
const fitnessTiles = <MetricTileDef>[
  MetricTileDef(key: 'sleep', label: 'Sleep', icon: Icons.bedtime_outlined, isSleep: true),
  MetricTileDef(key: 'daily-heart-rate-variability', label: 'HRV', icon: Icons.monitor_heart_outlined),
  MetricTileDef(key: 'daily-resting-heart-rate', label: 'Resting HR', icon: Icons.favorite_outline),
  MetricTileDef(key: 'respiratory-rate-sleep-summary', label: 'Respiratory', icon: Icons.air),
];

typedef Headline = ({String value, String unit, String sub});

/// Tile headline from the (already-fetched) summary: the latest value + unit,
/// with the reading date as the sub-line. Em dash when there's no reading.
Headline tileHeadline(FitnessSummary s, MetricTileDef def) {
  FitnessType? ft;
  for (final x in s.types) {
    if (x.type == def.key) {
      ft = x;
      break;
    }
  }
  final l = ft?.latest;
  if (l == null) return (value: '—', unit: '', sub: 'no recent data');
  return (value: l.value, unit: l.unit, sub: l.at);
}
