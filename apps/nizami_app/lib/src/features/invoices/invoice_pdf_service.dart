import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../settings/business_identity_store.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../accounting/minor_allocation.dart';
import '../products/unit_conversion_math.dart';

class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.productId = '',
    this.saleOptionId = '',
    this.optionUnitCode = '',
    this.optionQuantity,
    this.optionMassG,
    this.displayUnit = '',
    this.exactQuantityMilli,
    this.priceNumeratorMinor,
    this.priceDenominator,
    this.priceOverridden = false,
    this.lineDiscountMinor = 0,
    this.weightGramsMilli,
    this.pendingCatalogSync = false,
  });
  final String name;
  final double quantity;
  final double unitPrice;
  final String productId;
  final String saleOptionId;
  final String optionUnitCode;
  final double? optionQuantity;
  final double? optionMassG;
  final String displayUnit;
  final int? exactQuantityMilli;
  final int? priceNumeratorMinor;
  final int? priceDenominator;
  final bool priceOverridden;
  int? get priceNumeratorMinorSnapshot => priceNumeratorMinor;
  int? get priceDenominatorSnapshot => priceDenominator;

  /// Minor-unit price adjustment for selling a weighed product by an exact amount.
  /// This is part of the posted line discount, not a fictitious tax/fee.
  final int lineDiscountMinor;

  /// Optional display snapshot in milli-grams (not used by stock posting).
  final int? weightGramsMilli;

  /// True for a locally drafted stock product that has no canonical server ID.
  /// Such a line may be saved as a local draft but cannot be submitted.
  final bool pendingCatalogSync;
  int get grossMinor {
    final numerator = priceNumeratorMinor;
    final denominator = priceDenominator;
    if (numerator != null && denominator != null) {
      return ExactUnitPrice.grossMinor(
        quantityMilli: exactQuantityMilli ?? (quantity * 1000).round(),
        priceNumeratorMinor: numerator,
        priceDenominator: denominator,
      );
    }
    return MinorAllocation.lineGross(
      exactQuantityMilli ?? (quantity * 1000).round(),
      (unitPrice * 100).round(),
    );
  }

  int get totalMinor => grossMinor - lineDiscountMinor;
  double get total => totalMinor / 100;
  String get optionLabel {
    if (optionUnitCode.isEmpty || optionQuantity == null) return '';
    const labels = <String, String>{
      'gram': 'جرام',
      'kilogram': 'كيلو',
      'piece': 'قطعة',
      'item': 'حبة',
      'bundle': 'شدة',
      'box': 'صندوق',
      'carton': 'كرتون',
      'bag': 'كيس',
      'pack': 'باكت',
      'liter': 'لتر',
      'milliliter': 'ملليلتر',
      'dozen': 'درزن',
    };
    final amount = optionQuantity! % 1 == 0
        ? optionQuantity!.toStringAsFixed(0)
        : optionQuantity!.toStringAsFixed(3);
    return '$amount ${labels[optionUnitCode] ?? optionUnitCode}';
  }

  static const _unitLabels = <String, String>{
    'gram': 'جرام',
    'kilogram': 'كيلو',
    'milligram': 'ملليجرام',
    'piece': 'قطعة',
    'item': 'حبة',
    'bundle': 'شدة',
    'box': 'صندوق',
    'carton': 'كرتون',
    'bag': 'كيس',
    'pack': 'باكت',
    'liter': 'لتر',
    'milliliter': 'ملليلتر',
    'dozen': 'درزن',
  };

  String get resolvedDisplayUnit => displayUnit.isNotEmpty
      ? displayUnit
      : (_unitLabels[optionUnitCode] ?? optionUnitCode);

  String get displayQuantity {
    final milli = exactQuantityMilli ?? (quantity * 1000).round();
    final value = milli % 1000 == 0
        ? '${milli ~/ 1000}'
        : (milli / 1000)
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    return resolvedDisplayUnit.isEmpty ? value : '$value $resolvedDisplayUnit';
  }

  String get displayQuantityValue {
    final milli = exactQuantityMilli ?? (quantity * 1000).round();
    return milli % 1000 == 0
        ? '${milli ~/ 1000}'
        : (milli / 1000)
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  /// Exact unit price shown to the cashier and on exported invoices.
  /// A rational option can be smaller than one minor currency unit, so the
  /// legacy two-decimal preview is not authoritative for display.
  String get displayUnitPrice {
    final numerator = priceNumeratorMinor;
    final denominator = priceDenominator;
    if (numerator == null || denominator == null) {
      return unitPrice.toStringAsFixed(2);
    }
    var reducedNumerator = BigInt.from(numerator);
    var reducedDenominator = BigInt.from(denominator) * BigInt.from(100);
    final divisor = reducedNumerator.gcd(reducedDenominator);
    reducedNumerator ~/= divisor;
    reducedDenominator ~/= divisor;
    var twos = 0;
    var fives = 0;
    var remainder = reducedDenominator;
    while (remainder.isEven) {
      remainder ~/= BigInt.two;
      twos++;
    }
    while (remainder % BigInt.from(5) == BigInt.zero) {
      remainder ~/= BigInt.from(5);
      fives++;
    }
    if (remainder != BigInt.one) {
      return '$reducedNumerator/$reducedDenominator';
    }
    final decimals = twos > fives ? twos : fives;
    final scaled =
        reducedNumerator *
        BigInt.two.pow(decimals - twos) *
        BigInt.from(5).pow(decimals - fives);
    if (decimals == 0) return scaled.toString();
    final digits = scaled.toString().padLeft(decimals + 1, '0');
    final whole = digits.substring(0, digits.length - decimals);
    final fraction = digits
        .substring(digits.length - decimals)
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '$whole.$fraction';
  }

  String get displayName => optionLabel.isEmpty ? name : '$name — $optionLabel';
  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    name: json['name']?.toString() ?? '',
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    productId: json['productId']?.toString() ?? '',
    saleOptionId: json['saleOptionId']?.toString() ?? '',
    optionUnitCode: json['optionUnitCode']?.toString() ?? '',
    optionQuantity: (json['optionQuantity'] as num?)?.toDouble(),
    optionMassG: (json['optionMassG'] as num?)?.toDouble(),
    displayUnit: json['displayUnit']?.toString() ?? '',
    exactQuantityMilli: (json['exactQuantityMilli'] as num?)?.toInt(),
    priceNumeratorMinor: (json['priceNumeratorMinor'] as num?)?.toInt(),
    priceDenominator: (json['priceDenominator'] as num?)?.toInt(),
    priceOverridden: json['priceOverridden'] == true,
    lineDiscountMinor: (json['lineDiscountMinor'] as num?)?.toInt() ?? 0,
    weightGramsMilli: (json['weightGramsMilli'] as num?)?.toInt(),
    pendingCatalogSync: json['pendingCatalogSync'] == true,
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'productId': productId,
    'saleOptionId': saleOptionId,
    'optionUnitCode': optionUnitCode,
    'optionQuantity': optionQuantity,
    'optionMassG': optionMassG,
    'displayUnit': displayUnit,
    'exactQuantityMilli': exactQuantityMilli,
    'priceNumeratorMinor': priceNumeratorMinor,
    'priceDenominator': priceDenominator,
    'priceOverridden': priceOverridden,
    'lineDiscountMinor': lineDiscountMinor,
    'weightGramsMilli': weightGramsMilli,
    'pendingCatalogSync': pendingCatalogSync,
  };
}

