import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import '../purchases/purchase_invoice_store.dart';

/// Applies a server invoice delta to exactly one local domain cache.
///
/// Sales and purchases share the server aggregate type, but they must never
/// share a local cache. Keeping the dispatch here makes the invariant directly
/// testable for every Flutter target (web, Windows and Android).
class InvoiceDeltaRouter {
  const InvoiceDeltaRouter._();

  static Future<String> delete({
    required String tenantId,
    required String invoiceId,
    required String branchId,
    required String invoiceType,
  }) async {
    if (invoiceId.isEmpty || branchId.isEmpty) {
      throw const FormatException('Invoice delete delta has no scope');
    }
    if (invoiceType == 'sale') {
      await InvoiceHistoryStore().removeServerId(tenantId, branchId, invoiceId);
      return 'invoice';
    }
    if (invoiceType == 'purchase') {
      await PurchaseInvoiceStore().remove(tenantId, branchId, invoiceId);
      return 'purchase_invoice';
    }
    if (invoiceType == 'sale_return' || invoiceType == 'purchase_return') {
      return 'return_invoice';
    }
    throw FormatException('Unknown deleted invoice type: $invoiceType');
  }

  static Future<String> apply({
    required String tenantId,
    required String invoiceId,
    required Map<String, dynamic> value,
  }) async {
    final branchId = value['branch_id']?.toString() ?? '';
    if (branchId.isEmpty) {
      throw const FormatException('Invoice delta has no branch');
    }

    final invoiceType = value['type']?.toString() ?? '';
    final isVoided = value['status']?.toString() == 'voided';
    if (invoiceType == 'sale') {
      final history = InvoiceHistoryStore();
      if (isVoided) {
        await history.removeServerId(tenantId, branchId, invoiceId);
      } else {
        await history.save(
          tenantId,
          branchId,
          InvoiceDocument.fromServer(value),
        );
      }
      return 'invoice';
    }

    if (invoiceType == 'purchase') {
      final purchases = PurchaseInvoiceStore();
      if (isVoided) {
        await purchases.remove(tenantId, branchId, invoiceId);
      } else {
        await purchases.save(tenantId, branchId, value);
      }
      return 'purchase_invoice';
    }

    if (invoiceType == 'sale_return' || invoiceType == 'purchase_return') {
      // Dedicated return screens fetch immutable server returns; never put them in the sales cache.
      return 'return_invoice';
    }

    throw FormatException('Unknown invoice type: $invoiceType');
  }
}
