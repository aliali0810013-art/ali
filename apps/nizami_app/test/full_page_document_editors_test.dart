import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/simple_journal_page.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/features/purchases/purchase_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'purchase creation replaces the register with an embedded editor',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: PurchaseWorkspacePage(
            token: '',
            branchIds: ['branch-1'],
            tenantName: 'Tenant',
            roleCode: 'owner',
            permissions: [],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('فاتورة شراء جديدة'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('purchase-document-editor')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier), findsNothing);
    },
  );

  testWidgets('journal creation is an embedded full-page editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SimpleJournalPage(
          token: '',
          branchIds: ['branch-1'],
          roleCode: 'owner',
          permissions: [],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('قيد جديد'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('journal-document-editor')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNothing);
  });

  testWidgets('sales invoice renders as the page document editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: InvoiceWorkspacePage(
          branchIds: ['branch-1'],
          tenantName: 'Tenant',
          employeeName: 'Owner',
          token: '',
          roleCode: 'owner',
          permissions: [],
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('invoice-document-editor')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
  });
}