class InvoiceDocument {
  const InvoiceDocument({
    required this.number,
    required this.customerName,
    required this.customerPhone,
    this.customerId = '',
    required this.lines,
    required this.currency,
    required this.employeeName,
    required this.branchLabel,
    required this.createdAt,
    this.paymentMode = 'cash',
    this.paidAmount = 0,
    this.discountAmount = 0,
    this.amountTendered = 0,
    this.paymentChannel = '',
    this.paymentAccountCode = '',
    this.notes = '',
    this.localOperationId = '',
    this.serverInvoiceId = '',
    this.serverNumber = '',
    this.replacementInvoiceId = '',
    this.restoreGenerationAtCreation = 0,
    this.serverTotalMinor,
    this.currentPaidMinor,
    this.currentDueMinor,
    this.returnedMinor = 0,
    this.isDraft = false,
    this.quarantineReason = '',
  });
  final String number;
  final String customerName;
  final String customerPhone;
  final String customerId;
  final List<InvoiceLine> lines;
  final String currency;
  final String employeeName;
  final String branchLabel;
  final DateTime createdAt;
  final String paymentMode;
  final double paidAmount;
  final double discountAmount;
  final double amountTendered;
  final String paymentChannel;
  final String paymentAccountCode;
  final String notes;
  final String localOperationId;
  final String serverInvoiceId;
  final String serverNumber;
  final String replacementInvoiceId;

  /// Immutable restore generation captured when the local operation is born.
  /// It must never be replaced with the device's current generation on retry.
  final int restoreGenerationAtCreation;
  final int? serverTotalMinor, currentPaidMinor, currentDueMinor;
  final int returnedMinor;
  final bool isDraft;
  final String quarantineReason;
  bool get isQuarantined => quarantineReason.isNotEmpty;
  double get currentPaidAmount =>
      currentPaidMinor == null ? paidAmount : currentPaidMinor! / 100;
  double get currentDueAmount =>
      currentDueMinor == null ? dueAmount : currentDueMinor! / 100;
  double get returnedAmount => returnedMinor / 100;
  String get currentPaymentLabel =>
      currentDueAmount > 0 ? 'متبقٍ سداد' : 'مسددة/مسواة';
  String get displayNumber => serverNumber.isEmpty ? number : serverNumber;
  bool get postedToServer => serverInvoiceId.isNotEmpty;
  double get subtotal => lines.fold(0, (sum, line) => sum + line.total);
  double get total => serverTotalMinor == null
      ? (subtotal - discountAmount).clamp(0, double.infinity)
      : serverTotalMinor! / 100;
  double get returnAmount => (amountTendered - total).clamp(0, double.infinity);
  double get dueAmount => (total - paidAmount).clamp(0, double.infinity);
  bool get isCredit => paymentMode == 'credit' || dueAmount > 0;
  String get paymentLabel => isCredit ? 'آجل' : 'مدفوع';
  String get itemName => lines.isEmpty ? '' : lines.first.name;
  double get quantity => lines.isEmpty ? 1 : lines.first.quantity;
  double get unitPrice => lines.isEmpty ? 0 : lines.first.unitPrice;

