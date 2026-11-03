import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_api.dart';
import '../../auth/json_transport.dart';
import '../customers/customer_store.dart';
import '../accounting/accounting_api.dart';
import 'catalog_outbox.dart';
import 'invoice_delta_router.dart';
import 'sync_page_cursor.dart';
import 'pending_invoice_sync.dart';
import 'purchase_outbox.dart';
import 'product_unit_profile_outbox.dart';
import 'sales_invoice_outbox.dart';
import 'stock_operation_outbox.dart';
import '../inventory/stock_operations_api.dart';
import 'quarantined_operation_store.dart';
import 'restore_snapshot_store.dart';
import '../modules/catalog_sync_api.dart';
import '../products/product_catalog_store.dart';
import '../products/product_sale_option_store.dart';
import '../payroll/payroll_api.dart';
import '../payroll/payroll_cache.dart';
import 'payroll_outbox.dart';

bool catalogSnapshotNeedsRefresh({
  required bool force,
  required bool markedComplete,
  required bool localCacheEmpty,
}) => force || !markedComplete || localCacheEmpty;

bool canFlushProductUnitProfiles({
  required String roleCode,
  required Iterable<String> permissions,
}) => roleCode == 'owner' || permissions.contains('catalog.write');

bool canFlushSalesInvoiceOutbox({
  required String roleCode,
  required Iterable<String> permissions,
}) =>
    roleCode == 'owner' ||
    permissions.contains('invoices.create') ||
    permissions.contains('invoices.update');

bool canSendSalesInvoiceEntry({
  required SalesInvoiceOutboxEntry entry,
  required String roleCode,
  required Iterable<String> permissions,
}) {
  if (roleCode == 'owner') return true;
  final replacement = entry.request['replacement_invoice_id']?.toString() ?? '';
  return replacement.isEmpty
      ? permissions.contains('invoices.create')
      : permissions.contains('invoices.update');
}

bool unitProfileResponseIsCurrent({
  required int capturedCoordinatorGeneration,
  required int currentCoordinatorGeneration,
  required int capturedRestoreGeneration,
  required int currentRestoreGeneration,
  required bool sameSession,
}) =>
    sameSession &&
    capturedCoordinatorGeneration == currentCoordinatorGeneration &&
    capturedRestoreGeneration == currentRestoreGeneration;

Future<String> applyPayrollChange({
  required PayrollApi api,
  required String tenantId,
  required Iterable<String> allowedBranchIds,
  required String aggregateType,
  required String aggregateId,
  required String eventBranchId,
  required Map<String, dynamic> payload,
  required bool Function() isResponseValid,
}) async {
  if (!const {
    'employee',
    'employee_advance',
    'payroll_run',
    'payroll_payment',
  }.contains(aggregateType)) {
    throw FormatException('Unsupported payroll change: $aggregateType');
  }
  if (aggregateId.isEmpty ||
      eventBranchId.isEmpty ||
      !allowedBranchIds.contains(eventBranchId)) {
    throw const FormatException('Payroll change scope mismatch');
  }
  final detailPath = payload['detail_path']?.toString() ?? '';
  if (detailPath.isEmpty) {
    throw const FormatException('Payroll change has no detail_path');
  }
  final detail = await api.fetchDetailPath(detailPath);
  if (!isResponseValid()) {
    throw StateError('Payroll sync response belongs to a stale session');
  }
  await PayrollCache(tenantId, eventBranchId).mergeRemoteDetail(
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    detail: detail,
    isValid: isResponseValid,
  );
  return aggregateType;
}

Future<bool> refreshProductSaleOptionCache({
  required CatalogSyncApi api,
  required ProductSaleOptionStore store,
  required String branchId,
}) async {
  try {
    final snapshot = await api.productSaleOptionSnapshot(branchId: branchId);
    await store.replaceSnapshot(snapshot);
    return true;
  } catch (_) {
    // A failed opportunistic refresh must never erase usable offline options.
    return false;
  }
}

bool _canReadPayrollSnapshot(AuthSession session) =>
    session.roleCode == 'owner' || session.permissions.contains('payroll.read');

class PayrollBootstrapResult {
  const PayrollBootstrapResult({
    required this.cursor,
    required this.restoreGeneration,
    required this.restoreEpoch,
  });

  final int cursor;
  final int restoreGeneration;
  final DateTime? restoreEpoch;
}

