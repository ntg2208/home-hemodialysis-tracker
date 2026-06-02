import 'models.dart';

/// Port of lib/scorecard.ts, lib/queryFilter.ts, lib/cache.ts.

MarkerSummary summarize(String marker, List<BloodTestRow> rows) {
  final numeric = rows.where((r) => !r.qualitative).toList()
    ..sort((a, b) => a.datetime.compareTo(b.datetime));

  final latest = numeric.isNotEmpty ? numeric.last : null;
  final previous = numeric.length >= 2 ? numeric[numeric.length - 2] : null;

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

// --- query filter ---

bool _matchesFrom(String datetime, String from) =>
    datetime.substring(0, from.length.clamp(0, datetime.length)).compareTo(from) >= 0;

bool _matchesTo(String datetime, String to) =>
    datetime.substring(0, to.length.clamp(0, datetime.length)).compareTo(to) <= 0;

List<BloodTestRow> filterRows(
  List<BloodTestRow> rows, {
  List<String>? phase,
  String? from,
  String? to,
}) {
  return rows.where((r) {
    if (phase != null && phase.isNotEmpty && !phase.contains(r.phase)) {
      return false;
    }
    if (from != null && from.isNotEmpty && !_matchesFrom(r.datetime, from)) {
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
