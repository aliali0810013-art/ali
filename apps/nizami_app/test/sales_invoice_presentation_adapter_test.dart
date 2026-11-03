import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/invoices/presentation/sales_invoice_adapter.dart';

void main() {
  test('sales invoice presentation adapter preserves legacy document data', () {
    final original = InvoiceDocument(
      number: 'INV-1542',
      customerName: 'مؤسسة النور للتجارة',
      customerPhone: '551234567',
      customerId: 'customer-1',
      lines: const [
        InvoiceLine(
          name: 'لابتوب 15 بوصة',
          quantity: 2,
          unitPrice: 800,
          productId: 'product-1',
          saleOptionId: 'option-1',
          optionUnitCode: 'piece',
          optionQuantity: 1,
          displayUnit: 'حبة',
          exactQuantityMilli: 2000,
          priceNumeratorMinor: 80000,
          priceDenominator: 1,
          priceOverridden: false,
          lineDiscountMinor: 16000,
          weightGramsMilli: null,
          pendingCatalogSync: true,
        ),
      ],
      currency: 'YER',
      employeeName: 'أحمد سالم',
      branchLabel: 'الفرع الرئيسي',
      createdAt: DateTime.utc(2026, 11, 3, 10, 24),
      paymentMode: 'credit',
      paidAmount: 1000,
      discountAmount: 50,
      amountTendered: 1200,
      paymentChannel: 'bank',
      paymentAccountCode: '1112',
      notes: 'ملاحظة قديمة',
      localOperationId: 'local-1',
      serverInvoiceId: 'server-1',
      serverNumber: '1542',
      replacementInvoiceId: 'replacement-1',
      restoreGenerationAtCreation: 7,
      serverTotalMinor: 150000,
      currentPaidMinor: 100000,
      currentDueMinor: 50000,
      returnedMinor: 1000,
      isDraft: true,
      quarantineReason: 'legacy-review',
    );

    final viewModel = SalesInvoicePresentationAdapter.fromDomain(original);
    final restored = SalesInvoicePresentationAdapter.toDomain(viewModel);

    expect(restored.toJson(), original.toJson());
  });
}
