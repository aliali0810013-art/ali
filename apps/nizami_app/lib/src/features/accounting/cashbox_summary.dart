enum CashboxPeriod { all, today, thisMonth }

class CashboxReloadRequest {
  const CashboxReloadRequest({required this.silent});

  final bool silent;
}

/// Serializes cashbox reloads without losing a branch change or realtime event.
///
/// A non-silent (user/branch initiated) request takes precedence when several
/// requests arrive while the current network request is still running.
class CashboxReloadQueue {
  bool _active = false;
  bool _queued = false;
  bool _queuedSilent = true;

  bool get isActive => _active;

  bool start({required bool silent}) {
    if (_active) {
      _queued = true;
      _queuedSilent = _queuedSilent && silent;
      return false;
    }
    _active = true;
    return true;
  }

  CashboxReloadRequest? complete() {
    _active = false;
    if (!_queued) {
      _queuedSilent = true;
      return null;
    }
    final request = CashboxReloadRequest(silent: _queuedSilent);
    _queued = false;
    _queuedSilent = true;
    return request;
  }
}

List<String> prioritizeCashboxBranch(
  List<String> branchIds,
  String? selectedBranchId,
) {
  final selected = selectedBranchId?.trim() ?? '';
  if (selected.isEmpty || !branchIds.contains(selected)) {
    return List<String>.unmodifiable(branchIds);
  }
  return List<String>.unmodifiable([
    selected,
    ...branchIds.where((branchId) => branchId != selected),
  ]);
}

class CashboxMovement {
  const CashboxMovement({
    required this.entryId,
    required this.description,
    required this.referenceType,
    required this.postedAt,
    required this.debitMinor,
    required this.creditMinor,
    required this.balanceMinor,
  });

  final String entryId;
  final String description;
  final String referenceType;
  final DateTime? postedAt;
  final int debitMinor;
  final int creditMinor;
  final int balanceMinor;

  int get netMinor => debitMinor - creditMinor;
}

class CashboxSummary {
  const CashboxSummary({
    required this.currentBalanceMinor,
    required this.openingBalanceMinor,
    required this.inflowMinor,
    required this.outflowMinor,
    required this.movements,
  });

  final int currentBalanceMinor;
  final int openingBalanceMinor;
  final int inflowMinor;
  final int outflowMinor;
  final List<CashboxMovement> movements;

  int get periodNetMinor => inflowMinor - outflowMinor;
  int get closingBalanceMinor => openingBalanceMinor + periodNetMinor;
}

CashboxSummary summarizeCashbox(
  List<Map<String, dynamic>> journals, {
  CashboxPeriod period = CashboxPeriod.all,
  DateTime? now,
  String accountCode = '1100-CASH',
}) {
  final localNow = now?.toLocal() ?? DateTime.now();
  final start = switch (period) {
    CashboxPeriod.all => null,
    CashboxPeriod.today => DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    ),
    CashboxPeriod.thisMonth => DateTime(localNow.year, localNow.month),
  };
  final end = switch (period) {
    CashboxPeriod.all => null,
    CashboxPeriod.today => DateTime(
      localNow.year,
      localNow.month,
      localNow.day + 1,
    ),
    CashboxPeriod.thisMonth => DateTime(localNow.year, localNow.month + 1),
  };

  final seenEntries = <String>{};
  final raw = <_RawCashboxMovement>[];
  for (var index = 0; index < journals.length; index++) {
    final journal = journals[index];
    final entryId = journal['id']?.toString().trim();
    final stableId = entryId == null || entryId.isEmpty
        ? 'row:$index'
        : entryId;
    if (!seenEntries.add(stableId)) continue;

    var debitMinor = 0;
    var creditMinor = 0;
    final lines = journal['lines'];
    if (lines is List) {
      for (final value in lines.whereType<Map>()) {
        final line = Map<String, dynamic>.from(value);
        if (line['account_code']?.toString() != accountCode) continue;
        debitMinor += _minor(line['debit_minor']);
        creditMinor += _minor(line['credit_minor']);
      }
    }
    if (debitMinor == 0 && creditMinor == 0) continue;
    raw.add(
      _RawCashboxMovement(
        entryId: stableId,
        description:
            journal['description']?.toString().trim().isNotEmpty == true
            ? journal['description'].toString().trim()
            : 'حركة صندوق',
        referenceType: journal['reference_type']?.toString() ?? '',
        postedAt: parseCashboxPostedAt(journal['posted_at']),
        debitMinor: debitMinor,
        creditMinor: creditMinor,
      ),
    );
  }

  raw.sort((left, right) {
    final leftDate = left.postedAt;
    final rightDate = right.postedAt;
    if (leftDate == null && rightDate == null) {
      return left.entryId.compareTo(right.entryId);
    }
    if (leftDate == null) return -1;
    if (rightDate == null) return 1;
    final byDate = leftDate.compareTo(rightDate);
    return byDate != 0 ? byDate : left.entryId.compareTo(right.entryId);
  });

  var running = 0;
  var opening = 0;
  var inflow = 0;
  var outflow = 0;
  final selected = <CashboxMovement>[];
  for (final item in raw) {
    final beforeStart =
        start != null &&
        (item.postedAt == null || item.postedAt!.isBefore(start));
    final inWindow =
        start == null ||
        (item.postedAt != null &&
            !item.postedAt!.isBefore(start) &&
            item.postedAt!.isBefore(end!));
    running += item.debitMinor - item.creditMinor;
    if (beforeStart) opening += item.debitMinor - item.creditMinor;
    if (!inWindow) continue;
    inflow += item.debitMinor;
    outflow += item.creditMinor;
    selected.add(
      CashboxMovement(
        entryId: item.entryId,
        description: item.description,
        referenceType: item.referenceType,
        postedAt: item.postedAt,
        debitMinor: item.debitMinor,
        creditMinor: item.creditMinor,
        balanceMinor: running,
      ),
    );
  }

  return CashboxSummary(
    currentBalanceMinor: running,
    openingBalanceMinor: start == null ? 0 : opening,
    inflowMinor: inflow,
    outflowMinor: outflow,
    movements: selected.reversed.toList(growable: false),
  );
}

int _minor(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

DateTime? parseCashboxPostedAt(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (parsed.isUtc) return parsed.toLocal();

  // Laravel may return a database timestamp without an offset. The API stores
  // posted_at in UTC, so interpreting such a value as device-local time shifts
  // movements across the local midnight boundary.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).toLocal();
}

class _RawCashboxMovement {
  const _RawCashboxMovement({
    required this.entryId,
    required this.description,
    required this.referenceType,
    required this.postedAt,
    required this.debitMinor,
    required this.creditMinor,
  });

  final String entryId;
  final String description;
  final String referenceType;
  final DateTime? postedAt;
  final int debitMinor;
  final int creditMinor;
}
