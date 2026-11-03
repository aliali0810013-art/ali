import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/account_statement_page.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';

void main() {
  testWidgets('statement uses detailed labels and opens its source document', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _StatementApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountStatementPage(
            token: 'token',
            branchIds: const ['branch-1'],
            accountingApi: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل كشف الحساب'), findsOneWidget);
    expect(find.textContaining('فاتورة شراء'), findsWidgets);
    await tester.tap(find.byKey(const Key('statement-row-entry-1')));
    await tester.pumpAndSettle();

    expect(api.openedReferences, ['purchase_invoice|invoice-1']);
    expect(find.text('تفاصيل المستند'), findsOneWidget);
    expect(find.textContaining('#100'), findsWidgets);
  });

  testWidgets(
    'statement keeps the balance visible and presents plain-language totals',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AccountStatementPage(
              token: 'token',
              branchIds: const ['branch-1'],
              accountingApi: _StatementApi(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('له خلال الفترة'), findsOneWidget);
      expect(find.text('عليه خلال الفترة'), findsOneWidget);
      expect(find.text('الرصيد النهائي'), findsOneWidget);
      expect(find.text('#100'), findsOneWidget);
      expect(find.text('2100-AP'), findsNothing);

      final balance = find.byKey(const Key('statement-balance-entry-1'));
      expect(balance, findsOneWidget);
      final balanceRect = tester.getRect(balance);
      expect(balanceRect.left, greaterThanOrEqualTo(0));
      expect(balanceRect.right, lessThanOrEqualTo(900));
    },
  );

  testWidgets('contact statement opens directly in the unified template', (
    tester,
  ) async {
    final api = _StatementApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountStatementPage(
            token: 'token',
            branchIds: const ['branch-1'],
            accountingApi: api,
            initialContactId: 'supplier-1',
            initialContactRole: 'supplier',
            initialContactName: 'المورد التجريبي',
            lockContact: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.directoryCalls, 0);
    expect(api.lastContactId, 'supplier-1');
    expect(api.lastRole, 'supplier');
    expect(find.textContaining('المورد التجريبي'), findsWidgets);
    expect(find.text('معايير كشف الحساب'), findsNothing);
  });
}

class _StatementApi extends AccountingApi {
  _StatementApi() : super(token: 'token');

  final List<String> openedReferences = [];
  int directoryCalls = 0;
  String? lastContactId;
  String? lastRole;

  @override
  Future<List<Map<String, dynamic>>> accountDirectory({
    required String branchId,
    String query = '',
  }) async {
    directoryCalls++;
    return [
      {
        'id': 'supplier-1|supplier',
        'kind': 'contact',
        'contact_id': 'supplier-1',
        'role': 'supplier',
        'account_number': 'SUP-1',
        'name': 'المورد التجريبي',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> accountStatement({
    required String branchId,
    String accountId = '',
    String contactId = '',
    String role = '',
    String? from,
    String? to,
    bool includeChildren = false,
  }) async {
    lastContactId = contactId;
    lastRole = role;
    return {
      'account': {'name': 'المورد التجريبي', 'account_number': 'SUP-1'},
      'opening_balance_minor': 0,
      'total_debit_minor': 0,
      'total_credit_minor': 15000,
      'closing_balance_minor': 15000,
      'items': [
        {
          'id': 'line-1',
          'entry_id': 'entry-1',
          'posted_at': '2026-11-01T10:00:00Z',
          'document_number': 'PUR-100',
          'document_type_label': 'فاتورة شراء',
          'description': 'شراء بضاعة',
          'account_code': '2100-AP',
          'debit_minor': 0,
          'credit_minor': 15000,
          'balance_minor': 15000,
          'reference_type': 'purchase_invoice',
          'reference_id': 'invoice-1',
          'can_open_document': true,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> sourceDocument({
    required String branchId,
    required String referenceType,
    required String referenceId,
  }) async {
    openedReferences.add('$referenceType|$referenceId');
    return {
      'reference_type': referenceType,
      'reference_id': referenceId,
      'document': {
        'number': 'PUR-100',
        'party_name': 'المورد التجريبي',
        'total_minor': 15000,
      },
      'items': [],
      'lines': [],
    };
  }
}
