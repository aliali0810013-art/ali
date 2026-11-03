import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/data/invoices/local_invoice_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database database;
  late LocalInvoiceRepository repository;

  setUp(() {
    database = sqlite3.openInMemory();
    repository = LocalInvoiceRepository(database)..migrate();
  });
  tearDown(() => database.close());

  SalesInvoiceDraft draft(String operationId) => SalesInvoiceDraft(
    tenantId: 'tenant-a',
    branchId: 'branch-a',
    branchCode: 'MAIN',
    deviceId: 'device-a',
    creatorUserId: 'user-a',
    creatorDisplayName: 'موظف المبيعات',
    localOperationId: operationId,
    paidMinor: 4000,
    occurredAt: DateTime.utc(2026, 10, 12),
    lines: const [
      InvoiceLineDraft(
        name: 'طابعة حرارية',
        kind: 'stock',
        quantityMilli: 1000,
        unitPriceMinor: 10000,
        purchaseCostMinor: 6000,
      ),
    ],
  );

  test('smart-adds product and atomically posts a balanced sale', () {
    final saved = repository.saveSale(draft('op-1'));
    expect(saved.wasAlreadySaved, isFalse);
    expect(database.select('SELECT * FROM products'), hasLength(1));
    expect(database.select('SELECT * FROM invoices'), hasLength(1));
    expect(database.select('SELECT * FROM outbox'), hasLength(1));
    final totals = database
        .select(
          'SELECT SUM(debit_minor) debit, SUM(credit_minor) credit FROM journal_lines',
        )
        .single;
    expect(totals['debit'], totals['credit']);
  });

  test('repeating the same local operation is idempotent', () {
    final first = repository.saveSale(draft('op-same'));
    final second = repository.saveSale(draft('op-same'));
    expect(second.wasAlreadySaved, isTrue);
    expect(second.id, first.id);
    expect(database.select('SELECT * FROM invoices'), hasLength(1));
  });

  test('normalization prevents accidental duplicate products', () {
    repository.saveSale(draft('op-1'));
    repository.saveSale(
      SalesInvoiceDraft(
        tenantId: 'tenant-a',
        branchId: 'branch-a',
        branchCode: 'MAIN',
        deviceId: 'device-a',
        creatorUserId: 'user-a',
        creatorDisplayName: 'موظف المبيعات',
        localOperationId: 'op-2',
        paidMinor: 10000,
        occurredAt: DateTime.utc(2026, 10, 12),
        lines: const [
          InvoiceLineDraft(
            name: '  طابعة   حرارية ',
            kind: 'stock',
            quantityMilli: 1000,
            unitPriceMinor: 10000,
            purchaseCostMinor: 6000,
          ),
        ],
      ),
    );
    expect(database.select('SELECT * FROM products'), hasLength(1));
  });
}
