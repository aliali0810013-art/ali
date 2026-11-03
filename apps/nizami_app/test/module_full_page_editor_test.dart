import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/modules/module_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'customer creation replaces the register with an embedded editor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleWorkspacePage(
            module: ModuleDefinition(
              key: 'customers',
              title: 'العملاء',
              entityLabel: 'عميل',
              actionLabel: 'إضافة عميل',
              icon: Icons.people_outline,
              color: Colors.blue,
            ),
            tenantName: 'Tenant',
            token: '',
            branchIds: ['branch-1'],
            roleCode: 'owner',
            permissions: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('header-add-customers')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('module-record-document-editor')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier), findsNothing);
    },
  );
}
