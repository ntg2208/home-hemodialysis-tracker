# Chat: Retrieval Tools + Voice Input — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three data-retrieval tools to the Gemini chat assistant (blood markers, sessions, out-of-range markers) and a mic button for speech-to-text input.

**Architecture:** `RetrieverTools` is a pure Dart class that filters pre-fetched in-memory data — no extra network calls. The existing tool-call loop in `GeminiChatResponder.reply()` gets a pre-check branch that routes retrieval names before falling through to `_parseCommand`. Voice input is a `SpeechToText` state machine in `_ChatSheetState` that feeds the existing `_send()` path.

**Tech Stack:** Flutter/Dart, `google_generative_ai` (already installed), `speech_to_text` (new), `flutter_test` for tests.

---

## File Map

| File | Status | Purpose |
|---|---|---|
| `lib/features/chat/retriever_tools.dart` | **Create** | Pure class: `getBloodMarkers`, `getSessions`, `getOutOfRangeMarkers` |
| `test/retriever_tools_test.dart` | **Create** | Unit tests for `RetrieverTools` |
| `lib/features/chat/chat_context.dart` | **Modify** | Add clinical hints section to `build()` |
| `lib/features/chat/gemini_client.dart` | **Modify** | 3 tool declarations, retriever construction, loop routing |
| `test/features/chat/gemini_responder_test.dart` | **Modify** | Routing test: retrieval names don't reach `_parseCommand` |
| `lib/features/chat/chat_sheet.dart` | **Modify** | `SpeechToText` state + mic button in `_inputRow` |
| `pubspec.yaml` | **Modify** | Add `speech_to_text: ^7.0.0` |
| `android/app/src/main/AndroidManifest.xml` | **Modify** | Add `RECORD_AUDIO` permission |
| `ios/Runner/Info.plist` | **Modify** | Add speech + mic usage descriptions |

---

## Task 1: `RetrieverTools` — `getBloodMarkers`

**Files:**
- Create: `flutter/lib/features/chat/retriever_tools.dart`
- Create: `flutter/test/retriever_tools_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `flutter/test/retriever_tools_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/features/chat/retriever_tools.dart';

BloodTestRow _btRow({
  required String marker,
  required String datetime,
  required double value,
  double? refLow,
  double? refHigh,
  String timing = '',
}) =>
    BloodTestRow(
      marker: marker,
      datetime: datetime,
      value: value,
      unit: 'mmol/L',
      refLow: refLow,
      refHigh: refHigh,
      timing: timing,
      note: '',
      source: '',
      labId: 'lab1',
      phase: 'home-hd',
      createdAt: '',
      qualitative: false,
    );

void main() {
  final fixedNow = DateTime(2026, 6, 10);

  group('getBloodMarkers', () {
    final rows = [
      _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      _btRow(marker: 'phosphate', datetime: '2026-04-15T14:00:00', value: 1.6, refLow: 0.8, refHigh: 1.5),
      _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      _btRow(marker: 'egfr',      datetime: '2026-05-18T14:00:00', value: 5.0),
    ];

    RetrieverTools makeRetriever() =>
        RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow);

    test('returns one result object per requested marker', () {
      final result = makeRetriever().getBloodMarkers(['phosphate', 'potassium'], 12);
      final results = result['results'] as List;
      expect(results.length, 2);
      expect((results[0] as Map)['marker'], 'phosphate');
      expect((results[1] as Map)['marker'], 'potassium');
    });

    test('rows are sorted newest-first', () {
      final result = makeRetriever().getBloodMarkers(['phosphate'], 12);
      final rows = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect((rows[0] as Map)['date'], '2026-05-18');
      expect((rows[1] as Map)['date'], '2026-04-15');
    });

    test('months_back excludes rows older than cutoff', () {
      // fixedNow = 2026-06-10, months_back=1 → cutoff 2026-05-10
      // April row (2026-04-15) is excluded; May row (2026-05-18) is included
      final result = makeRetriever().getBloodMarkers(['phosphate'], 1);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.length, 1);
      expect((rowList[0] as Map)['date'], '2026-05-18');
    });

    test('unknown marker returns empty rows array', () {
      final result = makeRetriever().getBloodMarkers(['unknown'], 12);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.isEmpty, true);
    });

    test('in_range is true when both ref bounds are null', () {
      final result = makeRetriever().getBloodMarkers(['egfr'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], true);
    });

    test('in_range is false when value exceeds refHigh', () {
      // phosphate 1.9 > refHigh 1.5
      final result = makeRetriever().getBloodMarkers(['phosphate'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], false);
    });

    test('in_range is false when value is below refLow', () {
      final lowRow = _btRow(marker: 'potassium', datetime: '2026-05-01T00:00:00', value: 2.0, refLow: 3.5, refHigh: 5.0);
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [lowRow], now: fixedNow);
      final result = retriever.getBloodMarkers(['potassium'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], false);
    });
  });
}
```

- [ ] **Step 2: Run to confirm tests fail**

```bash
cd flutter && flutter test test/retriever_tools_test.dart
```
Expected: compile error — `retriever_tools.dart` doesn't exist yet.

- [ ] **Step 3: Create `retriever_tools.dart` with `getBloodMarkers`**

Create `flutter/lib/features/chat/retriever_tools.dart`:

```dart
import '../blood_tests/models.dart';
import '../treatment/models.dart';

