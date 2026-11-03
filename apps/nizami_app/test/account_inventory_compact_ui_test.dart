import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/account_statement_page.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/accounting/chart_accounts_page.dart';
import 'package:nizami/src/features/accounting/product_inquiry_page.dart';

void main() {
  testWidgets('statement opens source details inline without an alert', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
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

    await tester.tap(find.byKey(const Key('statement-row-entry-1')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('statement-inline-source')), findsOneWidget);
    expect(find.textContaining('#100'), findsWidgets);
  });

  testWidgets('product inquiry keeps facts collapsed until row expansion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProductInquiryResultCard(
              item: {
                'id': 'product-1',
                'name': 'Test product',
                'sku': 'SKU-1',
                'barcode': '123456',
                'unit_name': 'box',
                'quantity_milli': 3000,
                'warehouses': [
                  {'branch_name': 'Main warehouse', 'quantity_milli': 3000},
                ],
                'last_purchase': {
                  'invoice_number': 'PUR-1',
                  'supplier_name': 'Supplier',
                  'occurred_at': '2026-11-01T10:00:00Z',
                  'unit_price_minor': 1200,
                  'net_unit_price_minor': 1000,
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Main warehouse'), findsNothing);
    expect(find.textContaining('PUR-1'), findsNothing);

    await tester.tap(find.byKey(const Key('product-inquiry-product-1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Main warehouse'), findsOneWidget);
    expect(find.textContaining('PUR-1'), findsOneWidget);
  });

  testWidgets('chart owner edits accounts in the page instead of a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ChartAccountsPage(
            token: 'token',
            branchIds: const ['branch-1'],
            roleCode: 'owner',
            chartAccountsApi: _ChartApi(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.byKey(const Key('chart-account-inline-editor')),
      findsOneWidget,
    );
  });
}

class _StatementApi extends AccountingApi {
  _StatementApi() : super(token: 'token');

  @override
  Future<List<Map<String, dynamic>>> accountDirectory({
    required String branchId,
    String query = '',
  }) async => [
    {
      'id': 'supplier-1|supplier',
      'kind': 'contact',
      'contact_id': 'supplier-1',
      'role': 'supplier',
      'account_number': 'SUP-1',
      'name': 'Supplier',
    },
  ];

  @override
  Future<Map<String, dynamic>> accountStatement({
    required String branchId,
    String accountId = '',
    String contactId = '',
    String role = '',
    String? from,
    String? to,
    bool includeChildren = false,
  }) async => {
    'account': {'name': 'Supplier', 'account_number': 'SUP-1'},
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
        'document_type_label': 'Purchase invoice',
        'description': 'Stock purchase',
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

  @override
  Future<Map<String, dynamic>> sourceDocument({
    required String branchId,
    required String referenceType,
    required String referenceId,
  }) async => {
    'reference_type': referenceType,
    'reference_id': referenceId,
    'document': {
      'number': 'PUR-100',
      'party_name': 'Supplier',
      'total_minor': 15000,
    },
    'items': [],
    'lines': [],
  };
}

class _ChartApi extends ChartAccountsApi {
  _ChartApi() : super('token');

  @override
  Future<List<ChartAccount>> list(String branchId) async => const [
    ChartAccount(
      id: 'asset-root',
      code: '1000',
      nameAr: 'Assets',
      type: 'asset',
      normalBalance: 'debit',
      balanceMinor: 10000,
      allowPosting: false,
    ),
  ];
}