Future<PayrollBootstrapResult> bootstrapPayrollSnapshot({
  required JsonTransport transport,
  required Uri baseUri,
  required SharedPreferences prefs,
  required AuthSession session,
  required String scope,
  required int restoreGeneration,
  required int currentCursor,
  DateTime? currentRestoreEpoch,
  required bool Function() isResponseValid,
}) async {
  PayrollBootstrapResult unchanged() => PayrollBootstrapResult(
    cursor: currentCursor,
    restoreGeneration: restoreGeneration,
    restoreEpoch: currentRestoreEpoch,
  );
  if (!_canReadPayrollSnapshot(session)) return unchanged();
  final marker = '$scope.payroll_bootstrap';
  if (prefs.getBool(marker) == true) return unchanged();
  final boundaryResponse = await transport.request(
    baseUri.resolve('sync/changes?after=$currentCursor&limit=1'),
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.token}',
    },
  );
  if (!isResponseValid()) {
    throw StateError('Payroll bootstrap boundary belongs to a stale session');
  }
  if (boundaryResponse.statusCode != 200) {
    throw StateError(
      'Payroll bootstrap boundary status ${boundaryResponse.statusCode}',
    );
  }
  final boundaryDecoded = jsonDecode(boundaryResponse.body);
  if (boundaryDecoded is! Map ||
      boundaryDecoded['restore_generation'] is! int) {
    throw const FormatException('Invalid payroll bootstrap boundary');
  }
  final serverRestoreGeneration = boundaryDecoded['restore_generation'] as int;
  if (serverRestoreGeneration < restoreGeneration) {
    throw const FormatException('Payroll restore generation moved backwards');
  }
  final serverRestoreEpoch = DateTime.tryParse(
    boundaryDecoded['restore_epoch']?.toString() ?? '',
  )?.toUtc();
  if (serverRestoreGeneration > restoreGeneration &&
      serverRestoreEpoch == null) {
    throw const FormatException('Missing payroll restore epoch');
  }
  final response = await transport.request(
    baseUri.resolve(
      'sync/snapshot?restore_generation=$serverRestoreGeneration',
    ),
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.token}',
    },
  );
  if (!isResponseValid()) {
    throw StateError('Payroll bootstrap response belongs to a stale session');
  }
  if (response.statusCode != 200) {
    throw StateError('Payroll bootstrap status ${response.statusCode}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    throw const FormatException('Invalid payroll bootstrap snapshot');
  }
  final snapshot = Map<String, dynamic>.from(decoded);
  if (snapshot['restore_generation'] != serverRestoreGeneration) {
    throw const FormatException('Payroll bootstrap generation changed');
  }
  final snapshotBranches = (snapshot['branch_ids'] as List? ?? const [])
      .map((value) => value.toString())
      .toSet();
  if (snapshotBranches.length != session.branchIds.toSet().length ||
      !snapshotBranches.containsAll(session.branchIds)) {
    throw const FormatException('Payroll bootstrap branch scope mismatch');
  }
  final store = RestoreSnapshotStore.forSession(
    session,
    restoreGeneration: serverRestoreGeneration,
  );
  await store.stage(snapshot);
  final applied = await store.resume();
  if (!isResponseValid() || applied == null) {
    throw StateError('Payroll bootstrap was invalidated before cursor commit');
  }
  final cursor = applied['snapshot_cursor'];
  if (cursor is! int || cursor < currentCursor) {
    throw const FormatException('Invalid payroll bootstrap cursor');
  }
  if (!await prefs.setInt('$scope.cursor', cursor)) {
    throw StateError('Unable to persist payroll bootstrap cursor');
  }
  if (!await prefs.setInt(
    '$scope.restore_generation',
    serverRestoreGeneration,
  )) {
    throw StateError('Unable to persist payroll restore generation');
  }
  final effectiveEpoch = serverRestoreEpoch ?? currentRestoreEpoch;
  if (effectiveEpoch != null &&
      !await prefs.setString(
        '$scope.restore_epoch',
        effectiveEpoch.toIso8601String(),
      )) {
    throw StateError('Unable to persist payroll restore epoch');
  }
  if (!await prefs.setBool(marker, true)) {
    throw StateError('Unable to mark payroll bootstrap complete');
  }
  return PayrollBootstrapResult(
    cursor: cursor,
    restoreGeneration: serverRestoreGeneration,
    restoreEpoch: effectiveEpoch,
  );
}

Future<int> commitSyncPageAfterDurableChanges({
  required int previousCursor,
  required Object? serverNext,
  required bool hasMore,
  required Future<int> Function() applyChanges,
  required Future<bool> Function(int cursor) persistCursor,
}) async {
  final lastApplied = await applyChanges();
  final consumed = SyncPageCursor.next(
    previous: previousCursor,
    lastApplied: lastApplied,
    serverNext: serverNext,
    hasMore: hasMore,
  );
  if (consumed > previousCursor && !await persistCursor(consumed)) {
    throw StateError('Unable to persist sync cursor');
  }
  return consumed;
}

/// One sync loop per signed-in application, shared by web/Windows/Android.
/// Polling is deliberately bounded: no infrastructure changes to the Laravel
/// server are required. The feed is a hint + cache reconciliation, NEVER a
/// second accounting posting system.
class RealtimeSyncCoordinator {
  RealtimeSyncCoordinator._({
    JsonTransport? transport,
    Uri? baseUri,
    Duration? idlePollInterval,
    Duration? retryBaseDelay,
  }) : _transport = transport ?? createJsonTransport(),
       _baseUri = baseUri ?? _defaultBaseUri,
       _idlePollInterval =
           idlePollInterval ?? const Duration(milliseconds: 800),
       _retryBaseDelay = retryBaseDelay ?? const Duration(seconds: 2);
  static final RealtimeSyncCoordinator instance = RealtimeSyncCoordinator._();

  factory RealtimeSyncCoordinator.forTesting({
    required JsonTransport transport,
    required Uri baseUri,
    Duration idlePollInterval = const Duration(milliseconds: 800),
    Duration retryBaseDelay = const Duration(milliseconds: 1),
  }) => RealtimeSyncCoordinator._(
    transport: transport,
    baseUri: baseUri,
    idlePollInterval: idlePollInterval,
    retryBaseDelay: retryBaseDelay,
  );

