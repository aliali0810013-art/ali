import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/auth/json_transport.dart';
import 'package:nizami/src/features/accounting/accounting_api.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/accounting/searchable_chart_account_field.dart';
import 'package:nizami/src/features/invoices/invoice_history_store.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/invoices/invoice_workspace_page.dart';
import 'package:nizami/src/features/modules/catalog_sync_api.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';
import 'package:nizami/src/features/products/product_sale_option_store.dart';
import 'package:nizami/src/features/sync/pending_invoice_sync.dart';
import 'package:nizami/src/features/sync/quarantined_operation_store.dart';
import 'package:nizami/src/features/sync/sales_invoice_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tenant = 'sales-reference-tenant';
const _branch = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProductCatalogStore(_tenant).save(
      const CatalogProduct(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        sku: '101',
        name: 'كمون',
        salePrice: 5000,
        purchasePrice: 3000,
        barcode: 'CUMIN-BASE',
        unitName: 'gram',
      ),
    );
  });

  testWidgets('cash invoice starts with the visible walk-in customer', (
    tester,
  ) async {
    await _pumpEditor(tester, transport: _InvoiceTransport(), width: 1440);

    expect(find.text('عميل نقدي'), findsOneWidget);
  });

  testWidgets('cash collection account expands searchable results inline', (
    tester,
  ) async {
    await _pumpEditor(tester, transport: _InvoiceTransport(), width: 390);

    final field = find.byType(SearchableChartAccountField);
    expect(field, findsOneWidget);
    await tester.ensureVisible(field);
    final accountToggle = find.descendant(
      of: field,
      matching: find.byType(InkWell),
    ).first;
    await tester.tap(accountToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inline-account-search')), findsOneWidget);
    expect(find.text('ابحث باسم الحساب او رقمه'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('walk-in customer cannot be used for a credit invoice', (
    tester,
  ) async {
    final transport = _InvoiceTransport();
    await _pumpEditor(tester, transport: transport, width: 1440);
    await _addBaseLine(tester);

    await tester.tap(find.text('نقدي').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('آجل').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'الفاتورة الآجلة تتطلب اختيار عميل مسجل أو كتابة اسم عميل جديد.',
      ),
      findsOneWidget,
    );
    expect(transport.calls, 0);
  });

  testWidgets('primary save posts once through the durable outbox online', (
    tester,
  ) async {
    final transport = _InvoiceTransport();
    await _pumpEditor(tester, transport: transport, width: 1440);
    await _addBaseLine(tester);

    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

    expect(transport.calls, 1);
    expect(await SalesInvoiceOutbox(_tenant, _branch).count(), 0);
    final saved = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
    expect(saved.serverInvoiceId, isNotEmpty);
    expect(saved.isDraft, isFalse);
    expect(find.byKey(const Key('invoice-delivery-posted')), findsOneWidget);
    expect(find.text('ترحيل الفاتورة للخادم'), findsNothing);
    expect(find.byKey(const Key('ninesoft-document-editor')), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-entry-line-card-0')), findsNothing);
  });

  testWidgets('offline final save stays immutable and safely queued', (
    tester,
  ) async {
    final transport = _InvoiceTransport(offline: true);
    await _pumpEditor(tester, transport: transport, width: 390);
    await _addBaseLine(tester);

    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await _pumpUntilKey(tester, const Key('invoice-delivery-queued'));

    final outbox = SalesInvoiceOutbox(_tenant, _branch);
    expect(await outbox.count(), 1);
    expect(transport.calls, 1);
    final saved = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
    expect(saved.isDraft, isFalse);
    expect(find.byKey(const Key('invoice-delivery-queued')), findsOneWidget);
    expect(find.textContaining('محفوظة بأمان'), findsOneWidget);
    expect(find.byKey(const Key('ninesoft-entry-line-card-0')), findsNothing);
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsOneWidget);

    final delete = tester.widget<IconButton>(
      find.byKey(const Key('ninesoft-entry-line-delete-0')),
    );
    expect(delete.onPressed, isNull);
    expect(find.byKey(const Key('ninesoft-entry-line-table')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await tester.pump();
    expect(await outbox.count(), 1);

    transport.offline = false;
    final reconnected = await outbox.flush(
      api: AccountingApi(
        token: 'test-token',
        transport: transport,
        baseUrl: 'https://example.test/api/v1',
      ),
      currentRestoreGeneration: 0,
    );
    expect(reconnected.sent, 1);
    expect(await outbox.count(), 0);
    expect(transport.calls, 2);
    final posted = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
    expect(posted.postedToServer, isTrue);
  });

  testWidgets('deterministic rejection is needs-review and never posted copy', (
    tester,
  ) async {
    final transport = _InvoiceTransport(statusCode: 422);
    await _pumpEditor(tester, transport: transport, width: 980);
    await _addBaseLine(tester);

    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await _pumpUntilKey(tester, const Key('invoice-delivery-needs-review'));

    final retained = (await SalesInvoiceOutbox(_tenant, _branch).list()).single;
    expect(retained.state, SalesInvoiceOutboxState.needsReview);
    expect(transport.calls, 1);
    expect(
      find.byKey(const Key('invoice-delivery-needs-review')),
      findsOneWidget,
    );
    expect(find.textContaining('تحتاج مراجعة'), findsWidgets);
    expect(find.byKey(const Key('invoice-delivery-posted')), findsNothing);
  });

  testWidgets(
    'invoice created after restore epoch follows a refreshed generation automatically',
    (tester) async {
      var generation = 1;
      final restoreEpoch = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      final transport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: transport,
        width: 980,
        restoreGenerationReader: () => generation,
        restoreEpochReader: () => restoreEpoch,
      );
      await _addBaseLine(tester);
      generation = 2;

      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      expect(transport.calls, 1);
      final request =
          jsonDecode(transport.bodies.single) as Map<String, dynamic>;
      expect(request['restore_generation'], 2);
      expect(await QuarantinedOperationStore(_tenant).list(), isEmpty);
    },
  );

  testWidgets('Ctrl+S saves an editable draft and legacy sync excludes it', (
    tester,
  ) async {
    final transport = _InvoiceTransport();
    await _pumpEditor(tester, transport: transport, width: 980);
    await _addBaseLine(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final draft = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
    expect(draft.isDraft, isTrue);
    expect(await SalesInvoiceOutbox(_tenant, _branch).count(), 0);
    expect(transport.calls, 0);
    expect(
      await PendingInvoiceSync.isLegacyPending(
        tenantId: _tenant,
        branchId: _branch,
        invoice: draft,
      ),
      isFalse,
    );
    expect(find.byKey(const Key('invoice-delivery-draft')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('invoice-notes-input')))
          .enabled,
      isNot(false),
    );
  });

  testWidgets('F4 focuses barcode and Ctrl+Enter uses the final save path', (
    tester,
  ) async {
    final transport = _InvoiceTransport();
    await _pumpEditor(tester, transport: transport, width: 980);

    for (final keyName in const [
      'invoice-shortcut-f2',
      'invoice-shortcut-f3',
      'invoice-shortcut-f4',
      'invoice-shortcut-new',
    ]) {
      expect(find.byKey(Key(keyName)), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('invoice-shortcut-f4')));
    await tester.pump();
    final barcode = tester.widget<TextField>(
      find.byKey(const Key('invoice-barcode-input')),
    );
    expect(barcode.focusNode?.hasFocus, isTrue);

    await _fillBaseLine(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ninesoft-entry-line-row-0')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

    expect(transport.calls, 1);
    expect(find.byKey(const Key('invoice-delivery-posted')), findsOneWidget);
  });

  testWidgets(
    'create-only cashier posts cash sale without chart read permission',
    (tester) async {
      var chartReads = 0;
      final transport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: transport,
        width: 980,
        roleCode: 'cashier',
        permissions: const ['invoices.create'],
        chartAccountsLoader: (_) async {
          chartReads++;
          throw StateError('invoices.read is required');
        },
      );
      await _addBaseLine(tester);

      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      expect(chartReads, 0);
      expect(transport.calls, 1);
      expect(
        jsonDecode(transport.bodies.single),
        containsPair('payment_channel', 'cash'),
      );
    },
  );

  testWidgets('read-only cashier cannot enqueue by button or shortcut', (
    tester,
  ) async {
    final transport = _InvoiceTransport();
    await _pumpEditor(
      tester,
      transport: transport,
      width: 980,
      roleCode: 'auditor',
      permissions: const ['invoices.read'],
    );
    await _addBaseLine(tester);

    final primary = tester.widget<FilledButton>(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    expect(primary.onPressed, isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(transport.calls, 0);
    expect(await SalesInvoiceOutbox(_tenant, _branch).count(), 0);
    expect(await InvoiceHistoryStore().read(_tenant, _branch), isEmpty);
  });

  testWidgets(
    'same authorized session can reuse redacted cash choices offline',
    (tester) async {
      await _pumpEditor(
        tester,
        transport: _InvoiceTransport(),
        width: 980,
        token: 'owner-session',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      var offlineReads = 0;
      final transport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: transport,
        width: 980,
        token: 'owner-session',
        chartAccountsLoader: (_) async {
          offlineReads++;
          throw StateError('offline');
        },
      );
      await _addBaseLine(tester);
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      expect(offlineReads, 1);
      final body = Map<String, dynamic>.from(
        jsonDecode(transport.bodies.single) as Map,
      );
      expect(body['payment_account_code'], _cashAccount.code);
    },
  );

  testWidgets(
    'owner cache is redacted then cleared before a create-only session while offline creation still works',
    (tester) async {
      await _pumpEditor(
        tester,
        transport: _InvoiceTransport(),
        width: 980,
        token: 'owner-session',
      );
      final preferences = await SharedPreferences.getInstance();
      final cacheKey = preferences.getKeys().singleWhere(
        (key) => key.startsWith('ninesoft.chart_accounts.'),
      );
      final decoded = jsonDecode(preferences.getString(cacheKey)!);
      final storedAccounts = decoded is List
          ? decoded
          : (decoded as Map)['accounts'] as List;
      final stored = Map<String, dynamic>.from(storedAccounts.single as Map);
      expect(stored.keys.toSet(), {'id', 'code', 'name', 'channel', 'version'});
      expect(preferences.getString(cacheKey), isNot(contains('debit_minor')));
      expect(preferences.getString(cacheKey), isNot(contains('credit_minor')));
      expect(preferences.getString(cacheKey), isNot(contains('balance')));
      expect(
        preferences.getString(cacheKey),
        isNot(contains('classification')),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      var forbiddenChartReads = 0;
      final transport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: transport,
        width: 980,
        token: 'cashier-session',
        roleCode: 'cashier',
        permissions: const ['invoices.create'],
        chartAccountsLoader: (_) async {
          forbiddenChartReads++;
          throw StateError('invoices.read is required');
        },
      );
      await _addBaseLine(tester);
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      expect(forbiddenChartReads, 0);
      final body = Map<String, dynamic>.from(
        jsonDecode(transport.bodies.single) as Map,
      );
      expect(body['payment_channel'], 'cash');
      expect(body['payment_account_code'], anyOf(isNull, isEmpty));
      expect(preferences.getString(cacheKey), isNull);
    },
  );

  testWidgets(
    'late owner chart response cannot enter a mounted create-only session',
    (tester) async {
      final ownerChart = Completer<List<ChartAccount>>();
      await _pumpEditor(
        tester,
        transport: _InvoiceTransport(),
        width: 980,
        token: 'owner-session',
        chartAccountsLoader: (_) => ownerChart.future,
      );
      var forbiddenChartReads = 0;
      final transport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: transport,
        width: 980,
        token: 'cashier-session',
        roleCode: 'cashier',
        permissions: const ['invoices.create'],
        chartAccountsLoader: (_) async {
          forbiddenChartReads++;
          throw StateError('invoices.read is required');
        },
      );
      ownerChart.complete(const [_cashAccount]);
      await tester.pumpAndSettle();

      await _addBaseLine(tester);
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      expect(forbiddenChartReads, 0);
      final body = Map<String, dynamic>.from(
        jsonDecode(transport.bodies.single) as Map,
      );
      expect(body['payment_channel'], 'cash');
      expect(body['payment_account_code'], anyOf(isNull, isEmpty));
    },
  );

  testWidgets(
    'reference section order is stable and history opens in a modal',
    (tester) async {
      await _pumpEditor(tester, transport: _InvoiceTransport(), width: 1440);

      final documentTop = tester.getTopLeft(
        find.byKey(const Key('invoice-section-document')),
      );
      final linesTop = tester.getTopLeft(
        find.byKey(const Key('invoice-section-lines')),
      );
      final notesTop = tester.getTopLeft(
        find.byKey(const Key('invoice-section-notes')),
      );
      expect(documentTop.dy, lessThan(linesTop.dy));
      expect(linesTop.dy, lessThan(notesTop.dy));
      expect(
        find.byKey(const Key('invoice-history-modal-content')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('invoice-history-open-primary')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('invoice-history-modal-content')),
        findsOneWidget,
      );
    },
  );

  testWidgets('open history modal receives live sync updates safely', (
    tester,
  ) async {
    final events = StreamController<Set<String>>.broadcast();
    addTearDown(events.close);
    await _pumpEditor(
      tester,
      transport: _InvoiceTransport(),
      width: 980,
      syncChanges: events.stream,
    );
    await tester.tap(find.byKey(const Key('invoice-history-open-primary')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('invoice-history-modal-content')),
      findsOneWidget,
    );

    await InvoiceHistoryStore().save(
      _tenant,
      _branch,
      InvoiceDocument(
        number: 'LOCAL-LIVE-1',
        customerName: 'Live customer',
        customerPhone: '',
        lines: const [
          InvoiceLine(name: 'Live item', quantity: 1, unitPrice: 10),
        ],
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: 'Main',
        createdAt: DateTime.utc(2026, 11, 1, 12),
        localOperationId: 'live-history-operation',
        isDraft: true,
      ),
    );
    events.add({'invoice'});
    await _pumpUntilKey(
      tester,
      const Key('invoice-history-row-live-history-operation'),
    );
    expect(
      find.byKey(const Key('invoice-history-modal-content')),
      findsOneWidget,
    );

    Navigator.of(
      tester.element(find.byKey(const Key('invoice-history-modal-content'))),
    ).pop();
    await tester.pumpAndSettle();
    events.add({'invoice'});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('quarantined invoice keeps edit and delete actions available', (
    tester,
  ) async {
    await InvoiceHistoryStore().save(
      _tenant,
      _branch,
      InvoiceDocument(
        number: 'LOCAL-QUARANTINED-1',
        customerName: 'Held customer',
        customerPhone: '',
        lines: const [
          InvoiceLine(name: 'Held item', quantity: 1, unitPrice: 10),
        ],
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: 'Main',
        createdAt: DateTime.utc(2026, 11, 1, 12),
        localOperationId: 'quarantined-history-operation',
      ).quarantined('restore_generation_mismatch'),
    );
    await _pumpEditor(tester, transport: _InvoiceTransport(), width: 980);
    await tester.tap(find.byKey(const Key('invoice-history-open-primary')));
    await tester.pumpAndSettle();
    final row = find.byKey(
      const Key('invoice-history-row-quarantined-history-operation'),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.visibility_outlined),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('invoice-delivery-quarantined')),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'فاتورة مبسطة'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ninesoft-summary-primary')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('sale by amount keeps the rational milligram price exact', (
    tester,
  ) async {
    await _seedMilligramOption();
    await _pumpEditor(tester, transport: _InvoiceTransport(), width: 1440);

    await tester.enterText(
      find.byKey(const Key('invoice-barcode-input')),
      'CUMIN-MG',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invoice-sale-amount-input')),
      '1.25',
    );
    final addByAmount = find.byKey(const Key('invoice-sale-amount-add'));
    await _jumpToInvoiceBottom(tester, addByAmount);
    await tester.tap(addByAmount);
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('ninesoft-entry-line-row-0'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('250')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('1.25 YER')),
      findsOneWidget,
    );
  });

  testWidgets(
    'unit barcode selects exact milligram option and previews 1.25 YER',
    (tester) async {
      await _seedMilligramOption();
      await _pumpEditor(tester, transport: _InvoiceTransport(), width: 1440);

      await tester.enterText(
        find.byKey(const Key('invoice-barcode-input')),
        'CUMIN-MG',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-price-input')))
            .controller
            ?.text,
        '0.005',
      );
      await tester.enterText(
        find.byKey(const Key('invoice-quantity-input')),
        '250',
      );
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();

      expect(find.text('ملليجرام'), findsWidgets);
      expect(find.textContaining('1.25'), findsWidgets);
      final current = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('ninesoft-summary-total')),
              matching: find.byType(Text),
            )
            .last,
      );
      expect(current.data, contains('1.25'));
      final row = find.byKey(const Key('ninesoft-entry-line-row-0'));
      expect(find.descendant(of: row, matching: find.text('0.005')), findsOne);
    },
  );

  testWidgets('manual option price override drops stale exact authority', (
    tester,
  ) async {
    await _seedMilligramOption();
    final transport = _InvoiceTransport();
    await _pumpEditor(tester, transport: transport, width: 1440);

    await tester.enterText(
      find.byKey(const Key('invoice-barcode-input')),
      'CUMIN-MG',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invoice-quantity-input')),
      '250',
    );
    await tester.enterText(
      find.byKey(const Key('invoice-price-input')),
      '0.02',
    );
    final addLine = find.byKey(const Key('invoice-add-line'));
    await tester.scrollUntilVisible(
      addLine,
      450,
      scrollable: find
          .ancestor(of: addLine, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(addLine);
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('ninesoft-entry-line-row-0'));
    expect(find.descendant(of: row, matching: find.text('0.02')), findsOne);
    expect(find.descendant(of: row, matching: find.text('5.00 YER')), findsOne);

    await tester.ensureVisible(
      find.byKey(const Key('ninesoft-summary-primary')),
    );
    await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
    await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

    final request = Map<String, dynamic>.from(
      jsonDecode(transport.bodies.single) as Map,
    );
    final line = Map<String, dynamic>.from((request['items'] as List).single);
    expect(line['unit_price_minor'], 2);
    expect(line['price_overridden'], isTrue);
    expect(line['price_numerator_minor'], 2);
    expect(line['price_denominator'], 1);
    final saved = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
    expect(saved.lines.single.priceOverridden, isTrue);
    expect(saved.lines.single.totalMinor, 500);
  });

  testWidgets(
    'retyping the rounded managed preview carries explicit manual intent through ACK',
    (tester) async {
      await _seedVariablePieceOption(24);
      final transport = _InvoiceTransport();
      await _pumpEditor(tester, transport: transport, width: 1440);

      await tester.enterText(
        find.byKey(const Key('invoice-barcode-input')),
        'PACK-24',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final priceInput = find.byKey(const Key('invoice-price-input'));
      await tester.enterText(priceInput, '');
      await tester.enterText(priceInput, '416.67');
      await tester.enterText(
        find.byKey(const Key('invoice-quantity-input')),
        '24',
      );
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();

      expect(find.text('10000.08 YER'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));
      final request = Map<String, dynamic>.from(
        jsonDecode(transport.bodies.single) as Map,
      );
      final line = Map<String, dynamic>.from((request['items'] as List).single);
      expect(line['unit_price_minor'], 41667);
      expect(line['price_overridden'], isTrue);
      expect(line['price_numerator_minor'], 41667);
      expect(line['price_denominator'], 1);
      final saved = (await InvoiceHistoryStore().read(_tenant, _branch)).single;
      expect(saved.lines.single.priceOverridden, isTrue);
      expect(saved.lines.single.priceNumeratorMinor, 41667);
      expect(saved.lines.single.priceDenominator, 1);
      expect(saved.lines.single.totalMinor, 1000008);
    },
  );

  for (final scenario in const [
    (factor: 6, preview: '1666.67'),
    (factor: 12, preview: '833.33'),
    (factor: 24, preview: '416.67'),
    (factor: 100, preview: '100.0001'),
  ]) {
    testWidgets(
      'configured ${scenario.factor}-piece pack keeps its non-divisible exact price through ACK',
      (tester) async {
        await _seedVariablePieceOption(scenario.factor);
        final transport = _InvoiceTransport();
        await _pumpEditor(tester, transport: transport, width: 1440);

        await tester.enterText(
          find.byKey(const Key('invoice-barcode-input')),
          'PACK-${scenario.factor}',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('invoice-price-input')))
              .controller
              ?.text,
          scenario.preview,
        );
        await tester.enterText(
          find.byKey(const Key('invoice-quantity-input')),
          '${scenario.factor}',
        );
        final addLine = find.byKey(const Key('invoice-add-line'));
        await tester.scrollUntilVisible(
          addLine,
          450,
          scrollable: find
              .ancestor(of: addLine, matching: find.byType(Scrollable))
              .first,
        );
        await tester.tap(addLine);
        await tester.pumpAndSettle();

        final row = find.byKey(const Key('ninesoft-entry-line-row-0'));
        expect(
          find.descendant(of: row, matching: find.text('10000.01 YER')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('ninesoft-summary-primary')),
        );
        await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
        await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

        final request = Map<String, dynamic>.from(
          jsonDecode(transport.bodies.single) as Map,
        );
        final immutableLine = Map<String, dynamic>.from(
          (request['items'] as List).single as Map,
        );
        expect(immutableLine['price_numerator_minor'], 1000001);
        expect(immutableLine['price_denominator'], scenario.factor);
        expect(await SalesInvoiceOutbox(_tenant, _branch).count(), 0);
        final saved = (await InvoiceHistoryStore().read(
          _tenant,
          _branch,
        )).single;
        expect(saved.lines.single.priceNumeratorMinor, 1000001);
        expect(saved.lines.single.priceDenominator, scenario.factor);
        expect(saved.lines.single.totalMinor, 1000001);
      },
    );
  }

  testWidgets('lines with different exact ratios never merge', (tester) async {
    final events = StreamController<Set<String>>.broadcast();
    addTearDown(events.close);
    await _seedMilligramOption(numerator: 500000, version: 1);
    await _pumpEditor(
      tester,
      transport: _InvoiceTransport(),
      width: 1440,
      syncChanges: events.stream,
    );

    Future<void> scanAndAdd() async {
      await tester.enterText(
        find.byKey(const Key('invoice-barcode-input')),
        'CUMIN-MG',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();
    }

    await scanAndAdd();
    await _seedMilligramOption(numerator: 600000, version: 2);
    events.add({'product_sale_option'});
    await tester.pumpAndSettle();
    await scanAndAdd();

    expect(find.byKey(const Key('ninesoft-entry-line-row-0')), findsOne);
    expect(find.byKey(const Key('ninesoft-entry-line-row-1')), findsOne);
  });

  testWidgets(
    'fresh option refresh atomically replaces cached managed price authority',
    (tester) async {
      await _seedVariablePieceOption(24);
      final refresh = _SaleOptionRefreshTransport();
      final invoiceTransport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: invoiceTransport,
        width: 1440,
        catalogApi: CatalogSyncApi(token: 'test', transport: refresh),
      );

      await tester.enterText(
        find.byKey(const Key('invoice-barcode-input')),
        'PACK-24',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-price-input')))
            .controller
            ?.text,
        '416.67',
      );

      refresh.completeFresh();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-price-input')))
            .controller
            ?.text,
        '500',
      );
      expect(
        find.byKey(const Key('invoice-sale-option-piece-24-v2')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('invoice-quantity-input')),
        '24',
      );
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));
      final request = Map<String, dynamic>.from(
        jsonDecode(invoiceTransport.bodies.single) as Map,
      );
      final line = Map<String, dynamic>.from((request['items'] as List).single);
      expect(line, isNot(contains('price_overridden')));
      expect(line['price_numerator_minor'], 1200000);
      expect(line['price_denominator'], 24);
    },
  );

  testWidgets(
    'fresh option refresh preserves manual price intent while rebinding the option',
    (tester) async {
      await _seedVariablePieceOption(24);
      final refresh = _SaleOptionRefreshTransport();
      final invoiceTransport = _InvoiceTransport();
      await _pumpEditor(
        tester,
        transport: invoiceTransport,
        width: 1440,
        catalogApi: CatalogSyncApi(token: 'test', transport: refresh),
      );

      await tester.enterText(
        find.byKey(const Key('invoice-barcode-input')),
        'PACK-24',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final priceInput = find.byKey(const Key('invoice-price-input'));
      await tester.enterText(priceInput, '');
      await tester.enterText(priceInput, '416.67');
      refresh.completeFresh();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-price-input')))
            .controller
            ?.text,
        '416.67',
      );
      expect(
        find.byKey(const Key('invoice-sale-option-piece-24-v2')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('invoice-quantity-input')),
        '24',
      );
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('ninesoft-summary-primary')),
      );
      await tester.tap(find.byKey(const Key('ninesoft-summary-primary')));
      await _pumpUntilKey(tester, const Key('invoice-delivery-posted'));

      final request = Map<String, dynamic>.from(
        jsonDecode(invoiceTransport.bodies.single) as Map,
      );
      final line = Map<String, dynamic>.from((request['items'] as List).single);
      expect(line['sale_option_id'], 'piece-24');
      expect(line['price_overridden'], isTrue);
      expect(line['price_numerator_minor'], 41667);
      expect(line['price_denominator'], 1);
    },
  );

  test(
    'server restore history keeps manual and canonical price authority',
    () async {
      final manual = _serverVariablePieceInvoice(manual: true);
      final canonical = _serverVariablePieceInvoice(manual: false);

      await InvoiceHistoryStore().replaceRemoteSnapshot(_tenant, _branch, [
        manual,
        canonical,
      ]);
      final restored = await InvoiceHistoryStore().read(_tenant, _branch);
      final restoredManual = restored.firstWhere(
        (invoice) =>
            invoice.serverInvoiceId == '11111111-1111-4111-8111-111111111111',
      );
      final restoredCanonical = restored.firstWhere(
        (invoice) =>
            invoice.serverInvoiceId == '22222222-2222-4222-8222-222222222222',
      );

      expect(restoredManual.lines.single.priceOverridden, isTrue);
      expect(restoredManual.lines.single.priceNumeratorMinor, 41667);
      expect(restoredManual.lines.single.priceDenominator, 1);
      expect(restoredManual.lines.single.totalMinor, 1000008);
      expect(restoredCanonical.lines.single.priceOverridden, isFalse);
      expect(restoredCanonical.lines.single.priceNumeratorMinor, 1000001);
      expect(restoredCanonical.lines.single.priceDenominator, 24);
      expect(restoredCanonical.lines.single.totalMinor, 1000001);
    },
  );

  testWidgets(
    'server history edit and option refresh preserve manual price intent',
    (tester) async {
      await _seedVariablePieceOption(24);
      await InvoiceHistoryStore().save(
        _tenant,
        _branch,
        _serverVariablePieceInvoice(manual: true),
      );
      final transport = _InvoiceTransport();
      await _pumpEditor(tester, transport: transport, width: 1440);

      await tester.tap(find.byKey(const Key('invoice-history-open-primary')));
      await tester.pumpAndSettle();
      final historyRow = find.byKey(
        const Key('invoice-history-row-server-manual-operation'),
      );
      await tester.tap(
        find.descendant(
          of: historyRow,
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byKey(const Key('invoice-history-modal-content'))),
      ).pop();
      await tester.pumpAndSettle();

      final editableLine = find
          .descendant(
            of: find.byKey(const Key('ninesoft-entry-line-row-0')),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(editableLine);
      await tester.pumpAndSettle();
      await tester.tap(editableLine);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('invoice-price-input')))
            .controller
            ?.text,
        '416.67',
      );
      final addLine = find.byKey(const Key('invoice-add-line'));
      await tester.scrollUntilVisible(
        addLine,
        450,
        scrollable: find
            .ancestor(of: addLine, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(addLine);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final edited = (await InvoiceHistoryStore().read(
        _tenant,
        _branch,
      )).firstWhere((invoice) => invoice.isDraft);
      expect(edited.lines.single.priceOverridden, isTrue);
      expect(edited.lines.single.priceNumeratorMinor, 41667);
      expect(edited.lines.single.priceDenominator, 1);
      final request = await AccountingApi(
        token: 'test-token',
      ).prepareInvoiceRequest(branchId: _branch, invoice: edited);
      final line = Map<String, dynamic>.from((request['items'] as List).single);
      expect(line['price_overridden'], isTrue);
      expect(line['price_numerator_minor'], 41667);
      expect(line['price_denominator'], 1);
    },
  );
}

