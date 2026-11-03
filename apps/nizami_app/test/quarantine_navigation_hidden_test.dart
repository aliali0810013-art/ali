import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/dashboard/dashboard_page.dart';
import 'package:nizami/src/features/navigation/ninesoft_desktop_navigation.dart';

void main() {
  test('manual quarantine review is not exposed as an application section', () {
    expect(
      DashboardPage.modules.map((module) => module.key),
      isNot(contains('quarantine_review')),
    );
    expect(
      NineSoftDesktopNavigation.sections.map((section) => section.key),
      isNot(contains('quarantine_review')),
    );
  });
}
