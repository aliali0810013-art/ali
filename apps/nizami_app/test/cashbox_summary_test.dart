import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/cashbox_summary.dart';

void main() {
  Map<String, dynamic> journal({
    required String id,
    required DateTime postedAt,
    required int debit,
    required int credit,
    String account = '1100-CASH',
  }) => {
    'id': id,
    'description': 'حركة $id',
    'reference_type': 'manual_journal',
    'posted_at': postedAt.toUtc().toIso8601String(),
    'lines': [
      {'account_code': account, 'debit_minor': debit, 'credit_minor': credit},
    ],
  };

  test(
    'cashbox totals only the cash posting account and deduplicates entries',
    () {
      final cashIn = journal(
        id: 'one',
        postedAt: DateTime.utc(2026, 10, 1),
        debit: 15000,
        credit: 0,
      );
      final summary = summarizeCashbox([
        cashIn,
        cashIn,
        journal(
          id: 'two',
          postedAt: DateTime.utc(2026, 10, 2),
          debit: 0,
          credit: 4000,
        ),
        journal(
          id: 'inventory',
          postedAt: DateTime.utc(2026, 10, 2),
          debit: 900000,
          credit: 0,
          account: '1300-INVENTORY',
        ),
      ]);

      expect(summary.inflowMinor, 15000);
      expect(summary.outflowMinor, 4000);
      expect(summary.currentBalanceMinor, 11000);
      expect(summary.movements, hasLength(2));
      expect(summary.movements.first.entryId, 'two');
      expect(summary.movements.first.balanceMinor, 11000);
    },
  );

  test('period summary preserves opening and current balances', () {
    final summary = summarizeCashbox(
      [
        journal(
          id: 'old',
          postedAt: DateTime(2026, 9, 30, 12),
          debit: 10000,
          credit: 0,
        ),
        journal(
          id: 'month-in',
          postedAt: DateTime(2026, 10, 2, 10),
          debit: 5000,
          credit: 0,
        ),
        journal(
          id: 'month-out',
          postedAt: DateTime(2026, 10, 3, 10),
          debit: 0,
          credit: 3000,
        ),
        journal(
          id: 'future',
          postedAt: DateTime(2026, 11, 1, 10),
          debit: 2000,
          credit: 0,
        ),
      ],
      period: CashboxPeriod.thisMonth,
      now: DateTime(2026, 10, 20),
    );

    expect(summary.openingBalanceMinor, 10000);
    expect(summary.inflowMinor, 5000);
    expect(summary.outflowMinor, 3000);
    expect(summary.closingBalanceMinor, 12000);
    expect(summary.currentBalanceMinor, 14000);
    expect(summary.movements.map((item) => item.entryId), [
      'month-out',
      'month-in',
    ]);
  });

  test('reversal journal naturally restores the cash balance', () {
    final summary = summarizeCashbox([
      journal(
        id: 'sale',
        postedAt: DateTime.utc(2026, 10, 1),
        debit: 2500,
        credit: 0,
      ),
      journal(
        id: 'sale-void',
        postedAt: DateTime.utc(2026, 10, 2),
        debit: 0,
        credit: 2500,
      ),
    ]);

    expect(summary.currentBalanceMinor, 0);
    expect(summary.periodNetMinor, 0);
  });

  test('cashbox can summarize an actual bank or wallet account', () {
    final journals = [
      journal(
        id: 'cash',
        postedAt: DateTime.utc(2026, 10, 1),
        debit: 10000,
        credit: 0,
      ),
      journal(
        id: 'bank',
        postedAt: DateTime.utc(2026, 10, 2),
        debit: 7000,
        credit: 0,
        account: '1110-BANK',
      ),
    ];

    expect(summarizeCashbox(journals).currentBalanceMinor, 10000);
    expect(
      summarizeCashbox(journals, accountCode: '1110-BANK').currentBalanceMinor,
      7000,
    );
  });

  test('timezone-less posted_at is interpreted as UTC at local midnight', () {
    final utcInstant = DateTime.utc(2026, 10, 29, 23, 30);
    final localInstant = utcInstant.toLocal();
    final parsed = parseCashboxPostedAt('2026-10-29T23:30:00');

    expect(parsed, localInstant);

    final summary = summarizeCashbox(
      [
        {
          'id': 'midnight-boundary',
          'description': 'boundary',
          'reference_type': 'receipt',
          'posted_at': '2026-10-29T23:30:00',
          'lines': [
            {
              'account_code': '1100-CASH',
              'debit_minor': 100,
              'credit_minor': 0,
            },
          ],
        },
      ],
      period: CashboxPeriod.today,
      now: localInstant,
    );

    expect(summary.movements.single.entryId, 'midnight-boundary');
  });

  test('reload queue preserves realtime and branch-change requests', () {
    final queue = CashboxReloadQueue();

    expect(queue.start(silent: true), isTrue);
    expect(queue.start(silent: true), isFalse);
    expect(queue.start(silent: false), isFalse);

    final queued = queue.complete();
    expect(queued, isNotNull);
    expect(queued!.silent, isFalse);
    expect(queue.isActive, isFalse);

    expect(queue.start(silent: queued.silent), isTrue);
    expect(queue.complete(), isNull);
  });

  test('selected branch is prioritized when opening cash documents', () {
    expect(prioritizeCashboxBranch(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
    expect(prioritizeCashboxBranch(['a', 'b'], 'missing'), ['a', 'b']);
  });
}
