// Pure helpers for "today vs personal baseline" — no absolute population
// cutoffs (the patient's HRV/RHR move with fluid status and the HD cycle).
// Arrows are purely directional (up/down/steady), not good/bad.

enum Trend { up, down, steady }

/// Median of [xs], or null if empty. Does not mutate the input.
double? median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Direction of [today] relative to [baseline], steady within [tolerancePct]
/// (default 5%). Steady when baseline is zero (no meaningful ratio).
Trend arrow(double today, double baseline, {double tolerancePct = 0.05}) {
  if (baseline == 0) return Trend.steady;
  final diff = today - baseline;
  if (diff.abs() / baseline < tolerancePct) return Trend.steady;
  return diff > 0 ? Trend.up : Trend.down;
}

/// Latest value vs the median of the trailing [window] points before it.
/// Null when there are fewer than 2 points.
Trend? trendFromSeries(List<double> values, {int window = 7}) {
  if (values.length < 2) return null;
  final priors = values.sublist(0, values.length - 1);
  final windowed = priors.length > window
      ? priors.sublist(priors.length - window)
      : priors;
  final base = median(windowed);
  if (base == null) return null;
  return arrow(values.last, base);
}
