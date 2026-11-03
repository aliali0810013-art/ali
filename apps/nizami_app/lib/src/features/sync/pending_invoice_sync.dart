import '../../auth/auth_api.dart';
import '../accounting/accounting_api.dart';
import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import 'quarantined_operation_store.dart';
import 'restore_submission_policy.dart';
import 'sales_invoice_outbox.dart';

/// Retries only invoices already explicitly saved by the user. Posting is
/// server-idempotent on (tenant_id, device_id, local_operation_id).
class PendingInvoiceSync {
  PendingInvoiceSync._();
  static final Map<String, DateTime> _retryAfter = {};

  /// Only pre-outbox history rows may use the compatibility sender. A final
  /// operation owned by SalesInvoiceOutbox has exactly one delivery route.
  static Future<bool> isLegacyPending({
    required String tenantId,
    required String branchId,
    required InvoiceDocument invoice,
  }) async =>
      !invoice.postedToServer &&
      !invoice.isDraft &&
      invoice.lines.isNotEmpty &&
      invoice.localOperationId.isNotEmpty &&
      !await SalesInvoiceOutbox(
        tenantId,
        branchId,
      ).contains(invoice.localOperationId);

  static Future<bool> flush(
    AuthSession session, {
    int maxPerCycle = 4,
    DateTime? createdAfter,
    int restoreGeneration = 0,
  }) async {
    if (!AccountingApi.enabled ||
        (session.roleCode != 'owner' &&
            !session.permissions.contains('invoices.create'))) {
      return false;
    }

    final api = AccountingApi(token: session.token);
    final history = InvoiceHistoryStore();
    var processed = 0;
    var changed = false;
    for (final branch in session.branchIds) {
      for (final invoice in await history.read(session.tenantId, branch)) {
        if (processed >= maxPerCycle) return changed;
        if (!await isLegacyPending(
          tenantId: session.tenantId,
          branchId: branch,
          invoice: invoice,
        )) {
          continue;
        }
        final quarantine = QuarantinedOperationStore(session.tenantId);
        if (await quarantine.isDiscarded(invoice.localOperationId, 'invoice')) {
          continue;
        }
        final decision = await RestoreSubmissionPolicy.guardInvoice(
          tenantId: session.tenantId,
          invoice: invoice,
          currentGeneration: restoreGeneration,
          restoreEpoch: createdAfter,
        );
        if (!decision.allowed) {
          await history.markQuarantined(
            session.tenantId,
            branch,
            invoice.localOperationId,
            decision.reason,
            fallback: invoice,
          );
          changed = true;
          continue;
        }
        final key = '${session.tenantId}.$branch.${invoice.localOperationId}';
        if (_retryAfter[key]?.isAfter(DateTime.now()) == true) continue;
        processed++;
        try {
          final result = await api.postInvoice(
            branchId: branch,
            invoice: invoice,
            restoreGeneration: invoice.restoreGenerationAtCreation,
          );
          final posted = InvoiceDocument(
            number: invoice.number,
            customerName: invoice.customerName,
            customerPhone: invoice.customerPhone,
            customerId: invoice.customerId,
            lines: invoice.lines,
            currency: invoice.currency,
            employeeName: invoice.employeeName,
            branchLabel: invoice.branchLabel,
            createdAt: invoice.createdAt,
            paymentMode: invoice.paymentMode,
            paidAmount: invoice.paidAmount,
            discountAmount: invoice.discountAmount,
            amountTendered: invoice.amountTendered,
            paymentChannel: invoice.paymentChannel,
            notes: invoice.notes,
            localOperationId: invoice.localOperationId,
            serverInvoiceId: result['id']?.toString() ?? '',
            serverNumber: result['number']?.toString() ?? '',
            replacementInvoiceId: '',
            restoreGenerationAtCreation: invoice.restoreGenerationAtCreation,
            isDraft: false,
          );
          if (posted.serverInvoiceId.isEmpty) {
            throw StateError('Missing server invoice ID');
          }
          await history.save(session.tenantId, branch, posted);
          _retryAfter.remove(key);
          changed = true;
        } catch (error) {
          if (error is AccountingApiError && error.restoreBoundaryViolation) {
            final request = await api.prepareInvoiceRequest(
              branchId: branch,
              invoice: invoice,
              restoreGeneration: restoreGeneration,
            );
            final now = DateTime.now().toUtc();
            final minimum = createdAfter?.toUtc().add(
              const Duration(seconds: 1),
            );
            request['operation_created_at'] =
                (minimum != null && minimum.isAfter(now) ? minimum : now)
                    .toIso8601String();
            request['restore_generation'] = restoreGeneration;
            await SalesInvoiceOutbox(session.tenantId, branch).enqueue(request);
            await quarantine.remove(invoice.localOperationId);
            changed = true;
          }
          // Do not remove or re-key the invoice. Server uniqueness makes
          // retry after a lost response safe; avoid flooding on validation errors.
          _retryAfter[key] = DateTime.now().add(const Duration(seconds: 15));
        }
      }
    }
    return changed;
  }
}
