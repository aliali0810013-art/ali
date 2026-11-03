class SalesInvoiceLineViewModel {
  const SalesInvoiceLineViewModel({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.productId,
    required this.saleOptionId,
    required this.optionUnitCode,
    required this.optionQuantity,
    required this.optionMassG,
    required this.displayUnit,
    required this.exactQuantityMilli,
    required this.priceNumeratorMinor,
    required this.priceDenominator,
    required this.priceOverridden,
    required this.lineDiscountMinor,
    required this.weightGramsMilli,
    required this.pendingCatalogSync,
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
  final int lineDiscountMinor;
  final int? weightGramsMilli;
  final bool pendingCatalogSync;
}

class SalesInvoiceViewModel {
  const SalesInvoiceViewModel({
    required this.number,
    required this.customerName,
    required this.customerPhone,
    required this.customerId,
    required this.lines,
    required this.currency,
    required this.employeeName,
    required this.branchLabel,
    required this.createdAt,
    required this.paymentMode,
    required this.paidAmount,
    required this.discountAmount,
    required this.amountTendered,
    required this.paymentChannel,
    required this.paymentAccountCode,
    required this.notes,
    required this.localOperationId,
    required this.serverInvoiceId,
    required this.serverNumber,
    required this.replacementInvoiceId,
    required this.restoreGenerationAtCreation,
    required this.serverTotalMinor,
    required this.currentPaidMinor,
    required this.currentDueMinor,
    required this.returnedMinor,
    required this.isDraft,
    required this.quarantineReason,
  });

  final String number;
  final String customerName;
  final String customerPhone;
  final String customerId;
  final List<SalesInvoiceLineViewModel> lines;
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
  final int restoreGenerationAtCreation;
  final int? serverTotalMinor;
  final int? currentPaidMinor;
  final int? currentDueMinor;
  final int returnedMinor;
  final bool isDraft;
  final String quarantineReason;

  double get subtotal =>
      lines.fold<double>(0, (sum, line) {
        final quantityMilli =
            line.exactQuantityMilli ?? (line.quantity * 1000).round();
        final numerator = line.priceNumeratorMinor;
        final denominator = line.priceDenominator;
        if (numerator != null && denominator != null && denominator != 0) {
          final grossMinor =
              ((quantityMilli * numerator) / (1000 * denominator)).round();
          return sum + (grossMinor - line.lineDiscountMinor) / 100;
        }
        return sum +
            (line.quantity * line.unitPrice) -
            (line.lineDiscountMinor / 100);
      });

  double get total => serverTotalMinor == null
      ? (subtotal - discountAmount).clamp(0, double.infinity).toDouble()
      : serverTotalMinor! / 100;

  double get dueAmount =>
      (total - paidAmount).clamp(0, double.infinity).toDouble();

  double get returnAmount =>
      (amountTendered - total).clamp(0, double.infinity).toDouble();
}
