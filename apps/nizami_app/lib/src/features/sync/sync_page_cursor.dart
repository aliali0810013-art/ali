/// Cursor advancement is based on the consumed tenant stream, not just visible events.
/// Validation happens before writing the cursor and AFTER applying every visible change.
class SyncPageCursor {
  const SyncPageCursor._();

  static int next({
    required int previous,
    required int lastApplied,
    required Object? serverNext,
    required bool hasMore,
  }) {
    if (serverNext is! int || serverNext < previous || serverNext < lastApplied) {
      throw const FormatException('Invalid or regressing server sync cursor');
    }
    if (hasMore && serverNext <= previous) {
      throw const FormatException('Sync backlog did not advance');
    }
    return serverNext;
  }
}
