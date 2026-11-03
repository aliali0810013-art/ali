/// Server-ledger projections. An original document is not silently redated by a later return.
abstract final class FinancialProjection {
  static int invoiceAmount(Map<String, dynamic> invoice) {
    final face = (invoice['total_minor'] as num?)?.toInt() ?? 0;
    return const {'sale_return', 'purchase_return'}.contains(invoice['type']) ? -face : face;
  }
  static int cashMovement(Map<String, dynamic> entry) {
    final lines = entry['lines'];
    if (lines is! List) throw const FormatException('Missing journal lines');
    var value = 0;
    for (final line in lines.whereType<Map>()) {
      if (const {'1100-CASH','1110-BANK','1120-WALLET'}.contains(line['account_code'])) {
        value += ((line['debit_minor'] as num?)?.toInt() ?? 0) - ((line['credit_minor'] as num?)?.toInt() ?? 0);
      }
    }
    return value;
  }
}
