import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web browser tab uses the official NineSoft mark', () {
    final index = File('web/index.html').readAsStringSync();

    expect(
      index,
      contains(
        '<link rel="icon" type="image/png" sizes="192x192" '
        'href="icons/Icon-192.png"/>',
      ),
    );
    expect(File('web/icons/Icon-192.png').existsSync(), isTrue);
  });
}
