import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/navigation/ninesoft_global_shortcuts.dart';

void main() {
  test('accounting function keys keep the agreed document shortcuts', () {
    expect(NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f2), 'sales');
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f3),
      'purchases.invoices',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f4),
      'sales.returns',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f5),
      'purchases.returns',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f6),
      'debts.receipts',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f7),
      'debts.payments',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f8),
      'accounts.journals',
    );
    expect(
      NineSoftGlobalShortcuts.moduleFor(LogicalKeyboardKey.f9),
      'accounts.statements',
    );
  });
}
