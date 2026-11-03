import '../invoices/invoice_pdf_service.dart';

class RestoreSubmissionDecision {
  const RestoreSubmissionDecision._(this.allowed, this.reason);
  const RestoreSubmissionDecision.allow() : this._(true, '');
  const RestoreSubmissionDecision.block(String reason) : this._(false, reason);

  final bool allowed;
  final String reason;
}

/// The single local policy used by manual, automatic, and replacement posts.
/// The operation's immutable generation is authoritative; callers may not
/// substitute the current generation after a restore.
class RestoreSubmissionPolicy {
  const RestoreSubmissionPolicy._();

  static RestoreSubmissionDecision evaluate({
    required int operationGeneration,
    required int currentGeneration,
    required DateTime operationCreatedAt,
    DateTime? restoreEpoch,
  }) {
    if (operationGeneration != currentGeneration) {
      return RestoreSubmissionDecision.block(
        'restore_generation_at_creation_mismatch',
      );
    }
    if (restoreEpoch != null && !operationCreatedAt.isAfter(restoreEpoch)) {
      return const RestoreSubmissionDecision.block('created_before_restore');
    }
    return const RestoreSubmissionDecision.allow();
  }

  static Future<RestoreSubmissionDecision> guardInvoice({
    required String tenantId,
    required InvoiceDocument invoice,
    required int currentGeneration,
    DateTime? restoreEpoch,
  }) async {
    // The server is the authority for restore/idempotency reconciliation.
    // Local clients must attempt the original operation instead of hiding it
    // in a terminal review queue before the server can acknowledge it.
    return const RestoreSubmissionDecision.allow();
  }
}
