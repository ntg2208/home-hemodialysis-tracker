import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/chat_controller.dart';

void main() {
  group('KB update parsing', () {
    test('parses valid KB_UPDATE comment', () {
      const text =
          'Your dry weight has been updated.\n<!--KB_UPDATE {"title":"Dry Weight","content":"58.5 kg"}-->';
      final result = parseKbUpdate(text);
      expect(result, isNotNull);
      expect(result!.title, 'Dry Weight');
      expect(result.content, '58.5 kg');
    });

    test('returns null when no KB_UPDATE comment', () {
      expect(parseKbUpdate('Just a normal reply.'), isNull);
    });

    test('returns null when JSON is malformed', () {
      expect(parseKbUpdate('<!--KB_UPDATE {broken}-->'), isNull);
    });

    test('strips the comment from visible text', () {
      const raw =
          'Updated!\n<!--KB_UPDATE {"title":"T","content":"C"}-->';
      const expected = 'Updated!';
      expect(stripKbUpdate(raw), expected);
    });
  });
}
