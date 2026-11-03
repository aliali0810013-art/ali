import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/dashboard/ninesoft_reference_dashboard.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'phone command center uses compact icon shortcuts without long forms',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;

      await tester.pumpWidget(
        _app(onOpen: (key) => opened = key, modules: _modules),
      );
      await tester.pumpAndSettle();

      final quickGrid = tester.widget<GridView>(
        find.byKey(const Key('dashboard-quick-action-grid')),
      );
      final quickDelegate =
          quickGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(quickDelegate.crossAxisCount, 3);
      expect(
        find.byKey(const Key('quick-action-fast-invoice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('quick-action-invoice')), findsOneWidget);
      expect(find.byKey(const Key('quick-action-receipt')), findsOneWidget);
      expect(find.byKey(const Key('quick-action-payment')), findsOneWidget);
      expect(find.byKey(const Key('quick-action-journal')), findsOneWidget);
      expect(find.byKey(const Key('quick-action-customer')), findsOneWidget);

      expect(find.byKey(const Key('dashboard-invoice-preview')), findsNothing);
      expect(find.byKey(const Key('dashboard-voucher-preview')), findsNothing);
      expect(find.byKey(const Key('dashboard-journal-preview')), findsNothing);
      expect(find.textContaining('فتح محرر'), findsNothing);
      expect(find.text('النشاط الأخير'), findsNothing);
      expect(find.text('حالة الخدمات'), findsNothing);
      expect(find.text('لمحة عن نشاطك'), findsNothing);
      expect(find.textContaining('مرحباً بك في'), findsNothing);
      expect(find.text('المالك'), findsNothing);
      for (final keyName in const [
        'overview-sales-card',
        'overview-purchases-card',
        'overview-products-card',
        'overview-customers-card',
      ]) {
        expect(find.byKey(Key(keyName)), findsOneWidget);
      }
      final featureGrid = tester.widget<GridView>(
        find.byKey(const Key('dashboard-feature-shortcut-grid')),
      );
      final featureDelegate =
          featureGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(featureDelegate.crossAxisCount, 4);
      for (final keyName in const [
        'feature-shortcut-reports',
        'feature-shortcut-customers',
        'feature-shortcut-products',
        'feature-shortcut-inventory',
        'feature-shortcut-sales',
        'feature-shortcut-purchases',
        'feature-shortcut-suppliers',
        'feature-shortcut-cashbox',
        'feature-shortcut-accounts',
        'feature-shortcut-whatsapp',
        'feature-shortcut-backup',
        'feature-shortcut-settings',
      ]) {
        expect(find.byKey(Key(keyName)), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('overview-sales-card')));
      expect(opened, 'sales');
      expect(
        find.byKey(const Key('quick-action-icon-fast-invoice')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('quick-action-receipt')));
      expect(opened, 'debts.receipts');
      await tester.tap(find.byKey(const Key('quick-action-payment')));
      expect(opened, 'debts.payments');
      await tester.tap(find.byKey(const Key('quick-action-journal')));
      expect(opened, 'accounts.journals');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone home keeps only important shortcuts', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(onOpen: (_) {}, modules: _modules));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-module-grid')), findsNothing);
    expect(find.text('الأقسام الرئيسية'), findsOneWidget);
    expect(
      find.byKey(const Key('dashboard-feature-shortcut-grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick actions respect the available root modules', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onOpen: (_) {}, modules: const [_customers]));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-action-customer')), findsOneWidget);
    expect(find.byKey(const Key('quick-action-invoice')), findsNothing);
    expect(find.byKey(const Key('quick-action-receipt')), findsNothing);
    expect(find.byKey(const Key('quick-action-journal')), findsNothing);
  });
}

Widget _app({
  required ValueChanged<String> onOpen,
  required List<ModuleDefinition> modules,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: NineSoftReferenceDashboard(
        tenantName: 'ناين فود',
        tenantId: 'tenant-test',
        displayName: 'المالك',
        branchIds: const ['branch-test'],
        modules: modules,
        onOpen: onOpen,
        statusIndicator: const Text('متزامن'),
      ),
    ),
  ),
);

const _sales = ModuleDefinition(
  key: 'sales',
  title: 'المبيعات',
  entityLabel: 'فاتورة بيع',
  actionLabel: 'فاتورة جديدة',
  icon: Icons.shopping_cart_rounded,
  color: Colors.blue,
);
const _debts = ModuleDefinition(
  key: 'debts',
  title: 'السندات',
  entityLabel: 'سند',
  actionLabel: 'سند جديد',
  icon: Icons.payments_rounded,
  color: Colors.green,
);
const _accounts = ModuleDefinition(
  key: 'accounts',
  title: 'الحسابات',
  entityLabel: 'قيد',
  actionLabel: 'قيد جديد',
  icon: Icons.calculate_rounded,
  color: Colors.orange,
);
const _customers = ModuleDefinition(
  key: 'customers',
  title: 'العملاء',
  entityLabel: 'عميل',
  actionLabel: 'عميل جديد',
  icon: Icons.groups_rounded,
  color: Colors.purple,
);
const _products = ModuleDefinition(
  key: 'products',
  title: 'الأصناف',
  entityLabel: 'صنف',
  actionLabel: 'صنف جديد',
  icon: Icons.inventory_2_rounded,
  color: Colors.amber,
);
const _reports = ModuleDefinition(
  key: 'reports',
  title: 'التقارير',
  entityLabel: 'تقرير',
  actionLabel: 'عرض تقرير',
  icon: Icons.bar_chart_rounded,
  color: Colors.indigo,
);
const _purchases = ModuleDefinition(
  key: 'purchases',
  title: 'المشتريات',
  entityLabel: 'فاتورة شراء',
  actionLabel: 'فاتورة جديدة',
  icon: Icons.shopping_cart_rounded,
  color: Colors.pink,
);
const _inventory = ModuleDefinition(
  key: 'inventory',
  title: 'المخزون',
  entityLabel: 'حركة مخزون',
  actionLabel: 'عرض المخزون',
  icon: Icons.inventory_rounded,
  color: Colors.orange,
);
const _suppliers = ModuleDefinition(
  key: 'suppliers',
  title: 'الموردون',
  entityLabel: 'مورد',
  actionLabel: 'مورد جديد',
  icon: Icons.local_shipping_rounded,
  color: Colors.orange,
);
const _whatsapp = ModuleDefinition(
  key: 'whatsapp',
  title: 'واتساب',
  entityLabel: 'رسالة',
  actionLabel: 'فتح واتساب',
  icon: Icons.chat_rounded,
  color: Colors.green,
);
const _backup = ModuleDefinition(
  key: 'backup',
  title: 'المزامنة',
  entityLabel: 'مزامنة',
  actionLabel: 'فتح المزامنة',
  icon: Icons.sync_rounded,
  color: Colors.lightBlue,
);
const _settings = ModuleDefinition(
  key: 'settings',
  title: 'الإعدادات',
  entityLabel: 'إعداد',
  actionLabel: 'فتح الإعدادات',
  icon: Icons.settings_rounded,
  color: Colors.blueGrey,
);
const _cashbox = ModuleDefinition(
  key: 'cashbox',
  title: 'الصندوق',
  entityLabel: 'حركة صندوق',
  actionLabel: 'فتح الصندوق',
  icon: Icons.savings_rounded,
  color: Colors.amber,
);

const _modules = [
  _sales,
  _purchases,
  _debts,
  _accounts,
  _customers,
  _products,
  _inventory,
  _suppliers,
  _reports,
  _whatsapp,
  _backup,
  _settings,
  _cashbox,
];
