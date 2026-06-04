// flutter/lib/features/chat/chat_context.dart
import '../blood_tests/models.dart';
import '../inventory/inventory_models.dart';
import '../kb/kb_store.dart';
import '../treatment/models.dart';
import 'screen_context.dart' show AppScreenContext;

/// Pure class — takes pre-fetched data, returns the system prompt string.
/// No async I/O: easy to unit test with fixture data.
class ChatContextBuilder {
  const ChatContextBuilder({
    required this.kbEntries,
    required this.lastSession,
    required this.lastReadings,
    required this.bloodTestRows,
    required this.fitnessSummary,
    required this.inventory,
    required this.appState,
  });

  final List<KbEntry> kbEntries;
  final Session? lastSession;
  final List<Reading> lastReadings;
  final List<BloodTestRow> bloodTestRows;
  final Map<String, dynamic>? fitnessSummary;
  final InventoryResponse? inventory;
  final AppScreenContext appState;

  String build() {
    return '''
You are a personal health assistant for a home hemodialysis patient.

--- PATIENT KNOWLEDGE (user-curated) ---
${_kbSection()}

--- CURRENT STATE (auto-assembled) ---
${_sessionLine()}
${_bloodsLine()}
${_fitnessLine()}
${_inventoryLine()}

--- INSTRUCTIONS ---
- Answer concisely. Use markdown for tables and lists.
- When the user tells you something worth remembering (a new dry weight, a medication change, a symptom note), end your response with a KB update in this EXACT format on its own line: <!--KB_UPDATE {"title":"Entry Title","content":"Entry content"}-->
- For blood test values, include reference ranges when you know them.
- HRV values are relative to the patient's personal baseline — do not apply absolute population cutoffs.
- If asked about something not in the current state, say so — don't guess.
- Do not give medical advice. Summarise trends and flag patterns, but always defer to the clinical team.

${appState.toPromptSection()}
'''
        .trim();
  }

  String _kbSection() {
    if (kbEntries.isEmpty) return '(none yet)';
    return kbEntries.map((e) {
      final body = e.content.length > 100
          ? '${e.content.substring(0, 100)}…'
          : e.content;
      return '${e.title}: $body';
    }).join('\n');
  }

  String _sessionLine() {
    final s = lastSession;
    if (s == null) return 'Last dialysis: no sessions recorded.';
    final preBp =
        s.preBpSys != null ? '${s.preBpSys}/${s.preBpDia}' : 'unknown';
    final postBp =
        s.postBpSys != null ? '${s.postBpSys}/${s.postBpDia}' : 'pending';
    final uf = s.totalUf != null
        ? '${s.totalUf}L'
        : s.ufGoal != null
            ? '${s.ufGoal}L goal'
            : 'unknown';
    final dur = s.durationMin != null ? ', ${s.durationMin}min' : '';
    final prePulse = s.prePulse != null ? ' HR${s.prePulse}' : '';
    final postPulse = s.postPulse != null ? ' HR${s.postPulse}' : '';
    return 'Last dialysis: ${s.date}, pre $preBp$prePulse, post $postBp$postPulse, UF $uf$dur.';
  }

  String _bloodsLine() {
    if (bloodTestRows.isEmpty) return 'Latest bloods: none cached.';
    const keyMarkers = [
      'creatinine', 'potassium', 'haemoglobin', 'urea',
      'phosphate', 'albumin', 'adjusted_calcium', 'bicarbonate',
    ];
    final sorted = [...bloodTestRows]
      ..sort((a, b) => b.datetime.compareTo(a.datetime));
    final latestDate = sorted.first.datetime.substring(0, 10);
    final relevant = sorted
        .where((r) =>
            r.datetime.startsWith(latestDate) && keyMarkers.contains(r.marker))
        .toList();
    if (relevant.isEmpty) return 'Latest bloods ($latestDate): no key markers found.';
    final parts = relevant.map((r) {
      final ref = r.refLow != null && r.refHigh != null
          ? ' (ref ${r.refLow}–${r.refHigh} ${r.unit})'
          : '';
      return '${r.marker} ${r.value}${r.unit.isNotEmpty ? " ${r.unit}" : ""}$ref';
    }).join(', ');
    return 'Latest bloods ($latestDate): $parts.';
  }

  String _fitnessLine() {
    final summary = fitnessSummary;
    if (summary == null) return '';
    final types = summary['types'];
    if (types is! List) return '';
    final parts = <String>[];
    for (final t in types) {
      if (t is! Map) continue;
      final type = t['type'] as String?;
      final latest = t['latest'];
      if (latest is! Map) continue;
      if (type == 'daily-resting-heart-rate') {
        final bpm = latest['beatsPerMinute'];
        if (bpm != null) parts.add('Resting HR: $bpm bpm');
      } else if (type == 'daily-heart-rate-variability') {
        final rmssd = latest['averageHeartRateVariabilityMilliseconds'];
        if (rmssd != null) parts.add('HRV (RMSSD): ${rmssd}ms');
      } else if (type == 'sleep') {
        final summaryBlock = latest['summary'];
        if (summaryBlock is Map) {
          final mins =
              int.tryParse(summaryBlock['minutesAsleep']?.toString() ?? '') ??
                  0;
          if (mins > 0) {
            parts.add('Sleep: ${mins ~/ 60}h ${mins % 60}m');
          }
          final stages = summaryBlock['stagesSummary'];
          if (stages is List) {
            for (final stage in stages) {
              if (stage is Map && stage['type'] == 'DEEP') {
                final deepMins =
                    int.tryParse(stage['minutes']?.toString() ?? '') ?? 0;
                if (deepMins > 0) parts.add('Deep sleep: ${deepMins}min');
              }
            }
          }
        }
      }
    }
    return parts.isEmpty ? '' : parts.join('. ') + '.';
  }

  String _inventoryLine() {
    final inv = inventory;
    if (inv == null) return '';
    const critical = ['SAK-303', 'CAR-172-C', 'PAK-001', 'UK00000880'];
    final parts = critical
        .where((code) => inv.stock.containsKey(code))
        .map((code) => '$code: ${inv.stock[code]} boxes')
        .toList();
    if (parts.isEmpty) return '';
    final delivery = inv.cycle?.deliveryDate ?? '';
    return 'Inventory: ${parts.join(", ")}.'
        '${delivery.isNotEmpty ? " Next delivery: $delivery." : ""}';
  }
}
