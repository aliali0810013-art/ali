import '../accounting/journal.dart';
import '../accounting/money.dart';

class SalesPostingService {
  const SalesPostingService();

  List<JournalEntry> post({
    required String invoiceId,
    required Money total,
    required Money paid,
    required Money costOfGoodsSold,
  }) {
    if (total.isNegative ||
        paid.isNegative ||
        costOfGoodsSold.isNegative ||
        paid.minorUnits > total.minorUnits) {
      throw ArgumentError('Invalid sales amounts');
    }
    final receivable = total - paid;
    final saleLines = <JournalLine>[
      if (paid.minorUnits > 0)
        JournalLine(
          accountCode: '1100-CASH',
          side: EntrySide.debit,
          amount: paid,
        ),
      if (receivable.minorUnits > 0)
        JournalLine(
          accountCode: '1200-AR',
          side: EntrySide.debit,
          amount: receivable,
        ),
      JournalLine(
        accountCode: '4100-SALES',
        side: EntrySide.credit,
        amount: total,
      ),
    ];
    final entries = <JournalEntry>[
      JournalEntry(
        id: '$invoiceId-SALE',
        referenceId: invoiceId,
        lines: saleLines,
      ),
    ];
    if (costOfGoodsSold.minorUnits > 0) {
      entries.add(
        JournalEntry(
          id: '$invoiceId-COGS',
          referenceId: invoiceId,
          lines: [
            JournalLine(
              accountCode: '5100-COGS',
              side: EntrySide.debit,
              amount: costOfGoodsSold,
            ),
            JournalLine(
              accountCode: '1300-INVENTORY',
              side: EntrySide.credit,
              amount: costOfGoodsSold,
            ),
          ],
        ),
      );
    }
    return entries;
  }
}
