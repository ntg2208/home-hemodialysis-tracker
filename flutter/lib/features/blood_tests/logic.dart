import 'models.dart';

/// Port of lib/scorecard.ts, lib/queryFilter.ts, lib/cache.ts.

MarkerSummary summarize(String marker, List<BloodTestRow> rows) {
  final numeric = rows.where((r) => !r.qualitative).toList()
    ..sort((a, b) => a.datetime.compareTo(b.datetime));

  final latest = numeric.isNotEmpty ? numeric.last : null;
  final previous = _findPrevious(numeric, latest);

  double? delta;
  if (latest != null && previous != null) {
    delta = double.parse((latest.value - previous.value).toStringAsFixed(4));
  }

  var status = MarkerStatus.unknown;
  if (latest != null && latest.refLow != null && latest.refHigh != null) {
    status = (latest.value >= latest.refLow! && latest.value <= latest.refHigh!)
        ? MarkerStatus.inRange
        : MarkerStatus.outOfRange;
  }

  return MarkerSummary(
      marker: marker,
      latest: latest,
      previous: previous,
      delta: delta,
      status: status);
}

/// Finds the comparison row for scorecard delta.
/// When [latest] has a timing (`pre`/`post`), returns the most recent earlier
/// row with the same timing — avoids comparing a post-draw value against a
/// pre-draw value for the 6 dialysis-cleared markers.
/// Falls back to second-to-last when [latest] has no timing.
BloodTestRow? _findPrevious(List<BloodTestRow> sorted, BloodTestRow? latest) {
  if (latest == null) return null;
  final timing = latest.timing;
  if (timing.isEmpty) {
    return sorted.length >= 2 ? sorted[sorted.length - 2] : null;
  }
  for (var i = sorted.length - 2; i >= 0; i--) {
    if (sorted[i].timing == timing) return sorted[i];
  }
  return null;
}

// --- query filter ---

bool _matchesFrom(String datetime, String from) =>
    datetime.substring(0, from.length.clamp(0, datetime.length)).compareTo(from) >= 0;

bool _matchesTo(String datetime, String to) =>
    datetime.substring(0, to.length.clamp(0, datetime.length)).compareTo(to) <= 0;

List<BloodTestRow> filterRows(
  List<BloodTestRow> rows, {
  List<String>? phase,
  String? rangePreset,
  String? from,
  String? to,
}) {
  // Resolve a range-preset pill like '6m' into a concrete YYYY-MM floor.
  String? effectiveFrom = from;
  if (effectiveFrom == null &&
      rangePreset != null &&
      rangePreset.isNotEmpty &&
      rangePreset != 'all') {
    effectiveFrom = rangeFrom(rangePreset);
  }

  return rows.where((r) {
    if (phase != null && phase.isNotEmpty && !phase.contains(r.phase)) {
      return false;
    }
    if (effectiveFrom != null &&
        effectiveFrom.isNotEmpty &&
        !_matchesFrom(r.datetime, effectiveFrom)) {
      return false;
    }
    if (to != null && to.isNotEmpty && !_matchesTo(r.datetime, to)) return false;
    return true;
  }).toList();
}

// --- cache / backfill ---

String _rowKey(BloodTestRow r) => '${r.labId}_${r.marker}';

/// Union keyed by lab_id+marker; incoming wins (picks up edits).
List<BloodTestRow> mergeRows(
    List<BloodTestRow> existing, List<BloodTestRow> incoming) {
  final byKey = <String, BloodTestRow>{};
  for (final r in existing) {
    byKey[_rowKey(r)] = r;
  }
  for (final r in incoming) {
    byKey[_rowKey(r)] = r;
  }
  return byKey.values.toList();
}

String _pad2(int n) => n.toString().padLeft(2, '0');

/// `YYYY-MM` six months before [now].
String sixMonthsAgo(DateTime now) {
  final d = DateTime(now.year, now.month - 6, 1);
  return '${d.year}-${_pad2(d.month)}';
}

/// `YYYY-MM` start of the window for a range preset key.
/// Presets: '3m', '6m', '1y'. Anything else returns '' (no floor).
String rangeFrom(String preset) {
  final now = DateTime.now();
  return switch (preset) {
    '3m' => () {
        final d = DateTime(now.year, now.month - 3, 1);
        return '${d.year}-${_pad2(d.month)}';
      }(),
    '6m' => sixMonthsAgo(now),
    '1y' => () {
        final d = DateTime(now.year - 1, now.month, 1);
        return '${d.year}-${_pad2(d.month)}';
      }(),
    _ => '',
  };
}

/// Is month [a] earlier than [b]? '' is open-ended (earliest possible).
bool earlierMonth(String a, String b) {
  if (a == b) return false;
  if (a == '') return true;
  if (b == '') return false;
  return a.compareTo(b) < 0;
}

/// The still-uncovered slice for a requested `from`, given the cache's earliest
/// covered month ([coveredFrom], null = empty cache). Returns null if nothing to fetch.
({String from, String? to})? computeFetchRange(
    String? coveredFrom, String requestedFrom) {
  if (coveredFrom == null) return (from: requestedFrom, to: null);
  if (!earlierMonth(requestedFrom, coveredFrom)) return null;
  return (from: requestedFrom, to: coveredFrom);
}