InvoiceDocument _serverVariablePieceInvoice({required bool manual}) =>
    InvoiceDocument.fromServer({
      'id': manual
          ? '11111111-1111-4111-8111-111111111111'
          : '22222222-2222-4222-8222-222222222222',
      'number': manual ? 'SAL-MANUAL-1' : 'SAL-CANONICAL-1',
      'branch_id': _branch,
      'local_operation_id': manual
          ? 'server-manual-operation'
          : 'server-canonical-operation',
      'total_minor': manual ? 1000008 : 1000001,
      'paid_minor': manual ? 1000008 : 1000001,
      'initial_paid_minor': manual ? 1000008 : 1000001,
      'due_minor': 0,
      'payment_mode_at_issue': 'cash',
      'occurred_at': '2026-11-01T08:00:00Z',
      'creator_display_name': 'Owner',
      'items': [
        {
          'product_name_snapshot': 'ÙƒÙ…ÙˆÙ†',
          'product_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sale_option_id': 'piece-24',
          'option_unit_code_snapshot': 'piece',
          'option_quantity_snapshot': '1.000000',
          'quantity_milli': 24000,
          'unit_price_minor': 41667,
          'price_numerator_minor_snapshot': manual ? 41667 : 1000001,
          'price_denominator_snapshot': manual ? 1 : 24,
          'price_overridden': manual,
          'discount_minor': 0,
          'line_total_minor': manual ? 1000008 : 1000001,
        },
      ],
    });

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _InvoiceTransport transport,
  required double width,
  Stream<Set<String>>? syncChanges,
  String token = 'test-token',
  String roleCode = 'owner',
  List<String> permissions = const ['invoices.create', 'invoices.update'],
  Future<List<ChartAccount>> Function(String branchId)? chartAccountsLoader,
  CatalogSyncApi? catalogApi,
  int Function()? restoreGenerationReader,
  DateTime? Function()? restoreEpochReader,
}) async {
  tester.view.physicalSize = Size(width, width <= 700 ? 1600 : 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: InvoiceWorkspacePage(
        branchIds: const [_branch],
        tenantName: 'Tenant',
        tenantId: _tenant,
        employeeName: 'Owner',
        token: token,
        roleCode: roleCode,
        permissions: permissions,
        catalogApi:
            catalogApi ??
            CatalogSyncApi(
              token: 'offline',
              transport: _CatalogOfflineTransport(),
            ),
        chartAccountsLoader:
            chartAccountsLoader ?? (_) async => const [_cashAccount],
        identityLoader: (_, _) async {},
        syncChanges: syncChanges ?? const Stream.empty(),
        accountingApiFactory: () => AccountingApi(
          token: token,
          transport: transport,
          baseUrl: 'https://example.test/api/v1',
        ),
        synchronizeNow: () async {},
        restoreGenerationReader: restoreGenerationReader ?? () => 0,
        restoreEpochReader: restoreEpochReader ?? () => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilKey(WidgetTester tester, Key key) async {
  for (var tick = 0; tick < 100; tick++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(key).evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $key');
}

Future<void> _seedMilligramOption({int numerator = 500000, int version = 1}) =>
    ProductSaleOptionStore(_tenant, _branch).replaceSnapshot([
      ProductSaleOption.fromJson({
        'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'tenant_id': _tenant,
        'branch_id': _branch,
        'product_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'identity_key': 'mass:milligram:1',
        'unit_code': 'milligram',
        'quantity_per_option': '1',
        'normalized_mass_g': '0.001',
        'option_price_minor': 1,
        'price_numerator_minor': '$numerator',
        'price_denominator': '1000000',
        'unit_barcode': 'CUMIN-MG',
        'is_derived': true,
        'version': '$version',
      }),
    ]);

Future<void> _seedVariablePieceOption(int factor) =>
    ProductSaleOptionStore(_tenant, _branch).replaceSnapshot([
      ProductSaleOption.fromJson({
        'id': 'piece-$factor',
        'tenant_id': _tenant,
        'branch_id': _branch,
        'product_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'identity_key': 'count:piece:1',
        'unit_code': 'piece',
        'quantity_per_option': '1',
        'option_price_minor': switch (factor) {
          6 => 166667,
          12 => 83333,
          24 => 41667,
          100 => 10000,
          _ => throw ArgumentError.value(factor, 'factor'),
        },
        'price_numerator_minor': '1000001',
        'price_denominator': '$factor',
        'unit_barcode': 'PACK-$factor',
        'is_derived': true,
        'version': '1',
      }),
    ]);

Future<void> _fillBaseLine(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('invoice-product-input')),
    'كمون',
  );
  await tester.pump();
  await tester.tap(find.text('كمون').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('invoice-quantity-input')), '1');
  await tester.enterText(find.byKey(const Key('invoice-price-input')), '5000');
}

Future<void> _jumpToInvoiceBottom(
  WidgetTester tester,
  Finder descendant,
) async {
  final scrollable = find
      .ancestor(of: descendant, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}

Future<void> _addBaseLine(WidgetTester tester) async {
  await _fillBaseLine(tester);
  final addLine = find.byKey(const Key('invoice-add-line'));
  final invoiceScroll = find
      .ancestor(of: addLine, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(addLine, 450, scrollable: invoiceScroll);
  final position = tester.state<ScrollableState>(invoiceScroll).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
  await tester.tap(addLine);
  await tester.pumpAndSettle();
}

const _cashAccount = ChartAccount(
  id: 'cash-id',
  code: '1110-CASH',
  nameAr: 'الصندوق',
  type: 'asset',
  normalBalance: 'debit',
  balanceMinor: 987654,
  classification: 'current_asset',
  closingStatement: 'balance_sheet',
  nameEn: 'Privileged cash balance',
  isSystem: true,
  isCashEquivalent: true,
);

class _CatalogOfflineTransport implements JsonTransport {
  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) => throw StateError('offline catalog');
}

class _SaleOptionRefreshTransport implements JsonTransport {
  final _fresh = Completer<JsonResponse>();

  void completeFresh() => _fresh.complete(
    const JsonResponse(
      statusCode: 200,
      body:
          '{"data":[{"id":"piece-24","tenant_id":"sales-reference-tenant","branch_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","product_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","identity_key":"count:piece:1","unit_code":"piece","quantity_per_option":"1","option_price_minor":50000,"price_numerator_minor":"1200000","price_denominator":"24","unit_barcode":"PACK-24","is_derived":true,"version":"2"}]}',
    ),
  );

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) {
    if (uri.path.contains('/sale-options')) return _fresh.future;
    throw StateError('offline catalog');
  }
}

class _InvoiceTransport implements JsonTransport {
  _InvoiceTransport({this.offline = false, this.statusCode = 201});

  bool offline;
  final int statusCode;
  int calls = 0;
  final List<String> bodies = [];

  @override
  Future<JsonResponse> request(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls++;
    bodies.add(body ?? '');
    if (offline) throw StateError('offline');
    if (statusCode >= 400) {
      return JsonResponse(
        statusCode: statusCode,
        body: '{"message":"rejected for review"}',
      );
    }
    final request = Map<String, dynamic>.from(jsonDecode(body!) as Map);
    final items = (request['items'] as List).cast<Map>();
    var total = 0;
    final acknowledgedItems = <Map<String, dynamic>>[];
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw);
      final quantity = item['quantity_milli'] as int;
      final numerator = item['price_numerator_minor'] as int?;
      final denominator = item['price_denominator'] as int?;
      final gross = numerator == null
          ? ((quantity * (item['unit_price_minor'] as int) + 500) ~/ 1000)
          : ((quantity * numerator + (denominator! * 1000) ~/ 2) ~/
                (denominator * 1000));
      total += gross - ((item['discount_minor'] as int?) ?? 0);
      acknowledgedItems.add({
        'product_name_snapshot': item['name'],
        'product_id': item['product_id'],
        'sale_option_id': item['sale_option_id'],
        'quantity_milli': item['quantity_milli'],
        'unit_price_minor': item['unit_price_minor'],
        'discount_minor': item['discount_minor'] ?? 0,
        'price_numerator_minor_snapshot': item['price_numerator_minor'],
        'price_denominator_snapshot': item['price_denominator'],
        'price_overridden': item['price_overridden'] == true,
      });
    }
    return JsonResponse(
      statusCode: 201,
      body: jsonEncode({
        'invoice': {
          'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'number': 'SAL-TEST-1',
          'branch_id': request['branch_id'],
          'total_minor': total,
          'returned_minor': 0,
          'paid_minor': total,
          'due_minor': 0,
          'initial_paid_minor': total,
          'payment_mode_at_issue': request['payment_mode'],
          'amount_tendered_minor': request['amount_tendered_minor'],
          'payment_channel': request['payment_channel'] ?? 'cash',
          'payment_account_code': request['payment_account_code'] ?? '',
          'status': 'posted',
          'items': acknowledgedItems,
        },
      }),
    );
  }
}