  factory InvoiceDocument.fromJson(Map<String, dynamic> json) {
    final decodedLines =
        (json['lines'] as List?)
            ?.whereType<Map>()
            .map(
              (value) => InvoiceLine.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList() ??
        [];
    return InvoiceDocument(
      serverTotalMinor: (json['serverTotalMinor'] as num?)?.toInt(),
      currentPaidMinor: (json['currentPaidMinor'] as num?)?.toInt(),
      currentDueMinor: (json['currentDueMinor'] as num?)?.toInt(),
      returnedMinor: (json['returnedMinor'] as num?)?.toInt() ?? 0,
      isDraft: json['isDraft'] == true,
      quarantineReason: json['quarantineReason']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      lines: decodedLines.isNotEmpty
          ? decodedLines
          : [
              InvoiceLine(
                name: json['itemName']?.toString() ?? '',
                quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
                unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
              ),
            ],
      currency: json['currency']?.toString() ?? 'YER',
      employeeName: json['employeeName']?.toString() ?? '',
      branchLabel: json['branchLabel']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      paymentMode: json['paymentMode']?.toString() ?? 'cash',
      paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
      amountTendered:
          (json['amountTendered'] as num?)?.toDouble() ??
          (json['paidAmount'] as num?)?.toDouble() ??
          0,
      paymentChannel: json['paymentChannel']?.toString() ?? '',
      paymentAccountCode: json['paymentAccountCode']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      localOperationId: json['localOperationId']?.toString() ?? '',
      serverInvoiceId: json['serverInvoiceId']?.toString() ?? '',
      serverNumber: json['serverNumber']?.toString() ?? '',
      replacementInvoiceId: json['replacementInvoiceId']?.toString() ?? '',
      restoreGenerationAtCreation:
          (json['restoreGenerationAtCreation'] as num?)?.toInt() ?? 0,
    );
  }
  factory InvoiceDocument.fromServer(Map<String, dynamic> value) {
    final lines = (value['items'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) {
          final item = Map<String, dynamic>.from(raw);
          return InvoiceLine(
            name: item['product_name_snapshot']?.toString() ?? '',
            quantity:
                ((item['quantity_milli'] as num?)?.toInt() ?? 1000) / 1000,
            unitPrice:
                ((item['unit_price_minor'] as num?)?.toDouble() ?? 0) / 100,
            productId: item['product_id']?.toString() ?? '',
            saleOptionId: item['sale_option_id']?.toString() ?? '',
            optionUnitCode: item['option_unit_code_snapshot']?.toString() ?? '',
            optionQuantity: double.tryParse(
              item['option_quantity_snapshot']?.toString() ?? '',
            ),
            optionMassG: double.tryParse(
              item['option_mass_g_snapshot']?.toString() ?? '',
            ),
            displayUnit:
                item['display_unit_snapshot']?.toString() ??
                item['option_unit_code_snapshot']?.toString() ??
                '',
            exactQuantityMilli: (item['quantity_milli'] as num?)?.toInt(),
            priceNumeratorMinor:
                (item['price_numerator_minor_snapshot'] as num?)?.toInt(),
            priceDenominator: (item['price_denominator_snapshot'] as num?)
                ?.toInt(),
            priceOverridden: item['price_overridden'] == true,
            lineDiscountMinor: (item['discount_minor'] as num?)?.toInt() ?? 0,
            weightGramsMilli: (item['weight_grams_milli_snapshot'] as num?)
                ?.toInt(),
          );
        })
        .toList(growable: false);
    final total = (value['total_minor'] as num?)?.toInt() ?? 0;
    final initialPaid =
        (value['initial_paid_minor'] as num?)?.toInt() ??
        (value['paid_minor'] as num?)?.toInt() ??
        0;
    return InvoiceDocument(
      serverTotalMinor: (value['total_minor'] as num?)?.toInt(),
      currentPaidMinor: (value['paid_minor'] as num?)?.toInt(),
      currentDueMinor: (value['due_minor'] as num?)?.toInt(),
      returnedMinor: (value['returned_minor'] as num?)?.toInt() ?? 0,
      number: value['number']?.toString() ?? '',
      customerName: value['customer_name']?.toString().trim().isNotEmpty == true
          ? value['customer_name'].toString()
          : 'عميل نقدي',
      customerPhone: value['customer_phone']?.toString() ?? '',
      customerId: value['contact_id']?.toString() ?? '',
      lines: lines,
      currency: 'YER',
      employeeName: value['creator_display_name']?.toString() ?? '',
      branchLabel: value['branch_label_snapshot']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(value['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      paymentMode:
          value['payment_mode_at_issue']?.toString() ??
          (initialPaid >= total ? 'cash' : 'credit'),
      paidAmount: initialPaid / 100,
      discountAmount: lines.isEmpty
          ? ((value['discount_minor'] as num?)?.toDouble() ?? 0) / 100
          : 0,
      amountTendered:
          ((value['amount_tendered_minor'] as num?)?.toDouble() ??
              initialPaid) /
          100,
      paymentChannel: value['payment_channel']?.toString() ?? '',
      paymentAccountCode: value['payment_account_code']?.toString() ?? '',
      notes: value['notes']?.toString() ?? '',
      localOperationId: value['local_operation_id']?.toString() ?? '',
      serverInvoiceId: value['id']?.toString() ?? '',
      serverNumber: value['number']?.toString() ?? '',
      restoreGenerationAtCreation:
          (value['restore_generation'] as num?)?.toInt() ?? 0,
    );
  }
  Map<String, dynamic> toJson() => {
    'number': number,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerId': customerId,
    'lines': lines.map((line) => line.toJson()).toList(),
    'currency': currency,
    'employeeName': employeeName,
    'branchLabel': branchLabel,
    'createdAt': createdAt.toIso8601String(),
    'paymentMode': paymentMode,
    'paidAmount': paidAmount,
    'discountAmount': discountAmount,
    'amountTendered': amountTendered,
    'paymentChannel': paymentChannel,
    'paymentAccountCode': paymentAccountCode,
    'notes': notes,
    'localOperationId': localOperationId,
    'serverInvoiceId': serverInvoiceId,
    'serverNumber': serverNumber,
    'replacementInvoiceId': replacementInvoiceId,
    'restoreGenerationAtCreation': restoreGenerationAtCreation,
    'serverTotalMinor': serverTotalMinor,
    'currentPaidMinor': currentPaidMinor,
    'currentDueMinor': currentDueMinor,
    'returnedMinor': returnedMinor,
    'isDraft': isDraft,
    'quarantineReason': quarantineReason,
  };

  InvoiceDocument rebasedToRestoreGeneration(int generation) {
    final json = toJson()
      ..['restoreGenerationAtCreation'] = generation
      ..['quarantineReason'] = '';
    return InvoiceDocument.fromJson(json);
  }

  InvoiceDocument quarantined(String reason) => InvoiceDocument(
    number: number,
    customerName: customerName,
    customerPhone: customerPhone,
    customerId: customerId,
    lines: lines,
    currency: currency,
    employeeName: employeeName,
    branchLabel: branchLabel,
    createdAt: createdAt,
    paymentMode: paymentMode,
    paidAmount: paidAmount,
    discountAmount: discountAmount,
    amountTendered: amountTendered,
    paymentChannel: paymentChannel,
    paymentAccountCode: paymentAccountCode,
    notes: notes,
    localOperationId: localOperationId,
    serverInvoiceId: serverInvoiceId,
    serverNumber: serverNumber,
    replacementInvoiceId: replacementInvoiceId,
    restoreGenerationAtCreation: restoreGenerationAtCreation,
    serverTotalMinor: serverTotalMinor,
    currentPaidMinor: currentPaidMinor,
    currentDueMinor: currentDueMinor,
    returnedMinor: returnedMinor,
    isDraft: false,
    quarantineReason: reason,
  );
}

Future<Uint8List> buildInvoicePdf({
  required InvoiceDocument invoice,
  required BranchBusinessProfile profile,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
  );
  final latinFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
  );
  final brand = PdfColor.fromInt(profile.primaryColorValue);
  const orange = PdfColor.fromInt(0xFFFF7900);
  const ink = PdfColor.fromInt(0xFF252B35);
  const softGreen = PdfColor.fromInt(0xFFEAF7F0);
  final logo = profile.logoBytes == null
      ? null
      : pw.MemoryImage(profile.logoBytes!);
  final document = pw.Document(
    title: 'فاتورة ${compactDocumentNumber(invoice.displayNumber)}',
    author: profile.businessName,
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5.landscape,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [latinFont],
      ),
      margin: const pw.EdgeInsets.all(14),
      build: (_) => pw.Container(
        width: double.infinity,
        height: double.infinity,
        color: PdfColors.white,
        child: pw.Column(
          children: [
            pw.Container(
              height: 68,
              padding: const pw.EdgeInsets.fromLTRB(10, 5, 10, 7),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: brand, width: 1.5),
                ),
              ),
              child: pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.ltr,
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (profile.phone.isNotEmpty)
                              _contactLine(
                                'هاتف',
                                profile.phone,
                                brand,
                                font,
                                latinFont,
                              ),
                            if (profile.email.isNotEmpty)
                              _contactLine(
                                'بريد',
                                profile.email,
                                brand,
                                font,
                                latinFont,
                              ),
                            if (profile.address.isNotEmpty)
                              _contactLine(
                                'العنوان',
                                profile.address,
                                brand,
                                font,
                                latinFont,
                              ),
                          ],
                        ),
                      ),
                    ),
                    pw.Container(
                      width: .7,
                      height: 41,
                      color: PdfColors.grey300,
                    ),
                    pw.Container(
                      width: 92,
                      height: 57,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                      alignment: pw.Alignment.center,
                      child: logo == null
                          ? pw.Container(
                              width: 44,
                              height: 44,
                              alignment: pw.Alignment.center,
                              decoration: pw.BoxDecoration(
                                color: orange,
                                shape: pw.BoxShape.circle,
                              ),
                              child: pw.Text(
                                '9',
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontSize: 25,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            )
                          : pw.Transform.scale(
                              scale: profile.logoScale.clamp(.55, 1.65),
                              child: pw.Image(
                                logo,
                                width: 70,
                                height: 48,
                                fit: pw.BoxFit.contain,
                              ),
                            ),
                    ),
                    pw.Container(
                      width: .7,
                      height: 41,
                      color: PdfColors.grey300,
                    ),
                    pw.Expanded(
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _mixedPdfText(
                              profile.businessName,
                              font,
                              latinFont,
                              fontSize: 15,
                              color: brand,
                              bold: true,
                            ),
                            if (profile.businessNameEn.isNotEmpty)
                              pw.Text(
                                profile.businessNameEn,
                                textDirection: pw.TextDirection.ltr,
                                maxLines: 1,
                                style: pw.TextStyle(
                                  font: latinFont,
                                  fontSize: 9,
                                  color: ink,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            pw.SizedBox(height: 2),
                            if (profile.tagline.isNotEmpty)
                              pw.Text(
                                profile.tagline,
                                maxLines: 2,
                                style: const pw.TextStyle(
                                  fontSize: 7,
                                  color: ink,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      height: 34,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12),
                      decoration: pw.BoxDecoration(
                        color: brand,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Row(
                          children: [
                            pw.Text(
                              'فاتورة مبيعات',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Spacer(),
                            pw.Container(
                              width: 25,
                              height: 25,
                              alignment: pw.Alignment.center,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(
                                  color: PdfColors.white,
                                  width: 1,
                                ),
                                borderRadius: pw.BorderRadius.circular(5),
                              ),
                              child: pw.SvgImage(
                                svg: _documentIconSvg,
                                width: 14,
                                height: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    flex: 6,
                    child: pw.Container(
                      height: 34,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                      decoration: pw.BoxDecoration(
                        color: softGreen,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              child: _meta(
                                'رقم الفاتورة',
                                compactDocumentNumber(invoice.displayNumber),
                                font,
                                latinFont,
                              ),
                            ),
                            pw.Container(
                              width: .7,
                              height: 25,
                              color: PdfColors.grey400,
                            ),
                            pw.Expanded(
                              child: _meta(
                                'تاريخ الفاتورة',
                                _date(invoice.createdAt),
                                font,
                                latinFont,
                              ),
                            ),
                            pw.Container(
                              width: .7,
                              height: 25,
                              color: PdfColors.grey400,
                            ),
                            pw.Expanded(
                              child: _meta(
                                'حالة الدفع',
                                invoice.paymentLabel,
                                font,
                                latinFont,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              height: 37,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                border: pw.Border.all(color: PdfColors.grey300, width: .6),
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: _meta(
                      'العميل',
                      invoice.customerName,
                      font,
                      latinFont,
                    ),
                  ),
                  pw.Container(width: .6, height: 25, color: PdfColors.grey300),
                  pw.Expanded(
                    child: _meta(
                      'الجوال',
                      invoice.customerPhone.isEmpty
                          ? '-'
                          : invoice.customerPhone,
                      font,
                      latinFont,
                    ),
                  ),
                  pw.Container(width: .6, height: 25, color: PdfColors.grey300),
                  pw.Expanded(
                    child: _meta(
                      'الموظف',
                      invoice.employeeName,
                      font,
                      latinFont,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                border: pw.Border.all(color: PdfColors.grey300, width: .6),
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: _meta(
                'المخزن / الفرع',
                invoice.branchLabel.isEmpty ? '-' : invoice.branchLabel,
                font,
                latinFont,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              columnWidths: const {
                0: pw.FixedColumnWidth(25),
                1: pw.FlexColumnWidth(3.6),
                2: pw.FlexColumnWidth(1.05),
                3: pw.FlexColumnWidth(1.15),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(1.9),
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .45),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: brand),
                  children: [
                    for (final value in const [
                      '#',
                      'الصنف / الخدمة',
                      'الوحدة',
                      'الكمية',
                      'السعر',
                      'الإجمالي',
                    ])
                      _invoiceTableCell(
                        value,
                        font,
                        latinFont,
                        isHeader: true,
                        compact: invoice.lines.length > 12,
                      ),
                  ],
                ),
                for (var i = 0; i < invoice.lines.length; i++)
                  pw.TableRow(
                    decoration: i.isOdd
                        ? const pw.BoxDecoration(color: PdfColors.grey50)
                        : null,
                    children: [
                      _invoiceTableCell(
                        '${i + 1}',
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                      _invoiceTableCell(
                        invoice.lines[i].displayName,
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                      _invoiceTableCell(
                        invoice.lines[i].resolvedDisplayUnit.isEmpty
                            ? '-'
                            : invoice.lines[i].resolvedDisplayUnit,
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                      _invoiceTableCell(
                        invoice.lines[i].displayQuantityValue,
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                      _invoiceTableCell(
                        '${invoice.lines[i].displayUnitPrice} ${invoice.currency}',
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                      _invoiceTableCell(
                        _money(invoice.lines[i].total, invoice.currency),
                        font,
                        latinFont,
                        compact: invoice.lines.length > 12,
                      ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Container(
                        constraints: const pw.BoxConstraints(minHeight: 30),
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey50,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: _mixedPdfText(
                          invoice.notes.isEmpty
                              ? 'ملاحظات: ${profile.footer}'
                              : 'ملاحظات: ${invoice.notes}',
                          font,
                          latinFont,
                          fontSize: 6.5,
                          color: ink,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Container(
                    width: 220,
                    height: 37,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                    decoration: pw.BoxDecoration(
                      color: softGreen,
                      borderRadius: pw.BorderRadius.circular(7),
                    ),
                    child: pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Row(
                        children: [
                          pw.Text(
                            'الإجمالي الكلي',
                            style: pw.TextStyle(
                              color: brand,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Spacer(),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: pw.BoxDecoration(
                              color: brand,
                              borderRadius: pw.BorderRadius.circular(5),
                            ),
                            child: pw.Text(
                              _money(invoice.total, invoice.currency),
                              textDirection: pw.TextDirection.ltr,
                              style: pw.TextStyle(
                                font: latinFont,
                                color: PdfColors.white,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (invoice.discountAmount > 0)
                    _invoiceSummaryAmount(
                      'الخصم',
                      invoice.discountAmount,
                      invoice.currency,
                      latinFont,
                    ),
                  _invoiceSummaryAmount(
                    'المدفوع',
                    invoice.paidAmount,
                    invoice.currency,
                    latinFont,
                  ),
                  if (invoice.dueAmount > 0)
                    _invoiceSummaryAmount(
                      'المتبقي',
                      invoice.dueAmount,
                      invoice.currency,
                      latinFont,
                    ),
                  if (invoice.returnAmount > 0)
                    _invoiceSummaryAmount(
                      'المرتجع',
                      invoice.returnAmount,
                      invoice.currency,
                      latinFont,
                    ),
                  if (invoice.paymentChannel.isNotEmpty)
                    pw.Text(
                      'نوع الدفع: ${invoice.paymentChannel == 'bank' ? 'تحويل' : 'نقدًا'}',
                      style: const pw.TextStyle(fontSize: 6.5),
                    ),
                ],
              ),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 5),
              padding: const pw.EdgeInsets.only(top: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: brand, width: .8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Container(width: 27, height: .6, color: PdfColors.grey400),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    profile.footer.isEmpty
                        ? 'شكراً لتعاملكم معنا'
                        : profile.footer,
                    style: const pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Container(width: 27, height: .6, color: PdfColors.grey400),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return document.save();
}

/// Builds a compact 80mm receipt for supermarket and point-of-sale printers.
/// It is generated from the saved structured invoice, so no image copy is
/// stored and later restores always render with the branch's current identity.
Future<Uint8List> buildThermalInvoicePdf({
  required InvoiceDocument invoice,
  required BranchBusinessProfile profile,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
  );
  final latinFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
  );
  final logo = profile.logoBytes == null
      ? null
      : pw.MemoryImage(profile.logoBytes!);
  final heightMm = (100 + invoice.lines.length * 8.2)
      .clamp(125, 420)
      .toDouble();
  final document = pw.Document(
    title: 'فاتورة مبسطة ${compactDocumentNumber(invoice.displayNumber)}',
    author: profile.businessName,
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        80 * PdfPageFormat.mm,
        heightMm * PdfPageFormat.mm,
      ),
      margin: const pw.EdgeInsets.fromLTRB(7, 7, 7, 8),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [latinFont],
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: .55, color: PdfColors.grey700),
            ),
            child: pw.Column(
              children: [
                if (logo != null)
                  pw.Image(logo, width: 34, height: 28, fit: pw.BoxFit.contain),
                pw.Text(
                  profile.businessName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (profile.businessNameEn.isNotEmpty)
                  pw.Text(
                    profile.businessNameEn,
                    textDirection: pw.TextDirection.ltr,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: latinFont,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (profile.phone.isNotEmpty)
                  pw.Text(
                    'الهاتف: ${profile.phone}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 6.5),
                  ),
                if (profile.address.isNotEmpty)
                  pw.Text(
                    profile.address,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 6.5),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'فاتورة بيع ${invoice.isCredit ? 'آجل' : 'نقد'}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: .55, color: PdfColors.grey700),
            ),
            child: pw.Column(
              children: [
                _thermalPair(
                  'رقم الفاتورة',
                  compactDocumentNumber(invoice.displayNumber),
                  font,
                  latinFont,
                ),
                _thermalPair(
                  'التاريخ',
                  _receiptDateTime(invoice.createdAt),
                  font,
                  latinFont,
                ),
                _thermalPair(
                  'المخزن / الفرع',
                  invoice.branchLabel.isEmpty ? '-' : invoice.branchLabel,
                  font,
                  latinFont,
                ),
                if (invoice.customerName.isNotEmpty)
                  _thermalPair('العميل', invoice.customerName, font, latinFont),
                if (invoice.customerPhone.isNotEmpty)
                  _thermalPair(
                    'هاتف العميل',
                    invoice.customerPhone,
                    font,
                    latinFont,
                  ),
                if (invoice.employeeName.isNotEmpty)
                  _thermalPair(
                    'المستخدم',
                    invoice.employeeName,
                    font,
                    latinFont,
                  ),
                _thermalPair(
                  'حالة الدفع',
                  invoice.paymentLabel,
                  font,
                  latinFont,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.35),
              1: pw.FlexColumnWidth(1.25),
              2: pw.FlexColumnWidth(.8),
              3: pw.FlexColumnWidth(.8),
              4: pw.FlexColumnWidth(2.8),
            },
            border: const pw.TableBorder(
              left: pw.BorderSide(width: .55),
              right: pw.BorderSide(width: .55),
              top: pw.BorderSide(width: .55),
              bottom: pw.BorderSide(width: .55),
              horizontalInside: pw.BorderSide(
                width: .35,
                color: PdfColors.grey500,
              ),
              verticalInside: pw.BorderSide(
                width: .35,
                color: PdfColors.grey500,
              ),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _thermalCell('الإجمالي', font, latinFont, header: true),
                  _thermalCell('السعر', font, latinFont, header: true),
                  _thermalCell('الكمية', font, latinFont, header: true),
                  _thermalCell('الوحدة', font, latinFont, header: true),
                  _thermalCell('اسم الصنف', font, latinFont, header: true),
                ],
              ),
              ...invoice.lines.map(
                (line) => pw.TableRow(
                  children: [
                    _thermalCell(
                      line.total.toStringAsFixed(2),
                      font,
                      latinFont,
                    ),
                    _thermalCell(line.displayUnitPrice, font, latinFont),
                    _thermalCell(line.displayQuantityValue, font, latinFont),
                    _thermalCell(
                      line.resolvedDisplayUnit.isEmpty
                          ? '-'
                          : line.resolvedDisplayUnit,
                      font,
                      latinFont,
                    ),
                    _thermalCell(line.displayName, font, latinFont),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: .55, color: PdfColors.grey700),
            ),
            child: pw.Column(
              children: [
                if (invoice.discountAmount > 0)
                  _thermalTotal(
                    'الإجمالي العام',
                    invoice.subtotal,
                    invoice.currency,
                    latinFont,
                  ),
                if (invoice.discountAmount > 0)
                  _thermalTotal(
                    'الخصم',
                    invoice.discountAmount,
                    invoice.currency,
                    latinFont,
                  ),
                _thermalTotal(
                  'إجمالي المبلغ',
                  invoice.total,
                  invoice.currency,
                  latinFont,
                  bold: true,
                ),
                _thermalTotal(
                  'المدفوع',
                  invoice.paidAmount,
                  invoice.currency,
                  latinFont,
                ),
                _thermalTotal(
                  'الرصيد المتبقي',
                  invoice.dueAmount,
                  invoice.currency,
                  latinFont,
                  bold: invoice.dueAmount > 0,
                ),
                if (invoice.returnAmount > 0)
                  _thermalTotal(
                    'المرتجع',
                    invoice.returnAmount,
                    invoice.currency,
                    latinFont,
                    bold: true,
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: .4, color: PdfColors.grey600),
            ),
            child: pw.Row(
              children: [
                if (invoice.employeeName.isNotEmpty)
                  pw.Expanded(
                    child: pw.Text(
                      'المستخدم: ${invoice.employeeName}',
                      style: const pw.TextStyle(fontSize: 6.5),
                    ),
                  ),
                pw.Text(
                  'الرصيد الحالي: ${invoice.dueAmount.toStringAsFixed(2)} ${invoice.currency}',
                  textDirection: pw.TextDirection.rtl,
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
              ],
            ),
          ),
          if (invoice.paymentChannel.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                'نوع الدفع: ${invoice.paymentChannel == 'bank' ? 'تحويل' : 'نقدًا'}',
                textDirection: pw.TextDirection.rtl,
                style: const pw.TextStyle(fontSize: 7),
              ),
            ),
          if (invoice.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'ملاحظات: ${invoice.notes}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Divider(thickness: .5),
          pw.Text(
            profile.footer.isEmpty ? 'شكرًا لتعاملكم معنا' : profile.footer,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
    ),
  );
  return document.save();
}

String _receiptDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${_date(value)}  $hour:$minute';
}

pw.Widget _thermalPair(
  String label,
  String value,
  pw.Font arabicFont,
  pw.Font latinFont,
) => pw.Row(
  children: [
    pw.Text('$label: ', style: const pw.TextStyle(fontSize: 7)),
    pw.Expanded(
      child: _mixedPdfText(
        value,
        arabicFont,
        latinFont,
        fontSize: 7,
        textAlign: pw.TextAlign.left,
      ),
    ),
  ],
);

pw.Widget _thermalCell(
  String value,
  pw.Font font,
  pw.Font latinFont, {
  bool header = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
  child: _mixedPdfText(
    value,
    font,
    latinFont,
    fontSize: header ? 6.5 : 6,
    bold: header,
    textAlign: pw.TextAlign.center,
  ),
);

pw.Widget _invoiceSummaryAmount(
  String label,
  double value,
  String currency,
  pw.Font latinFont,
) => pw.Directionality(
  textDirection: pw.TextDirection.rtl,
  child: pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text('$label:', style: const pw.TextStyle(fontSize: 6.5)),
      pw.SizedBox(width: 3),
      pw.Text(
        _money(value, currency),
        textDirection: pw.TextDirection.ltr,
        style: pw.TextStyle(font: latinFont, fontSize: 6.5),
      ),
    ],
  ),
);

pw.Widget _thermalTotal(
  String label,
  double value,
  String currency,
  pw.Font latinFont, {
  bool bold = false,
}) => pw.Row(
  children: [
    pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
    pw.Spacer(),
    pw.Text(
      _money(value, currency),
      textDirection: pw.TextDirection.ltr,
      style: pw.TextStyle(
        font: latinFont,
        fontSize: 8,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  ],
);

pw.Widget _contactLine(
  String label,
  String value,
  PdfColor brand,
  pw.Font arabicFont,
  pw.Font latinFont,
) => pw.Directionality(
  textDirection: pw.TextDirection.ltr,
  child: pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      children: [
        pw.Container(
          width: 12,
          height: 12,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: brand,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.SvgImage(svg: _contactIconSvg(label), width: 8, height: 8),
        ),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Text(
            value,
            textDirection: _usesLatinTypography(value)
                ? pw.TextDirection.ltr
                : pw.TextDirection.rtl,
            textAlign: pw.TextAlign.left,
            maxLines: 1,
            style: pw.TextStyle(
              font: _usesLatinTypography(value) ? latinFont : arabicFont,
              fontSize: 7,
              color: const PdfColor.fromInt(0xFF252B35),
            ),
          ),
        ),
      ],
    ),
  ),
);

const _documentIconSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 2h8l4 4v16H6z M14 2v5h5 M9 12h6 M9 16h6"
        fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

String _contactIconSvg(String label) {
  if (label == 'هاتف') {
    return '''<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M7 3l3 5-2 2c2 4 4 6 8 8l2-2 4 3c-1 3-3 4-5 3C10 20 4 14 2 7 2 5 4 3 7 3z" fill="none" stroke="#ffffff" stroke-width="2" stroke-linejoin="round"/></svg>''';
  }
  if (label == 'بريد') {
    return '''<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="5" width="20" height="14" rx="2" fill="none" stroke="#ffffff" stroke-width="2"/><path d="M3 7l9 7 9-7" fill="none" stroke="#ffffff" stroke-width="2"/></svg>''';
  }
  return '''<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 22s7-6 7-13a7 7 0 10-14 0c0 7 7 13 7 13z" fill="none" stroke="#ffffff" stroke-width="2"/><circle cx="12" cy="9" r="2.5" fill="#ffffff"/></svg>''';
}

pw.Widget _meta(
  String label,
  String value,
  pw.Font arabicFont,
  pw.Font latinFont,
) => pw.Column(
  mainAxisAlignment: pw.MainAxisAlignment.center,
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    pw.Text(
      label,
      style: const pw.TextStyle(fontSize: 5.8, color: PdfColors.grey700),
    ),
    pw.SizedBox(height: 1),
    _mixedPdfText(
      value.isEmpty ? '-' : value,
      arabicFont,
      latinFont,
      fontSize: 7,
      color: const PdfColor.fromInt(0xFF252B35),
      bold: true,
      textAlign: pw.TextAlign.center,
      maxLines: 1,
    ),
  ],
);

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(double value, String currency) =>
    '${value.toStringAsFixed(2)} $currency';

bool _usesLatinTypography(String value) =>
    value.isNotEmpty && !RegExp(r'[\u0600-\u06FF]').hasMatch(value);

pw.Widget _mixedPdfText(
  String value,
  pw.Font arabicFont,
  pw.Font latinFont, {
  required double fontSize,
  PdfColor? color,
  bool bold = false,
  pw.TextAlign textAlign = pw.TextAlign.right,
  int maxLines = 1,
}) {
  final parts = value.split(
    RegExp(
      r'(?<=[A-Za-z0-9@._+:/-])(?=[^A-Za-z0-9@._+:/-])|(?<=[^A-Za-z0-9@._+:/-])(?=[A-Za-z0-9@._+:/-])',
    ),
  );
  return pw.Directionality(
    textDirection: _usesLatinTypography(value)
        ? pw.TextDirection.ltr
        : pw.TextDirection.rtl,
    child: pw.RichText(
      maxLines: maxLines,
      textAlign: textAlign,
      text: pw.TextSpan(
        children: [
          for (final part in parts)
            pw.TextSpan(
              text: part,
              style: pw.TextStyle(
                font: RegExp(r'[A-Za-z0-9]').hasMatch(part)
                    ? latinFont
                    : arabicFont,
                fontSize: fontSize,
                color: color,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
        ],
      ),
    ),
  );
}

pw.Widget _invoiceTableCell(
  String value,
  pw.Font arabicFont,
  pw.Font latinFont, {
  bool isHeader = false,
  bool compact = false,
}) {
  return pw.Container(
    padding: pw.EdgeInsets.symmetric(
      horizontal: 5,
      vertical: compact ? 0 : 2.7,
    ),
    alignment: pw.Alignment.center,
    child: _mixedPdfText(
      value,
      arabicFont,
      latinFont,
      fontSize: compact ? (isHeader ? 6.2 : 4.4) : 7.2,
      color: isHeader ? PdfColors.white : const PdfColor.fromInt(0xFF252B35),
      bold: isHeader,
      textAlign: pw.TextAlign.center,
      maxLines: 1,
    ),
  );
}
