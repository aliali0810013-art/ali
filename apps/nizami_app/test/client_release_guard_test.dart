import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/core/release/client_release.dart';

void main() {
  test('API requests advertise the pubspec release and platform', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^+\s]+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);

    expect(match, isNotNull);
    expect(ClientRelease.version, match!.group(1));
    expect(ClientRelease.buildNumber.toString(), match.group(2));
    expect(
      ClientRelease.addHeaders(const {'Accept': 'application/json'}, platform: 'web'),
      containsPair('X-NineSoft-Client-Build', match.group(2)),
    );
    expect(
      ClientRelease.addHeaders(const {}, platform: 'web'),
      containsPair('X-NineSoft-Client-Platform', 'web'),
    );
  });
}
