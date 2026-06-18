import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/providers.dart' show cacheBoxName;
import '../features/treatment/models.dart';
import '../flavor.dart';

const _patientNameKey =
    kCommunity ? 'community_patient_name' : 'patient_name';

String patientDisplayName() =>
    Hive.box(cacheBoxName).get(_patientNameKey) as String? ?? 'Patient';

String _patientName() => patientDisplayName();

Future<Uint8List> buildSessionPdf(
    Session session, List<Reading> readings) async {
  final pdf = pw.Document();
  final name = _patientName();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(name,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(session.date,
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('Session ${session.sessionId}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(),
        pw.SizedBox(height: 8),

        // Pre-treatment
        _sectionHeader('Pre-treatment'),
        _twoCol([
          ['Pre weight', '${session.preWeight ?? '-'} kg'],
          ['UF goal', '${session.ufGoal ?? '-'} L'],
          ['UF rate', '${session.ufRate ?? '-'} L/h'],
          ['BP', session.preBpSys != null ? '${session.preBpSys}/${session.preBpDia}' : '-'],
          ['Pulse', '${session.prePulse ?? '-'} bpm'],
        ]),
        pw.SizedBox(height: 12),

        // During session averages
        _sectionHeader('During Session'),
        if (readings.isNotEmpty)
          _twoCol(_readingAverages(readings))
        else
          pw.Text('No readings recorded during this session.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        pw.SizedBox(height: 12),

        // Post-treatment
        _sectionHeader('Post-treatment'),
        _twoCol([
          ['Post weight', '${session.postWeight ?? '-'} kg'],
          ['BP', session.postBpSys != null ? '${session.postBpSys}/${session.postBpDia}' : '-'],
          ['Pulse', '${session.postPulse ?? '-'} bpm'],
          ['Duration', session.durationMin != null ? '${session.durationMin} min' : '-'],
          ['Dialysate vol', session.dialysateVolume != null ? '${session.dialysateVolume} L' : '-'],
          ['Total UF', session.totalUf != null ? '${session.totalUf} L' : '-'],
          ['Blood processed', session.bloodProcessed != null ? '${session.bloodProcessed} L' : '-'],
        ]),

        if (session.comment?.isNotEmpty ?? false) ...[
          pw.SizedBox(height: 12),
          _sectionHeader('Comment'),
          pw.Text(session.comment!, style: const pw.TextStyle(fontSize: 10)),
        ],

        // Footer
        pw.SizedBox(height: 24),
        pw.Center(
          child: pw.Text(
            'Generated ${DateTime.now().toIso8601String().substring(0, 10)} · Home HD Tracker',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

Future<Uint8List> buildSummaryPdf(
    List<Session> sessions, List<Reading> readings, DateTime from, DateTime to) async {
  final pdf = pw.Document();
  final name = _patientName();

  final sorted = [...sessions]
    ..sort((a, b) => a.date.compareTo(b.date));
  final inRange = sorted.where((s) {
    final d = DateTime.tryParse(s.date);
    return d != null && !d.isBefore(from) && !d.isAfter(to);
  }).toList();

  // Build a map of sessionId -> avg BP string from readings
  final readingsBySession = <String, List<Reading>>{};
  for (final r in readings) {
    readingsBySession.putIfAbsent(r.sessionId, () => []).add(r);
  }
  String avgBp(String sessionId) {
    final rs = readingsBySession[sessionId] ?? [];
    final sysList = rs.map((r) => r.bpSys).whereType<int>().toList();
    final diaList = rs.map((r) => r.bpDia).whereType<int>().toList();
    if (sysList.isEmpty) return '-';
    final avgSys = (sysList.reduce((a, b) => a + b) / sysList.length).round();
    final avgDia = (diaList.reduce((a, b) => a + b) / diaList.length).round();
    return '$avgSys/$avgDia';
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      build: (ctx) => [
        pw.Text('Home HD — Session Summary',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text('$name  ·  ${from.toIso8601String().substring(0, 10)} to ${to.toIso8601String().substring(0, 10)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.Divider(),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [
            'Date',
            'Pre wt', 'UF goal', 'UF rate',
            'Pre BP sys', 'Pre BP dia', 'Pre pulse',
            'Post wt', 'Post BP sys', 'Post BP dia', 'Post pulse',
            'Avg BP',
            'Duration', 'Dial vol', 'Total UF', 'Blood proc',
          ],
          data: inRange.map((s) => [
            s.date,
            s.preWeight != null ? '${s.preWeight}' : '-',
            s.ufGoal != null ? '${s.ufGoal}' : '-',
            s.ufRate != null ? '${s.ufRate}' : '-',
            s.preBpSys != null ? '${s.preBpSys}' : '-',
            s.preBpDia != null ? '${s.preBpDia}' : '-',
            s.prePulse != null ? '${s.prePulse}' : '-',
            s.postWeight != null ? '${s.postWeight}' : '-',
            s.postBpSys != null ? '${s.postBpSys}' : '-',
            s.postBpDia != null ? '${s.postBpDia}' : '-',
            s.postPulse != null ? '${s.postPulse}' : '-',
            avgBp(s.sessionId),
            s.durationMin != null ? '${s.durationMin}' : '-',
            s.dialysateVolume != null ? '${s.dialysateVolume}' : '-',
            s.totalUf != null ? '${s.totalUf}' : '-',
            s.bloodProcessed != null ? '${s.bloodProcessed}' : '-',
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          cellPadding: const pw.EdgeInsets.all(3),
          cellAlignments: {
            for (var i = 0; i < 16; i++) i: pw.Alignment.center,
            0: pw.Alignment.centerLeft,
          },
        ),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Text(
            'Generated ${DateTime.now().toIso8601String().substring(0, 10)} · Home HD Tracker',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

// PDF helpers

pw.Widget _sectionHeader(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(title,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700)),
    );

List<List<String>> _readingAverages(List<Reading> readings) {
  int? _avg(int? Function(Reading) pick) {
    final vals = readings.map(pick).whereType<int>().toList();
    if (vals.isEmpty) return null;
    return (vals.reduce((a, b) => a + b) / vals.length).round();
  }

  final avgSys  = _avg((r) => r.bpSys);
  final avgDia  = _avg((r) => r.bpDia);
  final avgPulse = _avg((r) => r.pulse);
  final avgBf   = _avg((r) => r.bloodFlow);
  final avgVp   = _avg((r) => r.venousPressure);
  final avgAp   = _avg((r) => r.arterialPressure);

  return [
    ['Readings', '${readings.length}'],
    ['Avg BP', avgSys != null ? '$avgSys/$avgDia mmHg' : '-'],
    ['Avg pulse', avgPulse != null ? '$avgPulse bpm' : '-'],
    ['Avg blood flow', avgBf != null ? '$avgBf mL/min' : '-'],
    ['Avg VP', avgVp != null ? '$avgVp mmHg' : '-'],
    ['Avg AP', avgAp != null ? '$avgAp mmHg' : '-'],
  ];
}

pw.Widget _twoCol(List<List<String>> rows) {
  return pw.Wrap(
    spacing: 24,
    runSpacing: 4,
    children: rows
        .map((r) => pw.SizedBox(
              width: 200,
              child: pw.Row(children: [
                pw.SizedBox(
                  width: 100,
                  child: pw.Text(r[0],
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
                ),
                pw.Text(r[1], style: const pw.TextStyle(fontSize: 9)),
              ]),
            ))
        .toList(),
  );
}
