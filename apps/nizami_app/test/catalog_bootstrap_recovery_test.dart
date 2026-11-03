import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/sync/realtime_sync_coordinator.dart';

void main() {
  test('empty local catalogue repairs a stale completed bootstrap marker', () {
    expect(
      catalogSnapshotNeedsRefresh(
        force: false,
        markedComplete: true,
        localCacheEmpty: true,
      ),
      isTrue,
    );
  });

  test('healthy completed catalogue avoids an unnecessary full reload', () {
    expect(
      catalogSnapshotNeedsRefresh(
        force: false,
        markedComplete: true,
        localCacheEmpty: false,
      ),
      isFalse,
    );
  });

  test('forced and first-time bootstraps always fetch a snapshot', () {
    expect(
      catalogSnapshotNeedsRefresh(
        force: true,
        markedComplete: true,
        localCacheEmpty: false,
      ),
      isTrue,
    );
    expect(
      catalogSnapshotNeedsRefresh(
        force: false,
        markedComplete: false,
        localCacheEmpty: false,
      ),
      isTrue,
    );
  });
}
