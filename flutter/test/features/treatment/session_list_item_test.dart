import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/widgets/session_list_item.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: hdLightTheme(), home: Scaffold(body: w));

void main() {
  testWidgets('shows chat icon and preview when comment is set',
      (tester) async {
    await tester.pumpWidget(_app(const SessionListItem(
      session: Session(
        sessionId: '2026-06-01',
        date: '2026-06-01',
        comment: 'Felt fine throughout',
      ),
    )));
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.textContaining('Felt fine throughout'), findsOneWidget);
  });

  testWidgets('shows no indicator when comment is null', (tester) async {
    await tester.pumpWidget(_app(const SessionListItem(
      session: Session(sessionId: '2026-06-01', date: '2026-06-01'),
    )));
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });

  testWidgets('shows no indicator when comment is empty string',
      (tester) async {
    await tester.pumpWidget(_app(const SessionListItem(
      session: Session(
          sessionId: '2026-06-01', date: '2026-06-01', comment: ''),
    )));
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });

  testWidgets('truncates comments longer than 50 chars', (tester) async {
    const longComment =
        'This is a very long comment that exceeds fifty characters in length';
    await tester.pumpWidget(_app(const SessionListItem(
      session: Session(
        sessionId: '2026-06-01',
        date: '2026-06-01',
        comment: longComment,
      ),
    )));
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(
        find.textContaining('This is a very long comment that exceeds fifty'),
        findsOneWidget);
    expect(find.text(longComment), findsNothing);
  });
}
