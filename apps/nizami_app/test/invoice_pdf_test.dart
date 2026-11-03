import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/settings/business_identity_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arabic invoice PDF is generated with meaningful content', () async {
    final bytes = await buildInvoicePdf(
      invoice: InvoiceDocument(
        number: 'INV-1001',
        customerName: 'عميل تجريبي',
        customerPhone: '967700000000',
        lines: List.generate(
          15,
          (index) => InvoiceLine(
            name: 'صنف تجريبي ${index + 1}',
            quantity: index + 1,
            unitPrice: 1500 + (index * 100),
          ),
        ),
        currency: 'YER',
        employeeName: 'مدير النظام',
        branchLabel: 'الفرع 1',
        createdAt: DateTime(2026, 10, 14, 12, 30),
      ),
      profile: const BranchBusinessProfile(
        branchId: 'MAIN',
        businessName: 'مؤسسة الاختبار',
        phone: '9671000000',
        address: 'صنعاء - اليمن',
      ),
    );

    expect(bytes.length, greaterThan(10000));
    expect(bytes.take(4), orderedEquals([0x25, 0x50, 0x44, 0x46]));

    const sampleOutput = String.fromEnvironment('NINESOFT_PDF_SAMPLE_OUTPUT');
    if (sampleOutput.isNotEmpty) {
      await File(sampleOutput).writeAsBytes(bytes, flush: true);
    }
  });

  test('thermal invoice supports many items and remains a valid PDF', () async {
    final invoice = InvoiceDocument(
      number: 'INV-20261024-001',
      customerName: 'عميل نقدي',
      customerPhone: '771507715',
      lines: List.generate(
        35,
        (index) => InvoiceLine(
          name: 'صنف ${index + 1}',
          quantity: (index % 3) + 1,
          unitPrice: 100.0 + index,
        ),
      ),
      currency: 'YER',
      employeeName: 'System Owner',
      branchLabel: '',
      createdAt: DateTime(2026, 10, 24, 9, 5),
    );
    const profile = BranchBusinessProfile(
      branchId: 'MAIN',
      businessName: 'ناين فود',
      businessNameEn: 'NINE FOODS',
      phone: '771507715',
      email: 'qodynex@gmail.com',
      address: 'صنعاء - اليمن',
    );

    final bytes = await buildThermalInvoicePdf(
      invoice: invoice,
      profile: profile,
    );

    expect(bytes.length, greaterThan(10000));
    expect(bytes.take(4), orderedEquals([0x25, 0x50, 0x44, 0x46]));

    const sampleOutput = String.fromEnvironment(
      'NINESOFT_THERMAL_PDF_SAMPLE_OUTPUT',
    );
    if (sampleOutput.isNotEmpty) {
      await File(sampleOutput).writeAsBytes(bytes, flush: true);
    }
  });

  test('discount, remaining balance, and returned cash are independent', () {
    InvoiceDocument invoice({required double tendered, required double paid}) =>
        InvoiceDocument(
          number: 'INV-CALC-1',
          customerName: 'Customer',
          customerPhone: '',
          lines: const [InvoiceLine(name: 'Item', quantity: 2, unitPrice: 100)],
          currency: 'YER',
          employeeName: 'Owner',
          branchLabel: '',
          createdAt: DateTime(2026, 10, 24),
          discountAmount: 20,
          amountTendered: tendered,
          paidAmount: paid,
        );

    final cash = invoice(tendered: 200, paid: 180);
    expect(cash.subtotal, 200);
    expect(cash.total, 180);
    expect(cash.dueAmount, 0);
    expect(cash.returnAmount, 20);

    final credit = invoice(tendered: 50, paid: 50);
    expect(credit.total, 180);
    expect(credit.dueAmount, 130);
    expect(credit.returnAmount, 0);
  });

  test(
    'exact display unit and quantity survive JSON without changing legacy rows',
    () {
      const exact = InvoiceLine(
        name: 'كمون',
        quantity: 250,
        unitPrice: 0.01,
        displayUnit: 'ملليجرام',
        exactQuantityMilli: 250000,
        priceNumeratorMinor: 500000,
        priceDenominator: 1000000,
      );
      final restored = InvoiceLine.fromJson(exact.toJson());
      expect(restored.displayUnit, 'ملليجرام');
      expect(restored.exactQuantityMilli, 250000);
      expect(restored.displayQuantity, '250 ملليجرام');
      expect(restored.displayUnitPrice, '0.005');
      expect(restored.totalMinor, 125);

      final legacy = InvoiceLine.fromJson({
        'name': 'قديم',
        'quantity': 2,
        'unitPrice': 10,
      });
      expect(legacy.displayUnit, isEmpty);
      expect(legacy.displayQuantity, '2');
      expect(legacy.displayUnitPrice, '10.00');
      expect(legacy.totalMinor, 2000);
    },
  );

  test(
    'variable pack rational authority survives history JSON and PDF',
    () async {
      final lines = <InvoiceLine>[];
      for (final scenario in const [
        (factor: 6, preview: 1666.67, exact: '1000001/600'),
        (factor: 12, preview: 833.33, exact: '1000001/1200'),
        (factor: 24, preview: 416.67, exact: '1000001/2400'),
        (factor: 100, preview: 100.00, exact: '100.0001'),
      ]) {
        final restored = InvoiceLine.fromJson(
          InvoiceLine(
            name: 'Pack ${scenario.factor}',
            quantity: scenario.factor.toDouble(),
            unitPrice: scenario.preview,
            displayUnit: 'piece',
            exactQuantityMilli: scenario.factor * 1000,
            priceNumeratorMinor: 1000001,
            priceDenominator: scenario.factor,
          ).toJson(),
        );
        expect(restored.priceNumeratorMinor, 1000001);
        expect(restored.priceDenominator, scenario.factor);
        expect(restored.totalMinor, 1000001);
        expect(restored.displayUnitPrice, scenario.exact);
        lines.add(restored);
      }
      final invoice = InvoiceDocument(
        number: 'INV-VARIABLE-PACKS',
        customerName: 'Customer',
        customerPhone: '',
        lines: lines,
        currency: 'YER',
        employeeName: 'Owner',
        branchLabel: 'Main',
        createdAt: DateTime(2026, 11, 1),
      );
      const profile = BranchBusinessProfile(
        branchId: 'MAIN',
        businessName: 'NineSoft',
      );

      final standard = await buildInvoicePdf(
        invoice: invoice,
        profile: profile,
      );
      final thermal = await buildThermalInvoicePdf(
        invoice: invoice,
        profile: profile,
      );

      const referenceOutput = String.fromEnvironment(
        'NINESOFT_THERMAL_REFERENCE_OUTPUT',
      );
      if (referenceOutput.isNotEmpty) {
        await File(referenceOutput).writeAsBytes(thermal, flush: true);
      }

      expect(standard.take(4), orderedEquals([0x25, 0x50, 0x44, 0x46]));
      expect(thermal.take(4), orderedEquals([0x25, 0x50, 0x44, 0x46]));
    },
  );

  test('standard and thermal layouts render complete receipt data', () async {
    final invoice = InvoiceDocument(
      number: 'INV-COMPLETE-1',
      customerName: 'عميل كامل',
      customerPhone: '777000111',
      lines: const [
        InvoiceLine(
          name: 'كمون',
          quantity: 2,
          unitPrice: 500,
          displayUnit: 'كرتون',
        ),
      ],
      currency: 'YER',
      employeeName: 'أمين الصندوق',
      branchLabel: 'المخزن الرئيسي',
      createdAt: DateTime(2026, 11, 1, 10, 16),
    );
    const profile = BranchBusinessProfile(
      branchId: 'MAIN',
      businessName: 'NineSoft',
    );

    final standard = await buildInvoicePdf(invoice: invoice, profile: profile);
    final thermal = await buildThermalInvoicePdf(
      invoice: invoice,
      profile: profile,
    );

    expect(standard.length, greaterThan(10000));
    expect(thermal.length, greaterThan(10000));
  });
}