  final StreamController<Set<String>> _events =
      StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get changes => _events.stream;
  int get restoreGeneration => _restoreGeneration;
  DateTime? get restoreEpoch => _restoreEpoch;

  /// Connection health of the last server poll, NOT a guarantee that every
  /// local queue is drained. Purchase pending counts are shown separately.
  String get connectionHealthMessage {
    if (_session == null) return 'لا توجد جلسة مزامنة نشطة.';
    if (_failureCount > 0) {
      return 'تعذر الوصول إلى الخادم. يعيد النظام المحاولة تلقائيًا، والعمليات المحلية المعلقة محفوظة.';
    }
    if (_lastSuccessfulPoll == null) return 'جار التحقق من اتصال الخادم.';
    return 'اتصال الخادم نشط؛ آخر تحقق ${_lastSuccessfulPoll!.toLocal().hour.toString().padLeft(2, '0')}:${_lastSuccessfulPoll!.toLocal().minute.toString().padLeft(2, '0')}.';
  }

  final JsonTransport _transport;
  static final Uri _defaultBaseUri = Uri.parse(
    "${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/",
  );
  final Uri _baseUri;

  AuthSession? _session;
  Timer? _timer;
  bool _busy = false;
  bool _refreshRequested = false;
  bool _foreground = true;
  int _generation = 0;
  int _cursor = 0;
  int _failureCount = 0;
  DateTime? _lastSuccessfulPoll;
  String _scope = '';
  DateTime? _restoreEpoch;
  int _restoreGeneration = 0;
  final Duration _idlePollInterval;
  final Duration _retryBaseDelay;
  bool _bootstrapPending = false;

  String _key(AuthSession session) {
    final branches = [...session.branchIds]..sort();
    final permissions = [...session.permissions]..sort();
    // ACL changes must not reuse a cursor from a less privileged session.
    return 'ninesoft.sync.v1.${session.tenantId}.${session.userId}.'
        '${session.roleCode}.${branches.join('_')}.${permissions.join('_')}';
  }