class RetrieverTools {
  RetrieverTools({
    required this.sessions,
    required this.readings,
    required this.bloodTestRows,
    DateTime? now,
  }) : _now = now ?? DateTime.now();

  final List<Session> sessions;
  final List<Reading> readings;
  final List<BloodTestRow> bloodTestRows;
  final DateTime _now;

  Map<String, dynamic> getBloodMarkers(List<String> markers, int monthsBack) {
    final cutoff = DateTime(_now.year, _now.month - monthsBack, _now.day);
    final cutoffStr = cutoff.toIso8601String().substring(0, 10);

    final results = markers.map((marker) {
      final markerRows = bloodTestRows
          .where((r) =>
              r.marker == marker &&
              r.datetime.substring(0, 10).compareTo(cutoffStr) >= 0)
          .toList()
        ..sort((a, b) => b.datetime.compareTo(a.datetime));

      return {
        'marker': marker,
        'rows': markerRows
            .map((r) => {
                  'date': r.datetime.substring(0, 10),
                  'value': r.value,
                  'unit': r.unit,
                  'ref_low': r.refLow,
                  'ref_high': r.refHigh,
                  'in_range': _inRange(r.value, r.refLow, r.refHigh),
                  'timing': r.timing,
                })
            .toList(),
      };
    }).toList();

    return {'results': results};
  }

  Map<String, dynamic> getSessions(
          {int? lastN, String? from, String? to, bool includeReadings = false}) =>
      {'sessions': <dynamic>[], 'count': 0};

  Map<String, dynamic> getOutOfRangeMarkers() =>
      {'draw_date': null, 'out_of_range': <dynamic>[], 'total_markers_checked': 0};

