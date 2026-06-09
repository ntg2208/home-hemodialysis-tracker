import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app/providers.dart' show cacheBoxName;
import '../features/treatment/models.dart';

const _patientNameKey = 'community_patient_name';

String _patientName() =>
    Hive.box(cacheBoxName).get(_patientNameKey) as String? ?? 'Patient';

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

        // Readings table
        if (readings.isNotEmpty) ...[
          _sectionHeader('Readings'),
          pw.TableHelper.fromTextArray(
            headers: ['Time', 'BP', 'Pulse', 'BF (mL/min)', 'VP', 'AP', 'Note'],
            data: readings.map((r) => [
              r.time,
              r.bpSys != null ? '${r.bpSys}/${r.bpDia}' : '-',
              '${r.pulse ?? '-'}',
              '${r.bloodFlow ?? '-'}',
              '${r.venousPressure ?? '-'}',
              '${r.arterialPressure ?? '-'}',
              r.note ?? '',
            ]).toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
          pw.SizedBox(height: 12),
        ],

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
    List<Session> sessions, DateTime from, DateTime to) async {
  final pdf = pw.Document();
  final name = _patientName();

  final sorted = [...sessions]
    ..sort((a, b) => a.date.compareTo(b.date));
  final inRange = sorted.where((s) {
    final d = DateTime.tryParse(s.date);
    return d != null && !d.isBefore(from) && !d.isAfter(to);
  }).toList();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text('Home HD — Session Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('$name  ·  ${from.toIso8601String().substring(0, 10)} to ${to.toIso8601String().substring(0, 10)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Duration', 'Pre BP', 'Post BP', 'UF goal', 'UF actual', 'Note'],
          data: inRange.map((s) => [
            s.date,
            s.durationMin != null ? '${s.durationMin} min' : '-',
            s.preBpSys != null ? '${s.preBpSys}/${s.preBpDia}' : '-',
            s.postBpSys != null ? '${s.postBpSys}/${s.postBpDia}' : '-',
            s.ufGoal != null ? '${s.ufGoal} L' : '-',
            s.totalUf != null ? '${s.totalUf} L' : '-',
            (s.comment ?? '').length > 30
                ? '${s.comment!.substring(0, 30)}...'
                : (s.comment ?? ''),
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          cellPadding: const pw.EdgeInsets.all(3),
        ),
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

// PDF helpers

pw.Widget _sectionHeader(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(title,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700)),
    );

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
