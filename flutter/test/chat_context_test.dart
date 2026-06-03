import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/chat_context.dart';
import 'package:home_hd/features/kb/kb_store.dart';

void main() {
  final now = DateTime(2026, 6, 3);
  final kbEntry = KbEntry(
    id: '1',
    title: 'Dry Weight',
    content: '59 kg — target post-dialysis weight',
    source: 'user',
    createdAt: now,
    updatedAt: now,
  );

  group('ChatContextBuilder', () {
    test('empty KB shows (none yet)', () {
      final prompt = ChatContextBuilder(
        kbEntries: [],
        lastSession: null,
        lastReadings: [],
        bloodTestRows: [],
        fitnessSummary: null,
        inventory: null,
      ).build();
      expect(prompt, contains('(none yet)'));
      expect(prompt, contains('PATIENT KNOWLEDGE'));
      expect(prompt, contains('CURRENT STATE'));
      expect(prompt, contains('INSTRUCTIONS'));
    });

    test('KB entries appear in prompt', () {
      final prompt = ChatContextBuilder(
        kbEntries: [kbEntry],
        lastSession: null,
        lastReadings: [],
        bloodTestRows: [],
        fitnessSummary: null,
        inventory: null,
      ).build();
      expect(prompt, contains('Dry Weight: 59 kg'));
    });

    test('content truncated at 100 chars', () {
      final longEntry = KbEntry(
        id: '2',
        title: 'Notes',
        content: 'A' * 150,
        source: 'user',
        createdAt: now,
        updatedAt: now,
      );
      final prompt = ChatContextBuilder(
        kbEntries: [longEntry],
        lastSession: null,
        lastReadings: [],
        bloodTestRows: [],
        fitnessSummary: null,
        inventory: null,
      ).build();
      expect(prompt, contains('…'));
      expect(prompt, isNot(contains('A' * 150)));
    });

    test('KB_UPDATE instruction is in prompt', () {
      final prompt = ChatContextBuilder(
        kbEntries: [],
        lastSession: null,
        lastReadings: [],
        bloodTestRows: [],
        fitnessSummary: null,
        inventory: null,
      ).build();
      expect(prompt, contains('KB_UPDATE'));
    });
  });
}
