import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_api.dart';
import '../customers/customer_store.dart';
import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import '../products/product_catalog_store.dart';
import '../products/product_sale_option_store.dart';
import '../modules/catalog_sync_api.dart';
import '../purchases/purchase_invoice_store.dart';
import '../payroll/payroll_cache.dart';

class RestoreSnapshotScope {
  RestoreSnapshotScope({
    required this.tenantId,
    required this.userId,
    required this.roleCode,
    required this.restoreGeneration,
    required Iterable<String> branchIds,
    required Iterable<String> permissions,
  }) : branchIds = (branchIds.toSet().toList()..sort()),
       permissions = (permissions.toSet().toList()..sort());

  factory RestoreSnapshotScope.fromSession(
    AuthSession session, {
    required int restoreGeneration,
  }) => RestoreSnapshotScope(
    tenantId: session.tenantId,
    userId: session.userId,
    roleCode: session.roleCode,
    restoreGeneration: restoreGeneration,
    branchIds: session.branchIds,
    permissions: session.permissions,
  );

  final String tenantId;
  final String userId;
  final String roleCode;
  final int restoreGeneration;
  final List<String> branchIds;
  final List<String> permissions;

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'user_id': userId,
    'role_code': roleCode,
    'restore_generation': restoreGeneration,
    'branch_ids': branchIds,
    'permissions': permissions,
  };

  String get canonical => jsonEncode(toJson());

  String get keySuffix {
    var hash = 0x811c9dc5;
    for (final value in canonical.codeUnits) {
      hash = ((hash * 31) + value) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
}

/// Applies a complete server restore snapshot. The journal is written before
/// any visible store changes, so an app termination resumes the exact same
/// immutable snapshot. The caller may advance its change cursor only after
/// [resume] returns successfully.
class RestoreSnapshotStore {
  RestoreSnapshotStore(this.scope);

  factory RestoreSnapshotStore.forSession(
    AuthSession session, {
    required int restoreGeneration,
  }) => RestoreSnapshotStore(
    RestoreSnapshotScope.fromSession(
      session,
      restoreGeneration: restoreGeneration,
    ),
  );

  final RestoreSnapshotScope scope;
  String get tenantId => scope.tenantId;
  String get _journalKey =>
      'ninesoft.restore.snapshot.pending.v2.$tenantId.${scope.keySuffix}';

  Future<void> stage(Map<String, dynamic> snapshot) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _journalKey,
      jsonEncode({'scope': scope.toJson(), 'snapshot': snapshot}),
    );
    if (!saved) throw StateError('Unable to stage restore snapshot');
  }

  Future<Map<String, dynamic>?> pending() async {
    final raw = (await SharedPreferences.getInstance()).getString(_journalKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid restore journal');
    final envelope = Map<String, dynamic>.from(decoded);
    final storedScope = envelope['scope'];
    if (storedScope is! Map ||
        jsonEncode(Map<String, dynamic>.from(storedScope)) != scope.canonical) {
      throw StateError('Restore journal belongs to another sync scope');
    }
    final snapshot = envelope['snapshot'];
    if (snapshot is! Map) {
      throw const FormatException('Invalid restore snapshot payload');
    }
    final result = Map<String, dynamic>.from(snapshot);
    if ((result['restore_generation'] as num?)?.toInt() !=
        scope.restoreGeneration) {
      throw StateError('Restore journal generation no longer matches');
    }
    final snapshotBranches = (result['branch_ids'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (!scope.branchIds.toSet().containsAll(snapshotBranches)) {
      throw StateError('Restore snapshot contains an unauthorized branch');
    }
    for (final collection in const [
      'invoices',
      'purchase_invoices',
      'business_documents',
    ]) {
      for (final raw in result[collection] as List? ?? const []) {
        if (raw is! Map ||
            !snapshotBranches.contains(raw['branch_id']?.toString())) {
          throw StateError(
            'Restore snapshot row is outside its authorized branch set',
          );
        }
      }
    }
    for (final raw in result['product_sale_options'] as List? ?? const []) {
      if (raw is! Map) {
        throw StateError('Restore snapshot contains an invalid sale option');
      }
      final row = Map<String, dynamic>.from(raw);
      final tenant = row['tenant_id']?.toString() ?? '';
      final branch = row['branch_id']?.toString() ?? '';
      if (tenant != scope.tenantId ||
          (branch.isNotEmpty && !snapshotBranches.contains(branch))) {
        throw StateError(
          'Restore sale option is outside its authorized sync scope',
        );
      }
    }
    const payrollCollections = [
      'employees',
      'employee_advances',
      'payroll_runs',
      'payroll_run_items',
      'payroll_advance_allocations',
      'payroll_period_claims',
      'payroll_payments',
      'payroll_payment_items',
    ];
    final payrollCollectionCount = payrollCollections
        .where(result.containsKey)
        .length;
    if (payrollCollectionCount != 0 &&
        payrollCollectionCount != payrollCollections.length) {
      throw StateError('Restore snapshot has an incomplete payroll envelope');
    }
    for (final collection in payrollCollections.where(result.containsKey)) {
      final rows = result[collection];
      if (rows is! List) {
        throw StateError(
          'Restore snapshot is missing payroll collection $collection',
        );
      }
      for (final raw in rows) {
        if (raw is! Map ||
            raw['tenant_id']?.toString() != scope.tenantId ||
            !snapshotBranches.contains(raw['branch_id']?.toString())) {
          throw StateError(
            'Restore payroll row is outside its authorized sync scope',
          );
        }
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> resume() async {
    final snapshot = await pending();
    if (snapshot == null) return null;
    await _apply(snapshot);
    if (!await (await SharedPreferences.getInstance()).remove(_journalKey)) {
      throw StateError('Unable to complete restore journal');
    }
    return snapshot;
  }

  Future<void> _apply(Map<String, dynamic> snapshot) async {
    if (snapshot.containsKey('product_sale_options')) {
      final options = (snapshot['product_sale_options'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                ProductSaleOption.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false);
      final optionBranches = (snapshot['branch_ids'] as List? ?? const []).map(
        (value) => value.toString(),
      );
      for (final branch in optionBranches) {
        await ProductSaleOptionStore(tenantId, branch).replaceSnapshot(
          options.where(
            (option) => option.branchId == null || option.branchId == branch,
          ),
        );
      }
    }

    final products = (snapshot['products'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CatalogProduct.fromServer(Map<String, dynamic>.from(value)),
        );
    await ProductCatalogStore(tenantId).replaceRemoteSnapshot(products);

    final contacts = (snapshot['contacts'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value));
    await CustomerStore(tenantId).replaceRemoteSnapshot(contacts);

    final invoices = (snapshot['invoices'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final branches = (snapshot['branch_ids'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    for (final branch in branches) {
      final remote = invoices
          .where((value) => value['branch_id']?.toString() == branch)
          .map(InvoiceDocument.fromServer)
          .toList(growable: false);
      await InvoiceHistoryStore().replaceRemoteSnapshot(
        tenantId,
        branch,
        remote,
      );
      final purchases = (snapshot['purchase_invoices'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((value) => value['branch_id']?.toString() == branch);
      await PurchaseInvoiceStore().replaceRemoteSnapshot(
        tenantId,
        branch,
        purchases,
      );
      if (snapshot.containsKey('employees')) {
        await PayrollCache(tenantId, branch).replaceSnapshot(snapshot);
      }
    }

    await _replaceBusinessDocuments(
      (snapshot['business_documents'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false),
    );
  }

  Future<void> _replaceBusinessDocuments(
    List<Map<String, dynamic>> remote,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'ninesoft.records.v1.$tenantId.';
    final modules = <String>{
      for (final key in prefs.getKeys().where((key) => key.startsWith(prefix)))
        key.substring(prefix.length),
      for (final row in remote)
        if ((row['module_key']?.toString() ?? '').isNotEmpty)
          row['module_key'].toString(),
    };
    for (final module in modules) {
      final key = '$prefix$module';
      final raw = prefs.getString(key);
      final local = raw == null || raw.isEmpty
          ? <Map<String, dynamic>>[]
          : (jsonDecode(raw) as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
      final server = remote
          .where((row) => row['module_key']?.toString() == module)
          .map(_documentFromServer)
          .toList(growable: false);
      final serverOperations = server
          .map((row) => row['clientOperationId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final drafts = local.where(
        (row) =>
            (row['serverId']?.toString() ?? '').isEmpty &&
            !serverOperations.contains(row['clientOperationId']?.toString()),
      );
      final saved = await prefs.setString(
        key,
        jsonEncode([...drafts, ...server]),
      );
      if (!saved) throw StateError('Unable to replace document snapshot');
    }
  }

  static Map<String, dynamic> _documentFromServer(Map<String, dynamic> row) {
    Map<String, dynamic> payload = const {};
    final rawPayload = row['payload'];
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String && rawPayload.isNotEmpty) {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    }
    return {
      'title': row['title']?.toString() ?? '',
      'details': row['details']?.toString() ?? '',
      'updatedAt': row['occurred_at']?.toString(),
      'purchasePrice': (payload['purchasePrice'] as num?)?.toDouble() ?? 0,
      'salePrice': (payload['salePrice'] as num?)?.toDouble() ?? 0,
      'barcode': payload['barcode']?.toString() ?? '',
      'amount': ((row['amount_minor'] as num?)?.toDouble() ?? 0) / 100,
      'currency': payload['currency']?.toString() ?? 'YER',
      'dueAt': row['due_at']?.toString(),
      'settled': row['settled'] == true || row['settled'] == 1,
      'serverId': row['id']?.toString() ?? '',
      'version': (row['version'] as num?)?.toInt() ?? 1,
      'clientOperationId':
          row['client_operation_id']?.toString() ?? row['id']?.toString() ?? '',
      'restoreGenerationAtCreation':
          (row['restore_generation'] as num?)?.toInt() ?? 0,
    };
  }
}
