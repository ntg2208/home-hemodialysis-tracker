// Port of frontend/src/routes/Treatment/sessionId.ts.

/// Next session id for [date], handling same-day collisions (`-2`, `-3`, max+1).
String nextSessionId(String date, List<String> existingIds) {
  final sameDay =
      existingIds.where((id) => id == date || id.startsWith('$date-')).toList();
  if (sameDay.isEmpty) return date;

  var maxN = 1;
  for (final id in sameDay) {
    if (id == date) {
      maxN = maxN > 1 ? maxN : 1;
    } else {
      final suffix = id.substring(date.length + 1);
      final n = int.tryParse(suffix);
      if (n != null) maxN = n > maxN ? n : maxN;
    }
  }
  return '$date-${maxN + 1}';
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String todayIso([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';
}

String nowHHMM([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${_pad2(d.hour)}:${_pad2(d.minute)}';
}
