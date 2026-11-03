enum NineSoftModuleGroup {
  salesAndCollection,
  purchasesAndPayments,
  inventory,
  accounting,
  reports,
  administration,
}

/// Presentation-only module organization shared by every navigation surface.
///
/// It deliberately contains no permission, routing, API, or accounting rules.
abstract final class NineSoftModuleTaxonomy {
  static const _groups = <NineSoftModuleGroup, List<String>>{
    NineSoftModuleGroup.salesAndCollection: <String>[
      'sales',
      'sales.returns',
      'customers',
    ],
    NineSoftModuleGroup.purchasesAndPayments: <String>[
      'purchases',
      'suppliers',
    ],
    NineSoftModuleGroup.inventory: <String>['products', 'inventory'],
    NineSoftModuleGroup.accounting: <String>[
      'cashbox',
      'debts',
      'accounts',
      'wasl',
    ],
    NineSoftModuleGroup.reports: <String>['reports'],
    NineSoftModuleGroup.administration: <String>[
      'payroll',
      'users',
      'branches',
      'backup',
      'whatsapp',
      'settings',
    ],
  };

  static const _labels = <NineSoftModuleGroup, String>{
    NineSoftModuleGroup.salesAndCollection: 'البيع والتحصيل',
    NineSoftModuleGroup.purchasesAndPayments: 'الشراء والسداد',
    NineSoftModuleGroup.inventory: 'المخزون',
    NineSoftModuleGroup.accounting: 'المحاسبة',
    NineSoftModuleGroup.reports: 'التقارير',
    NineSoftModuleGroup.administration: 'الإدارة',
  };

  static List<String> keysFor(NineSoftModuleGroup group) =>
      List<String>.unmodifiable(_groups[group]!);

  static List<String> get orderedKeys => List<String>.unmodifiable(
    NineSoftModuleGroup.values.expand((group) => _groups[group]!),
  );

  static String labelFor(NineSoftModuleGroup group) => _labels[group]!;

  static NineSoftModuleGroup groupFor(String moduleKey) {
    if (moduleKey == 'sales.returns') {
      return NineSoftModuleGroup.salesAndCollection;
    }
    final root = moduleKey.split('.').first;
    for (final entry in _groups.entries) {
      if (entry.value.contains(root)) return entry.key;
    }
    return NineSoftModuleGroup.administration;
  }

  static List<T> order<T>(Iterable<T> values, String Function(T value) keyOf) {
    final positions = <String, int>{
      for (var index = 0; index < orderedKeys.length; index++)
        orderedKeys[index]: index,
    };
    final result = values.toList(growable: false);
    result.sort(
      (left, right) => (positions[keyOf(left)] ?? positions.length).compareTo(
        positions[keyOf(right)] ?? positions.length,
      ),
    );
    return result;
  }
}
