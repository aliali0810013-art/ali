import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../modules/module_workspace_page.dart';

class NineSoftGlobalShortcuts {
  const NineSoftGlobalShortcuts._();

  static final _moduleByKey = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.f2: 'sales',
    LogicalKeyboardKey.f3: 'purchases.invoices',
    LogicalKeyboardKey.f4: 'sales.returns',
    LogicalKeyboardKey.f5: 'purchases.returns',
    LogicalKeyboardKey.f6: 'debts.receipts',
    LogicalKeyboardKey.f7: 'debts.payments',
    LogicalKeyboardKey.f8: 'accounts.journals',
    LogicalKeyboardKey.f9: 'accounts.statements',
  };

  static String? moduleFor(LogicalKeyboardKey key) => _moduleByKey[key];

  static Iterable<MapEntry<LogicalKeyboardKey, String>> get entries =>
      _moduleByKey.entries;

  static ModuleDefinition? definitionFor(String key) => switch (key) {
    'purchases.invoices' => const ModuleDefinition(
      key: 'purchases.invoices',
      title: 'فواتير المشتريات',
      entityLabel: 'فاتورة شراء',
      actionLabel: 'فاتورة شراء جديدة',
      icon: Icons.shopping_cart_checkout_rounded,
      color: Color(0xFF137BE0),
    ),
    'purchases.returns' => const ModuleDefinition(
      key: 'purchases.returns',
      title: 'مرتجعات المشتريات',
      entityLabel: 'مرتجع شراء',
      actionLabel: 'مرتجع شراء جديد',
      icon: Icons.assignment_return_rounded,
      color: Color(0xFFFF7A45),
    ),
    'debts.receipts' => const ModuleDefinition(
      key: 'debts.receipts',
      title: 'سندات القبض',
      entityLabel: 'سند قبض',
      actionLabel: 'سند قبض جديد',
      icon: Icons.south_west_rounded,
      color: Color(0xFF00A88F),
    ),
    'debts.payments' => const ModuleDefinition(
      key: 'debts.payments',
      title: 'سندات الصرف',
      entityLabel: 'سند صرف',
      actionLabel: 'سند صرف جديد',
      icon: Icons.north_east_rounded,
      color: Color(0xFFE65353),
    ),
    'accounts.journals' => const ModuleDefinition(
      key: 'accounts.journals',
      title: 'القيد البسيط',
      entityLabel: 'قيد يومية',
      actionLabel: 'قيد بسيط جديد',
      icon: Icons.library_books_rounded,
      color: Color(0xFFE74B55),
    ),
    'accounts.statements' => const ModuleDefinition(
      key: 'accounts.statements',
      title: 'كشف الحساب',
      entityLabel: 'كشف حساب',
      actionLabel: 'فتح كشف حساب',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF7134E3),
    ),
    _ => null,
  };
}
