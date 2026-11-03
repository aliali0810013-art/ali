import '../invoice_pdf_service.dart';
import 'sales_invoice_view_model.dart';

class SalesInvoicePresentationAdapter {
  const SalesInvoicePresentationAdapter._();

  static SalesInvoiceLineViewModel fromDomainLine(InvoiceLine line) =>
      SalesInvoiceLineViewModel(
        name: line.name,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        productId: line.productId,
        saleOptionId: line.saleOptionId,
        optionUnitCode: line.optionUnitCode,
        optionQuantity: line.optionQuantity,
        optionMassG: line.optionMassG,
        displayUnit: line.displayUnit,
        exactQuantityMilli: line.exactQuantityMilli,
        priceNumeratorMinor: line.priceNumeratorMinorSnapshot,
        priceDenominator: line.priceDenominatorSnapshot,
        priceOverridden: line.priceOverridden,
        lineDiscountMinor: line.lineDiscountMinor,
        weightGramsMilli: line.weightGramsMilli,
        pendingCatalogSync: line.pendingCatalogSync,
      );

  static InvoiceLine toDomainLine(SalesInvoiceLineViewModel line) => InvoiceLine(
        name: line.name,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        productId: line.productId,
        saleOptionId: line.saleOptionId,
        optionUnitCode: line.optionUnitCode,
        optionQuantity: line.optionQuantity,
        optionMassG: line.optionMassG,
        displayUnit: line.displayUnit,
        exactQuantityMilli: line.exactQuantityMilli,
        priceNumeratorMinor: line.priceNumeratorMinor,
        priceDenominator: line.priceDenominator,
        priceOverridden: line.priceOverridden,
        lineDiscountMinor: line.lineDiscountMinor,
        weightGramsMilli: line.weightGramsMilli,
        pendingCatalogSync: line.pendingCatalogSync,
      );

  static SalesInvoiceViewModel fromDomain(InvoiceDocument document) =>
      SalesInvoiceViewModel(
        number: document.number,
        customerName: document.customerName,
        customerPhone: document.customerPhone,
        customerId: document.customerId,
        lines: document.lines
            .map(fromDomainLine)
            .toList(growable: false),
        currency: document.currency,
        employeeName: document.employeeName,
        branchLabel: document.branchLabel,
        createdAt: document.createdAt,
        paymentMode: document.paymentMode,
        paidAmount: document.paidAmount,
        discountAmount: document.discountAmount,
        amountTendered: document.amountTendered,
        paymentChannel: document.paymentChannel,
        paymentAccountCode: document.paymentAccountCode,
        notes: document.notes,
        localOperationId: document.localOperationId,
        serverInvoiceId: document.serverInvoiceId,
        serverNumber: document.serverNumber,
        replacementInvoiceId: document.replacementInvoiceId,
        restoreGenerationAtCreation: document.restoreGenerationAtCreation,
        serverTotalMinor: document.serverTotalMinor,
        currentPaidMinor: document.currentPaidMinor,
        currentDueMinor: document.currentDueMinor,
        returnedMinor: document.returnedMinor,
        isDraft: document.isDraft,
        quarantineReason: document.quarantineReason,
      );

  static InvoiceDocument toDomain(SalesInvoiceViewModel viewModel) =>
      InvoiceDocument(
        number: viewModel.number,
        customerName: viewModel.customerName,
        customerPhone: viewModel.customerPhone,
        customerId: viewModel.customerId,
        lines: viewModel.lines
            .map(toDomainLine)
            .toList(growable: false),
        currency: viewModel.currency,
        employeeName: viewModel.employeeName,
        branchLabel: viewModel.branchLabel,
        createdAt: viewModel.createdAt,
        paymentMode: viewModel.paymentMode,
        paidAmount: viewModel.paidAmount,
        discountAmount: viewModel.discountAmount,
        amountTendered: viewModel.amountTendered,
        paymentChannel: viewModel.paymentChannel,
        paymentAccountCode: viewModel.paymentAccountCode,
        notes: viewModel.notes,
        localOperationId: viewModel.localOperationId,
        serverInvoiceId: viewModel.serverInvoiceId,
        serverNumber: viewModel.serverNumber,
        replacementInvoiceId: viewModel.replacementInvoiceId,
        restoreGenerationAtCreation: viewModel.restoreGenerationAtCreation,
        serverTotalMinor: viewModel.serverTotalMinor,
        currentPaidMinor: viewModel.currentPaidMinor,
        currentDueMinor: viewModel.currentDueMinor,
        returnedMinor: viewModel.returnedMinor,
        isDraft: viewModel.isDraft,
        quarantineReason: viewModel.quarantineReason,
      );
}
