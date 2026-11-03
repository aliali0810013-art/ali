import 'money.dart';

enum EntrySide { debit, credit }

class JournalLine {
  const JournalLine({
    required this.accountCode,
    required this.side,
    required this.amount,
  });
  final String accountCode;
  final EntrySide side;
  final Money amount;
}

class JournalEntry {
  JournalEntry({
    required this.id,
    required this.referenceId,
    required List<JournalLine> lines,
  }) : lines = List.unmodifiable(lines) {
    if (lines.length < 2) {
      throw ArgumentError('A journal entry requires at least two lines');
    }
    if (lines.any((line) => line.amount.minorUnits <= 0)) {
      throw ArgumentError('Journal amounts must be positive');
    }
    if (!isBalanced) {
      throw StateError('Unbalanced journal entry');
    }
  }

  final String id;
  final String referenceId;
  final List<JournalLine> lines;

  bool get isBalanced {
    final debit = lines
        .where((l) => l.side == EntrySide.debit)
        .fold<int>(0, (v, l) => v + l.amount.minorUnits);
    final credit = lines
        .where((l) => l.side == EntrySide.credit)
        .fold<int>(0, (v, l) => v + l.amount.minorUnits);
    return debit == credit;
  }
}
