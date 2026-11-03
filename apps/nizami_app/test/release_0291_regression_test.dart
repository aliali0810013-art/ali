import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/wasl/wasl_api.dart';
import 'package:nizami/src/theme/nizami_theme.dart';

void main() {
  test('WASL integration is available in normal release builds', () {
    expect(WaslApi.enabled, isTrue);
  });

  test('application text styles force Latin digits under Arabic UI', () {
    final theme = NizamiTheme.light;
    final styles = <TextStyle?>[
      theme.textTheme.displayLarge,
      theme.textTheme.headlineMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.labelLarge,
    ];

    for (final style in styles) {
      expect(style?.locale, const Locale('en'));
      expect(
        style?.fontFeatures?.map((feature) => feature.feature).toSet(),
        containsAll(<String>['lnum', 'tnum']),
      );
    }
  });
}
