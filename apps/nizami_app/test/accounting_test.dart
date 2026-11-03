import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/domain/accounting/money.dart';
import 'package:nizami/src/domain/invoices/sales_posting_service.dart';

void main() {
  group('SalesPostingService', () {
    const service = SalesPostingService();

    test(
      'posts balanced cash, receivable, revenue, COGS and inventory entries',
      () {
        final entries = service.post(
          invoiceId: 'inv-01',
          total: const Money(10000),
          paid: const Money(4000),
          costOfGoodsSold: const Money(5500),
        );
        expect(entries, hasLength(2));
        expect(entries.every((entry) => entry.isBalanced), isTrue);
        expect(
          entries.first.lines.map((line) => line.accountCode),
          containsAll(['1100-CASH', '1200-AR', '4100-SALES']),
        );
        expect(
          entries.last.lines.map((line) => line.accountCode),
          containsAll(['5100-COGS', '1300-INVENTORY']),
        );
        expect(entries.last.referenceId, 'inv-01');
      },
    );

    test('rejects overpayment at invoice-posting layer', () {
      expect(
        () => service.post(
          invoiceId: 'inv-02',
          total: const Money(1000),
          paid: const Money(1001),
          costOfGoodsSold: const Money(0),
        ),
        throwsArgumentError,
      );
    });
  });
}