  bool _inRange(double value, double? refLow, double? refHigh) {
    if (refLow != null && value < refLow) return false;
    if (refHigh != null && value > refHigh) return false;
    return true;
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
flutter test test/retriever_tools_test.dart
```
Expected: all 7 `getBloodMarkers` tests pass.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/chat/retriever_tools.dart flutter/test/retriever_tools_test.dart
git commit -m "feat: RetrieverTools.getBloodMarkers with null-safe in_range logic"
```

---

## Task 2: `RetrieverTools` — `getSessions`

**Files:**
- Modify: `flutter/lib/features/chat/retriever_tools.dart`
- Modify: `flutter/test/retriever_tools_test.dart`

- [ ] **Step 1: Add failing tests to `retriever_tools_test.dart`**

Add this group after the existing `getBloodMarkers` group:

```dart
  // Add to imports at top of file:
  // import 'package:home_hd/features/treatment/models.dart';

  group('getSessions', () {
    Session _session(String date, {double? preW, double? postW,
        int? preSys, int? preDia, int? postSys, int? postDia,
        double? ufGoal, double? totalUf, int? durationMin}) =>
        Session(
          sessionId: date,
          date: date,
          preWeight: preW,
          postWeight: postW,
          preBpSys: preSys,
          preBpDia: preDia,
          postBpSys: postSys,
          postBpDia: postDia,
          ufGoal: ufGoal,
          totalUf: totalUf,
          durationMin: durationMin,
        );

    final sessions = [
      _session('2026-06-09', preW: 61.0, postW: 59.4, preSys: 117, preDia: 89,
          postSys: 112, postDia: 78, ufGoal: 2.0, totalUf: 1.6, durationMin: 255),
      _session('2026-06-07', preW: 60.5, postW: 59.0, preSys: 120, preDia: 80,
          postSys: 115, postDia: 75, ufGoal: 1.5, totalUf: 1.5, durationMin: 255),
      _session('2026-06-05'),
      _session('2026-06-03'),
      _session('2026-06-01'),
      _session('2026-05-30'),
      _session('2026-05-28'),
      _session('2026-05-26'),
    ];

    RetrieverTools makeRetriever() =>
        RetrieverTools(sessions: sessions, readings: [], bloodTestRows: [], now: fixedNow);

    test('last_n returns N most recent sessions, newest first', () {
      final result = makeRetriever().getSessions(lastN: 3);
      final list = result['sessions'] as List;
      expect(list.length, 3);
      expect((list[0] as Map)['date'], '2026-06-09');
      expect((list[1] as Map)['date'], '2026-06-07');
      expect(result['count'], 3);
    });

    test('default last_n is 7', () {
      final result = makeRetriever().getSessions();
      expect((result['sessions'] as List).length, 7);
    });

    test('last_n is clamped to 30', () {
      final result = makeRetriever().getSessions(lastN: 999);
      expect((result['sessions'] as List).length, sessions.length); // only 8 exist
    });

    test('from/to date range filters correctly', () {
      final result = makeRetriever().getSessions(from: '2026-06-01', to: '2026-06-07');
      final dates = (result['sessions'] as List).map((s) => (s as Map)['date']).toList();
      expect(dates, containsAll(['2026-06-01', '2026-06-05', '2026-06-07']));
      expect(dates, isNot(contains('2026-05-30')));
      expect(dates, isNot(contains('2026-06-09')));
    });

    test('from/to wins when both from/to and lastN provided', () {
      final result = makeRetriever().getSessions(lastN: 2, from: '2026-05-26', to: '2026-05-30');
      final list = result['sessions'] as List;
      expect(list.length, 2); // both May sessions
    });

    test('weight_removed is computed correctly', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['weight_removed'], closeTo(1.6, 0.01));
    });

    test('uf_achievement_pct is computed correctly', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['uf_achievement_pct'], 80); // 1.6/2.0 = 80%
    });

    test('pre_bp formatted as sys/dia string', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['pre_bp'], '117/89');
      expect(session['post_bp'], '112/78');
    });

    test('null bp/weight fields are null in output', () {
      final result = makeRetriever().getSessions(from: '2026-06-05', to: '2026-06-05');
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['pre_bp'], isNull);
      expect(session['pre_weight'], isNull);
    });

    test('include_readings: false gives empty readings array', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect((session['readings'] as List).isEmpty, true);
    });
  });
```

- [ ] **Step 2: Run to confirm new tests fail**

```bash
flutter test test/retriever_tools_test.dart --name "getSessions"
```
Expected: FAIL — `getSessions` returns empty list.

- [ ] **Step 3: Implement `getSessions` in `retriever_tools.dart`**

Replace the stub `getSessions` method:

```dart
  Map<String, dynamic> getSessions({
    int? lastN,
    String? from,
    String? to,
    bool includeReadings = false,
  }) {
    var sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));

    List<Session> filtered;
    if (from != null || to != null) {
      filtered = sorted.where((s) {
        if (from != null && s.date.compareTo(from) < 0) return false;
        if (to != null && s.date.compareTo(to) > 0) return false;
        return true;
      }).toList();
    } else {
      final n = (lastN ?? 7).clamp(1, 30);
      filtered = sorted.take(n).toList();
    }

    final sessionMaps = filtered.map((s) {
      final weightRemoved = (s.preWeight != null && s.postWeight != null)
          ? double.parse(((s.preWeight! - s.postWeight!) ).toStringAsFixed(1))
          : null;
      final ufAchievementPct =
          (s.ufGoal != null && s.ufGoal! > 0 && s.totalUf != null)
              ? ((s.totalUf! / s.ufGoal!) * 100).round()
              : null;

      final Map<String, dynamic> m = {
        'date': s.date,
        'session_id': s.sessionId,
        'pre_weight': s.preWeight,
        'post_weight': s.postWeight,
        'weight_removed': weightRemoved,
        'pre_bp': s.preBpSys != null ? '${s.preBpSys}/${s.preBpDia}' : null,
        'post_bp': s.postBpSys != null ? '${s.postBpSys}/${s.postBpDia}' : null,
        'pre_pulse': s.prePulse,
        'post_pulse': s.postPulse,
        'uf_goal': s.ufGoal,
        'total_uf': s.totalUf,
        'uf_achievement_pct': ufAchievementPct,
        'duration_min': s.durationMin,
        'comment': s.comment ?? '',
      };

      if (includeReadings) {
        final sessionReadings = readings
            .where((r) => r.sessionId == s.sessionId)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
        m['readings'] = sessionReadings
            .map((r) => {
                  'time': r.time,
                  'bp': r.bpSys != null ? '${r.bpSys}/${r.bpDia}' : null,
                  'pulse': r.pulse,
                  'blood_flow': r.bloodFlow,
                })
            .toList();
      } else {
        m['readings'] = <dynamic>[];
      }

      return m;
    }).toList();

    return {'sessions': sessionMaps, 'count': sessionMaps.length};
  }
```

- [ ] **Step 4: Run tests — expect pass**

```bash
flutter test test/retriever_tools_test.dart
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/chat/retriever_tools.dart flutter/test/retriever_tools_test.dart
git commit -m "feat: RetrieverTools.getSessions with date range and last_n"
```

---

## Task 3: `RetrieverTools` — `getOutOfRangeMarkers`

**Files:**
- Modify: `flutter/lib/features/chat/retriever_tools.dart`
- Modify: `flutter/test/retriever_tools_test.dart`

- [ ] **Step 1: Add failing tests**

Add this group to `retriever_tools_test.dart`:

```dart
  group('getOutOfRangeMarkers', () {
    test('returns empty result when no rows', () {
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [], now: fixedNow);
      final result = retriever.getOutOfRangeMarkers();
      expect(result['draw_date'], isNull);
      expect((result['out_of_range'] as List).isEmpty, true);
      expect(result['total_markers_checked'], 0);
    });

    test('identifies the most recent draw date', () {
      final rows = [
        _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
        _btRow(marker: 'potassium', datetime: '2026-04-15T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect(result['draw_date'], '2026-05-18');
    });

    test('flags marker with value above refHigh as high', () {
      final rows = [
        _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      final flagged = (result['out_of_range'] as List)[0] as Map;
      expect(flagged['marker'], 'phosphate');
      expect(flagged['direction'], 'high');
    });

    test('flags marker with value below refLow as low', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 2.0, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      final flagged = (result['out_of_range'] as List)[0] as Map;
      expect(flagged['direction'], 'low');
    });

    test('skips markers with both bounds null (e.g. intact_pth)', () {
      final rows = [
        _btRow(marker: 'intact_pth', datetime: '2026-05-18T14:00:00', value: 99.0),
        _btRow(marker: 'phosphate',  datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect(result['total_markers_checked'], 1); // intact_pth excluded
    });

    test('prefers pre row over post when both exist on same date', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 6.5,
            refLow: 3.5, refHigh: 5.0, timing: 'post'), // post-dialysis: low, in range
        _btRow(marker: 'potassium', datetime: '2026-05-18T12:00:00', value: 6.5,
            refLow: 3.5, refHigh: 5.0, timing: 'pre'),  // pre-dialysis: high, out of range
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      // pre row used: 6.5 > 5.0 → flagged high
      final flagged = result['out_of_range'] as List;
      expect(flagged.length, 1);
      expect((flagged[0] as Map)['direction'], 'high');
    });

    test('in-range markers are not included in out_of_range', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect((result['out_of_range'] as List).isEmpty, true);
      expect(result['total_markers_checked'], 1);
    });
  });
```

- [ ] **Step 2: Run to confirm new tests fail**

```bash
flutter test test/retriever_tools_test.dart --name "getOutOfRangeMarkers"
```
Expected: FAIL — stub returns empty.

- [ ] **Step 3: Implement `getOutOfRangeMarkers` in `retriever_tools.dart`**

Replace the stub `getOutOfRangeMarkers` method:

```dart
  Map<String, dynamic> getOutOfRangeMarkers() {
    if (bloodTestRows.isEmpty) {
      return {'draw_date': null, 'out_of_range': <dynamic>[], 'total_markers_checked': 0};
    }

    final latestDate = bloodTestRows
        .map((r) => r.datetime.substring(0, 10))
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

    // For each marker on the latest date, prefer 'pre' > 'post' > ''
    const timingPriority = {'pre': 2, 'post': 1, '': 0};
    final byMarker = <String, BloodTestRow>{};
    for (final row in bloodTestRows.where((r) => r.datetime.startsWith(latestDate))) {
      final existing = byMarker[row.marker];
      if (existing == null) {
        byMarker[row.marker] = row;
      } else {
        final newP = timingPriority[row.timing] ?? 0;
        final existP = timingPriority[existing.timing] ?? 0;
        if (newP > existP) byMarker[row.marker] = row;
      }
    }

    // Only markers with at least one bound defined
    final checkable = byMarker.values
        .where((r) => r.refLow != null || r.refHigh != null)
        .toList();

    final outOfRange = checkable
        .where((r) => !_inRange(r.value, r.refLow, r.refHigh))
        .map((r) => {
              'marker': r.marker,
              'value': r.value,
              'unit': r.unit,
              'ref_low': r.refLow,
              'ref_high': r.refHigh,
              'direction':
                  (r.refHigh != null && r.value > r.refHigh!) ? 'high' : 'low',
            })
        .toList();

    return {
      'draw_date': latestDate,
      'out_of_range': outOfRange,
      'total_markers_checked': checkable.length,
    };
  }
```

- [ ] **Step 4: Run all tests — expect pass**

```bash
flutter test test/retriever_tools_test.dart
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/chat/retriever_tools.dart flutter/test/retriever_tools_test.dart
git commit -m "feat: RetrieverTools.getOutOfRangeMarkers with pre/post dedup"
```

---

## Task 4: Clinical Hints in `ChatContextBuilder`

**Files:**
- Modify: `flutter/lib/features/chat/chat_context.dart`

No new tests — this is a string addition to an existing pure method already covered by `chat_context_test.dart`.

- [ ] **Step 1: Add clinical hints section to `build()` in `chat_context.dart`**

In `chat_context.dart`, find the `build()` method. The current template has `--- CURRENT STATE ---` followed by `--- INSTRUCTIONS ---`. Insert the new section between them:

```dart
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

--- CLINICAL HINTS ---
Use get_blood_markers when asked about symptoms or when deeper history is needed:
- Itching / skin irritation     → phosphate, adjusted_calcium
- Fatigue / breathlessness      → haemoglobin, ferritin, bicarbonate
- Muscle cramps / palpitations  → potassium, adjusted_calcium
- Swelling / fluid retention    → albumin, sodium
- Bone pain                     → phosphate, adjusted_calcium, intact_pth
- Poor clearance / uraemia      → urea, creatinine, egfr

Use get_sessions for questions about BP trends, UF patterns, or multi-session comparisons.
Use get_out_of_range_markers for "is anything flagged?" or general health-check questions.
When comparing months, fetch 2–3 months of data.

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
```

- [ ] **Step 2: Run existing context tests — expect pass**

```bash
flutter test test/chat_context_test.dart
```
Expected: all pass (the change adds a section; existing assertions still hold).

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/features/chat/chat_context.dart
git commit -m "feat: add clinical hints section to chat system prompt"
```

---

## Task 5: Tool Declarations + Loop Routing in `GeminiChatResponder`

**Files:**
- Modify: `flutter/lib/features/chat/gemini_client.dart`
- Modify: `flutter/test/features/chat/gemini_responder_test.dart`

- [ ] **Step 1: Write the routing test**

In `flutter/test/features/chat/gemini_responder_test.dart`, add this test after the existing tests:

```dart
  group('retrieval tool routing', () {
    test('get_blood_markers does not enqueue an AppCommand', () async {
      final dispatched = <AppCommand>[];
      final responder = _makeResponder(
        backend: _FakeBackend(
          streamResponses: [_toolResponse('get_blood_markers', {'markers': ['phosphate'], 'months_back': 2})],
          generateResponses: [_textResponse('Phosphate is elevated.')],
        ),
        dispatched: dispatched,
      );

      final reply = await responder.reply('why am I itching?', []).join();
      expect(reply, contains('Phosphate'));
      expect(dispatched, isEmpty); // no AppCommand — it's a data query, not a UI action
    });

    test('get_sessions does not enqueue an AppCommand', () async {
      final dispatched = <AppCommand>[];
      final responder = _makeResponder(
        backend: _FakeBackend(
          streamResponses: [_toolResponse('get_sessions', {'last_n': 7})],
          generateResponses: [_textResponse('Your last 7 sessions look fine.')],
        ),
        dispatched: dispatched,
      );

      final reply = await responder.reply('how were my sessions?', []).join();
      expect(dispatched, isEmpty);
    });

    test('get_out_of_range_markers does not enqueue an AppCommand', () async {
      final dispatched = <AppCommand>[];
      final responder = _makeResponder(
        backend: _FakeBackend(
          streamResponses: [_toolResponse('get_out_of_range_markers', {})],
          generateResponses: [_textResponse('Phosphate is flagged.')],
        ),
        dispatched: dispatched,
      );

      final reply = await responder.reply('anything flagged?', []).join();
      expect(dispatched, isEmpty);
    });
  });
```

Also add this helper near the top of the test file (alongside `_textResponse` and `_toolResponse`):

```dart
extension on Stream<String> {
  Future<String> join() async {
    final buf = StringBuffer();
    await for (final chunk in this) {
      buf.write(chunk);
    }
    return buf.toString();
  }
}
```

- [ ] **Step 2: Run to confirm routing tests fail**

```bash
flutter test test/features/chat/gemini_responder_test.dart --name "retrieval tool routing"
```
Expected: FAIL — unknown tool names fall through to `_parseCommand` which returns null → error response, or the test throws.

- [ ] **Step 3: Add tool declarations to `_tools` in `gemini_client.dart`**

In the `_tools` getter, add these three `FunctionDeclaration`s after the existing `end_session` declaration:

```dart
      FunctionDeclaration(
        'get_blood_markers',
        'Fetch historical blood test rows for specific markers. Use when asked about symptoms, trends, or comparisons across months.',
        Schema.object(properties: {
          'markers': Schema.array(
            items: Schema.string(description: 'Canonical marker name, e.g. phosphate, potassium, haemoglobin'),
            description: 'List of marker names to fetch',
          ),
          'months_back': Schema.integer(description: 'How many months back to look. Default 2, max 12.'),
        }, requiredProperties: ['markers']),
      ),
      FunctionDeclaration(
        'get_sessions',
        'Fetch dialysis session records. Use for BP trends, UF patterns, weight trends, or multi-session comparisons.',
        Schema.object(properties: {
          'last_n': Schema.integer(description: 'Last N sessions. Default 7, max 30. Mutually exclusive with from/to.'),
          'from': Schema.string(description: 'Start date YYYY-MM-DD (inclusive). Use with to.'),
          'to': Schema.string(description: 'End date YYYY-MM-DD (inclusive). Use with from.'),
          'include_readings': Schema.boolean(description: 'Include intra-session BP readings. Default false. Only use for last_n ≤ 5.'),
        }),
      ),
      FunctionDeclaration(
        'get_out_of_range_markers',
        'Returns all markers from the most recent blood draw that are outside their reference range. Use for general health checks or "is anything flagged?" questions.',
        Schema.object(properties: {}),
      ),
```

- [ ] **Step 4: Add `RetrieverTools` construction and loop routing in `gemini_client.dart`**

`retriever` must be declared before the `if (_testBackend != null)` branch because the tool-call loop runs after the branch and uses it on both paths. On the test path it holds empty data (the test verifies routing, not data content).

Replace the opening of `reply()` up to (and including) the `if/else` branch declaration like so — keeping all existing logic inside the `else`, just adding the `late` declaration and the test-path assignment:

```dart
    late final RetrieverTools retriever;

    final GeminiBackend backend;

    if (_testBackend != null) {
      retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: []);
      backend = _testBackend;
    } else {
      // ... existing production fetch code unchanged ...
      retriever = RetrieverTools(
        sessions: [...treatmentData.sessions],
        readings: treatmentData.readings,
        bloodTestRows: btCache.rows,
      );
      backend = _RealBackend(GenerativeModel(...));
    }
```

Then, in the tool-call loop (the `for` loop that processes `response.functionCalls`), replace the existing per-call block:

```dart
        for (final call in response.functionCalls) {
          final cmd = _parseCommand(call);
          Map<String, dynamic> result;

          if (cmd == null) {
            result = {'error': 'Unknown tool: ${call.name}'};
          } else {
            ...
          }
          functionResponses.add(Content.functionResponse(call.name, result));
        }
```

with:

```dart
        for (final call in response.functionCalls) {
          Map<String, dynamic> result;

          // Retrieval tools: return data, no AppCommand enqueued.
          if (call.name == 'get_blood_markers') {
            final markers =
                ((call.args['markers'] as List?) ?? []).cast<String>();
            final months = (call.args['months_back'] as num?)?.toInt() ?? 2;
            result = retriever.getBloodMarkers(markers, months);
          } else if (call.name == 'get_sessions') {
            result = retriever.getSessions(
              lastN: (call.args['last_n'] as num?)?.toInt(),
              from: call.args['from'] as String?,
              to: call.args['to'] as String?,
              includeReadings:
                  call.args['include_readings'] as bool? ?? false,
            );
          } else if (call.name == 'get_out_of_range_markers') {
            result = retriever.getOutOfRangeMarkers();
          } else {
            // Action tools: validate state, enqueue command.
            final cmd = _parseCommand(call);
            if (cmd == null) {
              result = {'error': 'Unknown tool: ${call.name}'};
            } else {
              final stateError =
                  validateCommand(cmd, _screenContext.treatmentState);
              final valueError =
                  stateError == null ? validateValues(cmd) : null;
              final error = stateError ?? valueError;
              if (error != null) {
                result = {'error': error};
              } else {
                commandsToRun.add(cmd);
                result = {'ok': true};
              }
            }
          }

          functionResponses.add(Content.functionResponse(call.name, result));
        }
```

Also add the import at the top of `gemini_client.dart`:

```dart
import 'retriever_tools.dart';
```

On the test path, `retriever` holds empty lists — that's intentional. The routing tests only verify that no `AppCommand` is enqueued; they don't assert on the data returned to the model.

- [ ] **Step 5: Run all tests — expect pass**

```bash
flutter test
```
Expected: all tests pass, no analyse errors.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/chat/gemini_client.dart flutter/test/features/chat/gemini_responder_test.dart
git commit -m "feat: wire retrieval tools into GeminiChatResponder loop"
```

---

## Task 6: Platform Permissions + Package

**Files:**
- Modify: `flutter/pubspec.yaml`
- Modify: `flutter/android/app/src/main/AndroidManifest.xml`
- Modify: `flutter/ios/Runner/Info.plist`

- [ ] **Step 1: Add `speech_to_text` to `pubspec.yaml`**

In `flutter/pubspec.yaml`, add under `dependencies:` (after `csv: ^6.0.0`):

```yaml
  speech_to_text: ^7.0.0
```

- [ ] **Step 2: Fetch the package**

```bash
cd flutter && flutter pub get
```
Expected: `speech_to_text` appears in `.dart_tool/package_config.json`, no errors.

- [ ] **Step 3: Add Android permission**

In `flutter/android/app/src/main/AndroidManifest.xml`, add after the existing `POST_NOTIFICATIONS` line:

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

- [ ] **Step 4: Add iOS usage descriptions**

In `flutter/ios/Runner/Info.plist`, add before the closing `</dict>` tag:

```xml
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Voice input for the HD assistant</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Microphone access for voice input to the HD assistant</string>
```

- [ ] **Step 5: Verify analyse still clean**

```bash
flutter analyze
```
Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add flutter/pubspec.yaml flutter/pubspec.lock flutter/android/app/src/main/AndroidManifest.xml flutter/ios/Runner/Info.plist
git commit -m "chore: add speech_to_text package and platform permissions"
```

---

## Task 7: Mic Button + STT in `ChatSheet`

**Files:**
- Modify: `flutter/lib/features/chat/chat_sheet.dart`

- [ ] **Step 1: Add `speech_to_text` import and STT state to `_ChatSheetState`**

At the top of `chat_sheet.dart`, add:

```dart
import 'package:speech_to_text/speech_to_text.dart';
```

In `_ChatSheetState`, add these fields after `final _focus = FocusNode();`:

```dart
  final _stt = SpeechToText();
  bool _sttAvailable = false;
  bool _listening = false;
```

- [ ] **Step 2: Initialise STT in `initState` and dispose in `dispose`**

At the end of `initState()`, after the existing `addPostFrameCallback` block:

```dart
    _initStt();
```

Add the new method to `_ChatSheetState`:

```dart
  Future<void> _initStt() async {
    final available = await _stt.initialize();
    if (mounted) setState(() => _sttAvailable = available);
  }
```

In `dispose()`, add before `super.dispose()`:

```dart
    if (_listening) _stt.stop();
    _stt.cancel();
```

- [ ] **Step 3: Add `_toggleListening` method**

Add to `_ChatSheetState`:

```dart
  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      if (_input.text.trim().isNotEmpty) _send(_input.text);
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (result) {
        setState(() => _input.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          if (_input.text.trim().isNotEmpty) _send(_input.text);
        }
      },
      pauseFor: const Duration(seconds: 2),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }
