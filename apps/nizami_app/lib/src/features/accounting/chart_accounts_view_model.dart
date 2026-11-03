import 'chart_accounts_api.dart';

/// Totals only the highest account in each hierarchy branch. The API balance
/// of a parent already includes its descendants, so adding every row would
/// count the same journal movements more than once.
Map<String, int> chartRootTotals(Iterable<ChartAccount> accounts) {
  final totals = <String, int>{};
  for (final account in accounts.where((item) => item.parentId == null)) {
    totals[account.type] = (totals[account.type] ?? 0) + account.balanceMinor;
  }
  return totals;
}

List<ChartAccount> visibleChartAccounts({
  required List<ChartAccount> accounts,
  required Set<String> expandedIds,
  String query = '',
  String type = '',
}) {
  final byParent = <String?, List<ChartAccount>>{};
  final byId = {for (final account in accounts) account.id: account};
  for (final account in accounts) {
    (byParent[account.parentId] ??= []).add(account);
  }
  for (final children in byParent.values) {
    children.sort((a, b) {
      final sort = a.sortOrder.compareTo(b.sortOrder);
      return sort != 0 ? sort : a.code.compareTo(b.code);
    });
  }

  final normalized = query.trim().toLowerCase();
  final matchingIds = <String>{};
  if (normalized.isNotEmpty) {
    for (final account in accounts) {
      if (account.nameAr.toLowerCase().contains(normalized) ||
          account.nameEn.toLowerCase().contains(normalized) ||
          account.code.toLowerCase().contains(normalized)) {
        matchingIds.add(account.id);
        var parentId = account.parentId;
        while (parentId != null && matchingIds.add(parentId)) {
          parentId = byId[parentId]?.parentId;
        }
      }
    }
  }

  final result = <ChartAccount>[];
  void visit(ChartAccount account, bool parentVisible) {
    final matchesType = type.isEmpty || account.type == type;
    final matchesSearch =
        normalized.isEmpty || matchingIds.contains(account.id);
    final visible = parentVisible && matchesType && matchesSearch;
    if (visible) result.add(account);
    final searchExpanded =
        normalized.isNotEmpty && matchingIds.contains(account.id);
    if (visible && (searchExpanded || expandedIds.contains(account.id))) {
      for (final child in byParent[account.id] ?? const <ChartAccount>[]) {
        visit(child, true);
      }
    }
  }

  for (final root in byParent[null] ?? const <ChartAccount>[]) {
    visit(root, true);
  }
  return result;
}
