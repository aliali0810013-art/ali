import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/accounting/chart_accounts_api.dart';
import 'package:nizami/src/features/accounting/chart_accounts_view_model.dart';

ChartAccount account({
  required String id,
  required String code,
  required String type,
  required int balance,
  String? parentId,
}) => ChartAccount(
  id: id,
  code: code,
  nameAr: id,
  type: type,
  normalBalance: type == 'asset' ? 'debit' : 'credit',
  balanceMinor: balance,
  parentId: parentId,
);

void main() {
  test('chart totals do not count descendant balances twice', () {
    final accounts = [
      account(id: 'assets', code: '1', type: 'asset', balance: 15000),
      account(
        id: 'cash',
        code: '11',
        type: 'asset',
        balance: 9000,
        parentId: 'assets',
      ),
      account(
        id: 'bank',
        code: '12',
        type: 'asset',
        balance: 6000,
        parentId: 'assets',
      ),
      account(id: 'liabilities', code: '2', type: 'liability', balance: 4000),
      account(
        id: 'payables',
        code: '21',
        type: 'liability',
        balance: 4000,
        parentId: 'liabilities',
      ),
    ];

    expect(chartRootTotals(accounts), {'asset': 15000, 'liability': 4000});
  });

  test(
    'collapsed tree hides children and search reveals matching ancestry',
    () {
      final accounts = [
        account(id: 'assets', code: '1', type: 'asset', balance: 15000),
        account(
          id: 'cash',
          code: '11',
          type: 'asset',
          balance: 9000,
          parentId: 'assets',
        ),
      ];

      expect(
        visibleChartAccounts(
          accounts: accounts,
          expandedIds: const {},
        ).map((e) => e.id),
        ['assets'],
      );
      expect(
        visibleChartAccounts(
          accounts: accounts,
          expandedIds: const {},
          query: 'cash',
        ).map((e) => e.id),
        ['assets', 'cash'],
      );
    },
  );
}
