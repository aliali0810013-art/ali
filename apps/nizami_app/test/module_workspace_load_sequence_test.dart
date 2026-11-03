import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';

void main() {
  test('latest module load may update the visible records', () {
    expect(isCurrentModuleLoad(requestSequence: 4, activeSequence: 4), isTrue);
  });

  test('an older module load cannot replace a newer result', () {
    expect(isCurrentModuleLoad(requestSequence: 3, activeSequence: 4), isFalse);
  });
}