  Future<void> start(AuthSession session) async {
    stop();
    if (session.mustChangePassword || session.isExpired) return;
    final generation = _generation;
    _session = session;
    _scope = _key(session);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation) return;
      _cursor = prefs.getInt('$_scope.cursor') ?? 0;
      _restoreEpoch = DateTime.tryParse(
        prefs.getString('$_scope.restore_epoch') ?? '',
      );
      _restoreGeneration = prefs.getInt('$_scope.restore_generation') ?? 0;
      final resumed = await RestoreSnapshotStore.forSession(
        session,
        restoreGeneration: _restoreGeneration,
      ).resume();
      if (generation != _generation) return;
      if (resumed != null) {
        _cursor = (resumed['snapshot_cursor'] as num?)?.toInt() ?? _cursor;
        _restoreGeneration =
            (resumed['restore_generation'] as num?)?.toInt() ??
            _restoreGeneration;
        _restoreEpoch = DateTime.tryParse(
          resumed['restore_epoch']?.toString() ?? '',
        );
        await prefs.setInt('$_scope.cursor', _cursor);
        await prefs.setInt('$_scope.restore_generation', _restoreGeneration);
        if (_restoreEpoch != null) {
          await prefs.setString(
            '$_scope.restore_epoch',
            _restoreEpoch!.toUtc().toIso8601String(),
          );
        }
        await _invalidateProductSaleOptionBootstrap(prefs, session);
        if (resumed.containsKey('employees') &&
            _canReadPayrollSnapshot(session)) {
          await prefs.setBool('$_scope.payroll_bootstrap', true);
        }
      }
      // First-time snapshots cover rows created before change_log events existed.
      _bootstrapPending = true;
      await _bootstrap(generation, prefs, session);
      _bootstrapPending = false;
      if (generation != _generation) return;
      _schedule(Duration.zero, generation);
    } catch (_) {
      if (generation != _generation) return;
      _bootstrapPending = true;
      _recordFailure(generation);
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value && _session != null && !_busy) {
      _schedule(Duration.zero, _generation);
    } else if (!value) {
      _timer?.cancel();
    }
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _session = null;
    _cursor = 0;
    _failureCount = 0;
    _lastSuccessfulPoll = null;
    _refreshRequested = false;
    _scope = '';
    _restoreEpoch = null;
    _restoreGeneration = 0;
    _bootstrapPending = false;
  }

  void _notify(Set<String> types) {
    if (types.isNotEmpty) _events.add(Set<String>.unmodifiable(types));
  }

  /// Requests an immediate differential refresh, without creating a backup.
  Future<bool> synchronizeNow() async {
    if (_session == null || !_foreground) return false;
    if (_busy) {
      _refreshRequested = true;
      return false;
    }
    _timer?.cancel();
    await _poll(_generation);
    return _failureCount == 0;
  }

  Future<void> _bootstrap(
    int generation,
    SharedPreferences prefs,
    AuthSession session, {
    bool force = false,
  }) async {
    final api = CatalogSyncApi(token: session.token);
    final owner = session.roleCode == 'owner';
    final productStore = ProductCatalogStore(session.tenantId);
    final customerStore = CustomerStore(session.tenantId);
    final productsEmpty = (await productStore.read()).isEmpty;
    final customersEmpty = (await customerStore.read()).isEmpty;
    if ((owner || session.permissions.contains('catalog.read')) &&
        catalogSnapshotNeedsRefresh(
          force: force,
          markedComplete: prefs.getBool('$_scope.catalog_bootstrap') == true,
          localCacheEmpty: productsEmpty,
        )) {
      try {
        final server = await api.list('products');
        if (generation != _generation) return;
        await productStore.replaceRemoteSnapshot(
          server.map(CatalogProduct.fromServer),
        );
        if (generation != _generation) return;
        await prefs.setBool('$_scope.catalog_bootstrap', true);
        _notify({'product'});
      } catch (_) {
        if (force) rethrow;
        // No reset: offline cache and pending posting data are preserved.
      }
    }
    if ((owner || session.permissions.contains('contacts.read')) &&
        catalogSnapshotNeedsRefresh(
          force: force,
          markedComplete: prefs.getBool('$_scope.contacts_bootstrap') == true,
          localCacheEmpty: customersEmpty,
        )) {
      try {
        final server = await api.list('customers');
        if (generation != _generation) return;
        await customerStore.replaceRemoteSnapshot(server);
        if (generation != _generation) return;
        await prefs.setBool('$_scope.contacts_bootstrap', true);
        _notify({'contact'});
      } catch (_) {
        if (force) rethrow;
        // Keep local data until a successful authenticated refresh.
      }
    }
    if (owner || session.permissions.contains('catalog.read')) {
      for (final branchId in session.branchIds) {
        if (generation != _generation) return;
        final store = ProductSaleOptionStore(session.tenantId, branchId);
        final marker = '$_scope.product_sale_options_bootstrap.$branchId';
        final localEmpty = await store.isEmpty;
        if (!catalogSnapshotNeedsRefresh(
          force: force,
          markedComplete: prefs.getBool(marker) == true,
          localCacheEmpty: localEmpty,
        )) {
          continue;
        }
        final refreshed = await refreshProductSaleOptionCache(
          api: api,
          store: store,
          branchId: branchId,
        );
        if (generation != _generation) return;
        if (refreshed) {
          if (!await prefs.setBool(marker, true)) {
            throw StateError('Unable to mark product sale option bootstrap');
          }
          _notify({'product_sale_option'});
        } else if (force) {
          // The caller requested a refresh, but the valid previous cache stays
          // available and the incomplete marker guarantees a later retry.
          await prefs.remove(marker);
        }
      }
    }
    final payrollMarker = '$_scope.payroll_bootstrap';
    final payrollWasPending =
        _canReadPayrollSnapshot(session) &&
        prefs.getBool(payrollMarker) != true;
    final payrollBootstrap = await bootstrapPayrollSnapshot(
      transport: _transport,
      baseUri: _baseUri,
      prefs: prefs,
      session: session,
      scope: _scope,
      restoreGeneration: _restoreGeneration,
      currentCursor: _cursor,
      currentRestoreEpoch: _restoreEpoch,
      isResponseValid: () =>
          generation == _generation && identical(_session, session),
    );
    _cursor = payrollBootstrap.cursor;
    _restoreGeneration = payrollBootstrap.restoreGeneration;
    _restoreEpoch = payrollBootstrap.restoreEpoch;
    if (payrollWasPending && prefs.getBool(payrollMarker) == true) {
      _notify({
        'employee',
        'employee_advance',
        'payroll_run',
        'payroll_payment',
      });
    }
  }

  Future<void> _invalidateProductSaleOptionBootstrap(
    SharedPreferences prefs,
    AuthSession session,
  ) async {
    for (final branchId in session.branchIds) {
      await prefs.remove('$_scope.product_sale_options_bootstrap.$branchId');
    }
  }

  void _schedule(Duration delay, int generation) {
    _timer?.cancel();
    if (generation != _generation || _session == null || !_foreground) return;
    _timer = Timer(delay, () => unawaited(_poll(generation)));
  }

  Future<void> _poll(int generation) async {
    if (_busy) {
      _schedule(const Duration(milliseconds: 500), generation);
      return;
    }
    if (!_foreground || _session == null || generation != _generation) {
      return;
    }
    _busy = true;
    try {
      final session = _session!;
      final prefs = await SharedPreferences.getInstance();
      if (_bootstrapPending) {
        await _bootstrap(generation, prefs, session);
        if (generation != _generation) return;
        _bootstrapPending = false;
      }
      var pages = 0;
      var hasMore = false;
      do {
        if (generation != _generation) return;
        final pageStart = _cursor;
        final uri = _baseUri.resolve('sync/changes?after=$_cursor&limit=200');
        final response = await _transport
            .request(
              uri,
              method: 'GET',
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer ${session.token}',
              },
            )
            .timeout(const Duration(seconds: 30));
        if (generation != _generation) return;
        if (response.statusCode != 200) {
          throw StateError('Sync feed status ${response.statusCode}');
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) throw const FormatException('Invalid sync page');
        final items = decoded['changes'];
        if (items is! List) throw const FormatException('Invalid sync events');
        final serverRestoreGeneration =
            (decoded['restore_generation'] as num?)?.toInt() ??
            _restoreGeneration;
        if (serverRestoreGeneration < _restoreGeneration) {
          throw const FormatException('Restore generation moved backwards');
        }
        if (serverRestoreGeneration > _restoreGeneration) {
          final epoch = DateTime.tryParse(
            decoded['restore_epoch']?.toString() ?? '',
          );
          if (epoch == null) {
            throw const FormatException('Missing restore epoch');
          }
          await _restoreSnapshot(
            generation,
            prefs,
            session,
            serverRestoreGeneration,
            epoch.toUtc(),
          );
          if (generation != _generation) return;
          _notify({
            'snapshot_restore',
            'invoice',
            'return_invoice',
            'business_document',
            'product',
            'contact',
            'journal_entry',
            'employee',
            'employee_advance',
            'payroll_run',
            'payroll_payment',
          });
          _failureCount = 0;
          _schedule(Duration.zero, generation);
          return;
        }
        final affected = <String>{};
        var next = _cursor;
        for (final raw in items) {
          if (generation != _generation) return;
          if (raw is! Map) throw const FormatException('Invalid sync event');
          final change = Map<String, dynamic>.from(raw);
          final cursor = (change['cursor'] as num?)?.toInt() ?? -1;
          if (cursor <= next) {
            throw const FormatException('Unordered sync events');
          }
          final type = change['aggregate_type']?.toString() ?? '';
          final id = change['aggregate_id']?.toString() ?? '';
          final op = change['operation']?.toString() ?? '';
          final payload = change['payload'] is Map
              ? Map<String, dynamic>.from(change['payload'] as Map)
              : <String, dynamic>{};
          if (type == 'snapshot_restore') {
            final epoch =
                DateTime.tryParse(
                  payload['epoch']?.toString() ?? '',
                )?.toUtc() ??
                DateTime.now().toUtc();
            await _restoreSnapshot(
              generation,
              prefs,
              session,
              serverRestoreGeneration,
              epoch,
            );
            _notify({
              'product',
              'contact',
              'invoice',
              'business_document',
              'journal_entry',
              'chart_account',
              'snapshot_restore',
              'employee',
              'employee_advance',
              'payroll_run',
              'payroll_payment',
            });
            _failureCount = 0;
            _schedule(const Duration(milliseconds: 100), generation);
            return;
          } else if (type == 'product' && id.isNotEmpty) {
            await ProductCatalogStore(
              session.tenantId,
            ).applyRemoteChange(id, op, payload);
          } else if (type == 'product_sale_option' && id.isNotEmpty) {
            await _applyProductSaleOptionChange(
              session,
              id,
              op,
              payload,
              change['branch_id']?.toString(),
            );
          } else if (type == 'contact' && id.isNotEmpty) {
            await CustomerStore(
              session.tenantId,
            ).applyRemoteChange(id, op, payload);
          } else if (type == 'invoice' && id.isNotEmpty) {
            if (op == 'delete') {
              affected.add(
                await InvoiceDeltaRouter.delete(
                  tenantId: session.tenantId,
                  invoiceId: id,
                  branchId:
                      change['branch_id']?.toString() ??
                      payload['branch_id']?.toString() ??
                      '',
                  invoiceType: payload['type']?.toString() ?? '',
                ),
              );
            } else {
              final value = await AccountingApi(
                token: session.token,
              ).invoice(id);
              affected.add(
                await InvoiceDeltaRouter.apply(
                  tenantId: session.tenantId,
                  invoiceId: id,
                  value: value,
                ),
              );
            }
          } else if (type == 'business_document' && id.isNotEmpty) {
            await _applyBusinessDocument(session.tenantId, id, op, payload);
          } else if (const {
                'employee',
                'employee_advance',
                'payroll_run',
                'payroll_payment',
              }.contains(type) &&
              id.isNotEmpty) {
            final payrollGeneration = _restoreGeneration;
            affected.add(
              await applyPayrollChange(
                api: PayrollApi(token: session.token),
                tenantId: session.tenantId,
                allowedBranchIds: session.branchIds,
                aggregateType: type,
                aggregateId: id,
                eventBranchId: change['branch_id']?.toString() ?? '',
                payload: payload,
                isResponseValid: () => unitProfileResponseIsCurrent(
                  capturedCoordinatorGeneration: generation,
                  currentCoordinatorGeneration: _generation,
                  capturedRestoreGeneration: payrollGeneration,
                  currentRestoreGeneration: _restoreGeneration,
                  sameSession: identical(_session, session),
                ),
              ),
            );
          }
          affected.add(type);
          next = cursor;
        }
        // The cursor is durable only AFTER all page changes are applied.
        // Retrying a page is safe because local data is upserted by server ID.
        if (generation != _generation) return;
        hasMore = decoded['has_more'] == true;
        final consumed = await commitSyncPageAfterDurableChanges(
          previousCursor: pageStart,
          serverNext: decoded['next_cursor'],
          hasMore: hasMore,
          applyChanges: () async {
            if (generation != _generation) {
              throw StateError('Sync session changed before cursor commit');
            }
            return next;
          },
          persistCursor: (cursor) {
            if (generation != _generation) return Future<bool>.value(false);
            return prefs.setInt('$_scope.cursor', cursor);
          },
        );
        if (consumed > _cursor) {
          if (generation != _generation) return;
          _cursor = consumed;
        }
        _notify(affected);
        pages++;
      } while (hasMore && pages < 10);
      // A connectivity recovery retries locally committed catalog operations.
      // The outbox is keyed by tenant and acknowledges only successful writes.
      if (generation == _generation &&
          (session.roleCode == 'owner' ||
              session.permissions.contains('catalog.write') ||
              session.permissions.contains('contacts.write'))) {
        await CatalogOutbox(session.tenantId).flush(
          CatalogSyncApi(token: session.token),
          createdAfter: _restoreEpoch,
          currentRestoreGeneration: _restoreGeneration,
        );
        if (canFlushProductUnitProfiles(
          roleCode: session.roleCode,
          permissions: session.permissions,
        )) {
          final profileRestoreGeneration = _restoreGeneration;
          for (final branchId in session.branchIds) {
            if (generation != _generation) return;
            final result =
                await ProductUnitProfileOutbox(
                  session.tenantId,
                  branchId,
                ).flush(
                  api: CatalogSyncApi(token: session.token),
                  currentRestoreGeneration: _restoreGeneration,
                  restoreEpoch: _restoreEpoch,
                  isResponseValid: () => unitProfileResponseIsCurrent(
                    capturedCoordinatorGeneration: generation,
                    currentCoordinatorGeneration: _generation,
                    capturedRestoreGeneration: profileRestoreGeneration,
                    currentRestoreGeneration: _restoreGeneration,
                    sameSession: identical(_session, session),
                  ),
                );
            if (result.sent > 0 && generation == _generation) {
              _notify({'product_sale_option', 'product'});
            }
            if (result.needsReview > 0 && generation == _generation) {
              _notify({'product_unit_profile_needs_review'});
            }
          }
        }
      }
      if (generation == _generation) {
        final hasPayrollMutationPermission =
            session.roleCode == 'owner' ||
            session.permissions.any(
              const {
                'payroll.manage',
                'payroll.advance',
                'payroll.approve',
                'payroll.pay',
              }.contains,
            );
        if (AccountingApi.enabled && hasPayrollMutationPermission) {
          final payrollGeneration = _restoreGeneration;
          for (final branch in session.branchIds) {
            if (generation != _generation) return;
            final payrollResult = await PayrollOutbox(session.tenantId, branch)
                .flush(
                  api: PayrollApi(token: session.token),
                  currentRestoreGeneration: _restoreGeneration,
                  restoreEpoch: _restoreEpoch,
                  isResponseValid: () => unitProfileResponseIsCurrent(
                    capturedCoordinatorGeneration: generation,
                    currentCoordinatorGeneration: _generation,
                    capturedRestoreGeneration: payrollGeneration,
                    currentRestoreGeneration: _restoreGeneration,
                    sameSession: identical(_session, session),
                  ),
                  canSend: (entry) => canSendPayrollOperation(
                    kind: entry.kind,
                    roleCode: session.roleCode,
                    permissions: session.permissions,
                  ),
                );
            if (generation != _generation) return;
            if (payrollResult.sentKinds.any(
              (kind) => kind.aggregateType == 'employee',
            )) {
              _notify({'employee'});
            }
            if (payrollResult.sentKinds.any(
              (kind) => kind.aggregateType == 'employee_advance',
            )) {
              _notify({'employee_advance'});
            }
            if (payrollResult.sentKinds.any(
              (kind) => kind.aggregateType == 'payroll_run',
            )) {
              _notify({'payroll_run'});
            }
            if (payrollResult.sentKinds.any(
              (kind) => kind.aggregateType == 'payroll_payment',
            )) {
              _notify({'payroll_payment'});
            }
            if (payrollResult.needsReview > 0) {
              _notify({'payroll_needs_review'});
            }
          }
        }
        if (generation != _generation) return;
        if (AccountingApi.enabled &&
            canFlushSalesInvoiceOutbox(
              roleCode: session.roleCode,
              permissions: session.permissions,
            )) {
          final salesRestoreGeneration = _restoreGeneration;
          for (final branch in session.branchIds) {
            if (generation != _generation) return;
            final salesResult =
                await SalesInvoiceOutbox(session.tenantId, branch).flush(
                  api: AccountingApi(token: session.token),
                  currentRestoreGeneration: _restoreGeneration,
                  restoreEpoch: _restoreEpoch,
                  isResponseValid: () => unitProfileResponseIsCurrent(
                    capturedCoordinatorGeneration: generation,
                    currentCoordinatorGeneration: _generation,
                    capturedRestoreGeneration: salesRestoreGeneration,
                    currentRestoreGeneration: _restoreGeneration,
                    sameSession: identical(_session, session),
                  ),
                  canSend: (entry) => canSendSalesInvoiceEntry(
                    entry: entry,
                    roleCode: session.roleCode,
                    permissions: session.permissions,
                  ),
                );
            if (salesResult.sent > 0 && generation == _generation) {
              _notify({'invoice'});
            }
            if (salesResult.needsReview > 0 && generation == _generation) {
              _notify({'sales_invoice_needs_review'});
            }
          }
        }
        if (generation != _generation) return;
        await _flushBusinessDocuments(session, prefs);
        final posted = await PendingInvoiceSync.flush(
          session,
          createdAfter: _restoreEpoch,
          restoreGeneration: _restoreGeneration,
        );
        if (posted && generation == _generation) _notify({'invoice'});
        // Purchases use their own durable, immutable FIFO outbox. Unlike the
        // legacy direct POST, this survives app restarts and lost HTTP ACKs.
        // Flush committed physical-count and interbranch transfer requests
        // with their original immutable operation identity. Reconnect and
        // restart do not create a new adjustment or transfer.
        if (generation == _generation &&
            (session.roleCode == 'owner' ||
                session.permissions.contains('catalog.write'))) {
          for (final branch in session.branchIds) {
            if (generation != _generation) return;
            final result = await StockOperationOutbox(session.tenantId, branch)
                .flush(
                  api: StockOperationsApi(token: session.token),
                  currentRestoreGeneration: _restoreGeneration,
                  restoreEpoch: _restoreEpoch,
                );
            if (result.sent > 0 && generation == _generation) {
              _notify({'inventory_balance', 'inventory_adjustment'});
            }
          }
        }
        if (AccountingApi.enabled &&
            (session.roleCode == 'owner' ||
                session.permissions.contains('invoices.create'))) {
          for (final branch in session.branchIds) {
            if (generation != _generation) return;
            final purchaseResult =
                await PurchaseOutbox(session.tenantId, branch).flush(
                  api: AccountingApi(token: session.token),
                  currentRestoreGeneration: _restoreGeneration,
                  restoreEpoch: _restoreEpoch,
                );
            if (purchaseResult.sent > 0 && generation == _generation) {
              _notify({'purchase_invoice'});
            }
          }
        }
      }
      final recovering = _failureCount > 0;
      _failureCount = 0;
      _lastSuccessfulPoll = DateTime.now();
      if (recovering) _notify({'sync_recovered'});
      // Drain backlog quickly, then keep foreground devices near real time.
      // This remains a differential cursor poll; it never reloads full lists.
      _schedule(
        hasMore ? const Duration(milliseconds: 200) : _idlePollInterval,
        generation,
      );
    } catch (_) {
      if (generation != _generation) return;
      _recordFailure(generation);
    } finally {
      _busy = false;
      if (_refreshRequested && _session != null) {
        _refreshRequested = false;
        _schedule(Duration.zero, _generation);
      }
    }
  }

  void _recordFailure(int generation) {
    _failureCount = (_failureCount + 1).clamp(1, 5).toInt();
    if (_failureCount == 1) _notify({'sync_failure'});
    _schedule(_retryBaseDelay * (1 << (_failureCount - 1)), generation);
  }

  Future<void> _restoreSnapshot(
    int generation,
    SharedPreferences prefs,
    AuthSession session,
    int restoreGeneration,
    DateTime restoreEpoch,
  ) async {
    final uri = _baseUri.resolve(
      'sync/snapshot?restore_generation=$restoreGeneration',
    );
    final response = await _transport.request(
      uri,
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${session.token}',
      },
    );
    if (response.statusCode != 200) {
      throw StateError('Restore snapshot status ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid restore snapshot');
    }
    final snapshot = Map<String, dynamic>.from(decoded)
      ..['restore_epoch'] = restoreEpoch.toUtc().toIso8601String();
    if ((snapshot['restore_generation'] as num?)?.toInt() !=
        restoreGeneration) {
      throw const FormatException('Restore snapshot generation changed');
    }
    final store = RestoreSnapshotStore.forSession(
      session,
      restoreGeneration: restoreGeneration,
    );
    await store.stage(snapshot);
    final applied = await store.resume();
    if (generation != _generation || applied == null) return;
    final cursor = (applied['snapshot_cursor'] as num?)?.toInt();
    if (cursor == null) throw const FormatException('Missing snapshot cursor');
    _restoreEpoch = restoreEpoch.toUtc();
    _restoreGeneration = restoreGeneration;
    _cursor = cursor;
    // Cursor and generation are durable only after every snapshot store was
    // successfully reconciled. A crash earlier leaves the journal to resume.
    await prefs.setString(
      '$_scope.restore_epoch',
      _restoreEpoch!.toIso8601String(),
    );
    await prefs.setInt('$_scope.restore_generation', _restoreGeneration);
    await prefs.setInt('$_scope.cursor', _cursor);
    if (_canReadPayrollSnapshot(session)) {
      await prefs.setBool('$_scope.payroll_bootstrap', true);
    }
    await _invalidateProductSaleOptionBootstrap(prefs, session);
    await _bootstrap(generation, prefs, session);
  }

  Future<void> _applyProductSaleOptionChange(
    AuthSession session,
    String id,
    String operation,
    Map<String, dynamic> payload,
    String? eventBranchId,
  ) async {
    final payloadBranch = payload['branch_id']?.toString() ?? '';
    final branchId = (eventBranchId ?? '').isNotEmpty
        ? eventBranchId!
        : payloadBranch;
    final targetBranches = branchId.isEmpty
        ? session.branchIds
        : session.branchIds.where((allowed) => allowed == branchId);
    for (final target in targetBranches) {
      await ProductSaleOptionStore(
        session.tenantId,
        target,
      ).applyRemoteChange(id, operation, payload);
    }
  }

  Future<void> _applyBusinessDocument(
    String tenantId,
    String id,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final module = payload['module_key']?.toString() ?? '';
    if (module.isEmpty) throw const FormatException('Missing document module');
    final prefs = await SharedPreferences.getInstance();
    final key = 'ninesoft.records.v1.$tenantId.$module';
    final raw = prefs.getString(key);
    final records = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
    records.removeWhere((item) => item['serverId']?.toString() == id);
    if (operation != 'delete') {
      Map<String, dynamic> details = const {};
      final encoded = payload['payload'];
      if (encoded is Map) {
        details = Map<String, dynamic>.from(encoded);
      } else if (encoded is String && encoded.isNotEmpty) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) details = Map<String, dynamic>.from(decoded);
      }
      records.insert(0, {
        'title': payload['title']?.toString() ?? '',
        'details': payload['details']?.toString() ?? '',
        'updatedAt': payload['occurred_at']?.toString(),
        'purchasePrice': (details['purchasePrice'] as num?)?.toDouble() ?? 0,
        'salePrice': (details['salePrice'] as num?)?.toDouble() ?? 0,
        'barcode': details['barcode']?.toString() ?? '',
        'amount': ((payload['amount_minor'] as num?)?.toDouble() ?? 0) / 100,
        'currency': details['currency']?.toString() ?? 'YER',
        'dueAt': payload['due_at']?.toString(),
        'settled': payload['settled'] == true,
        'serverId': id,
        'version': (payload['version'] as num?)?.toInt() ?? 1,
        'clientOperationId': payload['client_operation_id']?.toString() ?? id,
      });
    }
    if (!await prefs.setString(key, jsonEncode(records))) {
      throw StateError('Unable to persist document delta');
    }
  }

  Future<void> _flushBusinessDocuments(
    AuthSession session,
    SharedPreferences prefs,
  ) async {
    if (session.roleCode != 'owner' &&
        !session.permissions.contains('documents.create')) {
      return;
    }
    final prefix = 'ninesoft.records.v1.${session.tenantId}.';
    var sent = 0;
    for (final key in prefs.getKeys().where(
      (item) => item.startsWith(prefix),
    )) {
      if (sent >= 4) return;
      final module = key.substring(prefix.length);
      if (!const {
        'accounts.opening',
        'accounts.years',
        'debts.receipts',
        'debts.payments',
        'debts.exchange',
        'inventory.warehouses',
        'inventory.transfers',
        'inventory.counts',
        'purchases.orders',
        'purchases.receiving',
      }.contains(module)) {
        continue;
      }
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      final records = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      var changed = false;
      for (final record in records.where(
        (item) =>
            (item['serverId']?.toString() ?? '').isEmpty &&
            (item['clientOperationId']?.toString() ?? '').isNotEmpty,
      )) {
        if (sent >= 4) break;
        final operationId = record['clientOperationId'].toString();
        final quarantine = QuarantinedOperationStore(session.tenantId);
        if (await quarantine.isDiscarded(operationId, 'business_document')) {
          continue;
        }
        final operationGeneration =
            (record['restoreGenerationAtCreation'] as num?)?.toInt() ?? 0;
        final createdAt = DateTime.tryParse(
          record['updatedAt']?.toString() ?? '',
        );
        if (operationGeneration != _restoreGeneration ||
            (_restoreEpoch != null &&
                (createdAt == null || !createdAt.isAfter(_restoreEpoch!)))) {
          await quarantine.quarantine(
            operationId: operationId,
            kind: 'business_document',
            reason: operationGeneration != _restoreGeneration
                ? 'restore_generation_at_creation_mismatch'
                : 'created_before_restore',
            payload: record,
          );
          continue;
        }
        final branchId = session.branchIds.isEmpty
            ? ''
            : session.branchIds.first;
        if (branchId.isEmpty) continue;
        sent++;
        final response = await _transport.request(
          _baseUri.resolve('documents'),
          method: 'POST',
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.token}',
          },
          body: jsonEncode({
            'id': operationId,
            'client_operation_id': operationId,
            'restore_generation': operationGeneration,
            'branch_id': branchId,
            'module_key': module,
            'title': record['title']?.toString() ?? '',
            'details': record['details']?.toString() ?? '',
            'amount_minor':
                (((record['amount'] as num?)?.toDouble() ?? 0) * 100).round(),
            'due_at': record['dueAt'],
            'settled': record['settled'] == true,
            'occurred_at': record['updatedAt'],
            'payload': {
              'purchasePrice': record['purchasePrice'],
              'salePrice': record['salePrice'],
              'barcode': record['barcode'],
              'currency': record['currency'],
            },
          }),
        );
        if (response.statusCode == 409 &&
            response.body.contains('RESTORE_GENERATION_')) {
          await QuarantinedOperationStore(session.tenantId).quarantine(
            operationId: operationId,
            kind: 'business_document',
            reason: response.body,
            payload: record,
          );
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) return;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['id']?.toString().isEmpty != false) {
          return;
        }
        record['serverId'] = decoded['id'].toString();
        changed = true;
      }
      if (changed && !await prefs.setString(key, jsonEncode(records))) {
        throw StateError('Unable to acknowledge document outbox');
      }
    }
  }
}