```

- [ ] **Step 4: Add `_MicButton` widget to the bottom of `chat_sheet.dart`**

Add after `_KbUpdateChip`:

```dart
class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap});
  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Material(
      color: listening ? Colors.red.shade400 : t.panel,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            listening ? Icons.mic : Icons.mic_none,
            size: 20,
            color: listening ? Colors.white : t.textSecondary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the mic button into `_inputRow`**

Replace the `_inputRow` method in `_ChatSheetState`:

```dart
  Widget _inputRow(HdTokens t, ChatState state) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: state.sending ? null : _send,
            decoration: InputDecoration(
              hintText: _listening ? 'Listening…' : 'Message',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_sttAvailable)
          _MicButton(listening: _listening, onTap: _toggleListening),
        if (_sttAvailable) const SizedBox(width: 8),
        _SendButton(
          enabled: !state.sending,
          onTap: () => _send(_input.text),
        ),
      ]),
    );
  }
```

- [ ] **Step 6: Run all tests and analyse**

```bash
flutter test && flutter analyze
```
Expected: all tests pass, no analyse errors.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/chat/chat_sheet.dart
git commit -m "feat: add STT mic button to chat input"
```

---

## Task 8: Final check

- [ ] **Step 1: Run full test suite**

```bash
cd flutter && flutter test
```
Expected: all tests pass.

- [ ] **Step 2: Run analyse**

```bash
flutter analyze
```
Expected: no errors or warnings introduced by this work.

- [ ] **Step 3: Build web to confirm no compile errors**

```bash
flutter build web --no-tree-shake-icons
```
Expected: build succeeds.

- [ ] **Step 4: Commit if any cleanup was needed, otherwise note as clean**

```bash
git log --oneline -6
```
Expected: 6 commits from this feature visible.
