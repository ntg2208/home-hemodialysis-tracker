import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/app/theme.dart';

void main() {
  test('light and dark themes attach the matching HdTokens extension', () {
    final light = hdLightTheme();
    final dark = hdDarkTheme();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);

    final lightTokens = light.extension<HdTokens>();
    final darkTokens = dark.extension<HdTokens>();

    expect(lightTokens, isNotNull);
    expect(darkTokens, isNotNull);
    // Token sets differ between modes (e.g. background flips near-white ↔ dark slate).
    expect(lightTokens!.bg, isNot(equals(darkTokens!.bg)));
    expect(lightTokens.accent, isNot(equals(darkTokens.accent)));
  });

  test('buttons use a pill (StadiumBorder) shape in both themes', () {
    for (final theme in [hdLightTheme(), hdDarkTheme()]) {
      final shape = theme.elevatedButtonTheme.style
          ?.shape
          ?.resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>());
    }
  });
}
