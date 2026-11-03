import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../products/product_catalog_store.dart';
import '../sync/realtime_sync_coordinator.dart';
import '../sync/catalog_outbox.dart';
import '../sync/purchase_outbox.dart';
import '../sync/quarantined_operation_store.dart';
import '../accounting/accounting_api.dart';
import '../accounting/account_statement_page.dart';
import '../accounting/chart_accounts_api.dart';
import '../accounting/simple_journal_page.dart';
import '../accounting/searchable_chart_account_field.dart';
import '../accounting/financial_projection.dart';
import '../accounting/settlement_idempotency_store.dart';
import '../customers/customer_store.dart';
import '../navigation/ninesoft_module_access_policy.dart';
import '../invoices/invoice_history_store.dart';
import '../invoices/invoice_pdf_service.dart';
import '../wasl/wasl_qr_scanner_page.dart';
import 'business_document_api.dart';
import 'catalog_sync_api.dart';
import '../../settings/business_identity_store.dart';
import '../../core/pdf/pdf_export_service.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';

@visibleForTesting
bool stableStockIncrease({
  required double current,
  required double requested,
}) => (requested * 1000).round() > (current * 1000).round();

class ModuleDefinition {
  const ModuleDefinition({
    required this.key,
    required this.title,
    required this.entityLabel,
    required this.actionLabel,
    required this.icon,
    required this.color,
  });

  final String key;
  final String title;
  final String entityLabel;
  final String actionLabel;
  final IconData icon;
  final Color color;
}

@visibleForTesting
bool isCurrentModuleLoad({
  required int requestSequence,
  required int activeSequence,
}) => requestSequence == activeSequence;

@visibleForTesting
class ContactStatementOpenGuard {
  final Set<String> _active = <String>{};

  bool tryAcquire(String key) => _active.add(key);
  void release(String key) => _active.remove(key);
  bool isActive(String key) => _active.contains(key);
}

@visibleForTesting
CatalogContact? selectCanonicalContact(
  Iterable<Map<String, dynamic>> rows, {
  required String name,
  required String phone,
}) {
  String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  final nameKey = normalize(name);
  final matches = rows
      .map(CatalogContact.fromJson)
      .where(
        (contact) =>
            contact.id.isNotEmpty && normalize(contact.name) == nameKey,
      )
      .toList(growable: false);
  if (matches.isEmpty) return null;
  final phoneKey = normalize(phone);
  if (phoneKey.isNotEmpty) {
    final phoneMatches = matches
        .where((contact) => normalize(contact.phone) == phoneKey)
        .toList(growable: false);
    if (phoneMatches.length == 1) return phoneMatches.single;
    throw StateError(
      'يوجد طرف بالاسم نفسه لكن رقم الهاتف لا يطابقه؛ راجع الرقم قبل فتح كشف الحساب.',
    );
  }
  if (matches.length == 1) return matches.single;
  throw StateError(
    'توجد عدة جهات بالاسم نفسه؛ حدّد رقم الهاتف الصحيح قبل فتح كشف الحساب.',
  );
}

@visibleForTesting
Map<String, Object?> projectSettlementRecord(
  Map<String, dynamic> json, {
  required bool isReceipt,
  DateTime? fallbackNow,
}) {
  final id = json['id']?.toString() ?? '';
  final number = json['number']?.toString().trim() ?? '';
  final invoiceNumber = json['invoice_number']?.toString().trim() ?? '';
  final partyName =
      json[isReceipt ? 'customer_name' : 'supplier_name']?.toString().trim() ??
      json['party_name']?.toString().trim() ??
      '';
  final channel = switch (json['channel']?.toString()) {
    'cash' => 'نقدًا',
    'bank' => 'تحويل بنكي',
    'wallet' => 'محفظة',
    final value when value != null && value.isNotEmpty => value,
    _ => '',
  };
  final reason = json['reason']?.toString().trim() ?? '';
  final detailParts = <String>[
    if (number.isNotEmpty) number,
    if (invoiceNumber.isNotEmpty) invoiceNumber,
    if (channel.isNotEmpty) channel,
    if (reason.isNotEmpty) reason,
  ];
  final occurredAt =
      DateTime.tryParse(json['posted_at']?.toString() ?? '') ??
      DateTime.tryParse(json['created_at']?.toString() ?? '') ??
      DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
      fallbackNow ??
      DateTime.now();
  final status = json['status']?.toString() ?? 'posted';
  return <String, Object?>{
    'title': partyName.isNotEmpty
        ? partyName
        : (number.isNotEmpty ? number : (isReceipt ? 'سند قبض' : 'سند صرف')),
    'details': detailParts.join(' • '),
    'updatedAt': occurredAt,
    'amount': ((json['amount_minor'] as num?)?.toDouble() ?? 0) / 100,
    'currency': json['currency']?.toString() ?? 'YER',
    'settled': status == 'posted',
    'status': status,
    'serverId': id,
    'clientOperationId':
        json['idempotency_key']?.toString() ?? (id.isNotEmpty ? id : ''),
  };
}

class ModuleWorkspacePage extends StatefulWidget {
  const ModuleWorkspacePage({
    required this.module,
    required this.tenantName,
    this.tenantId,
    this.token,
    this.branchIds = const [],
    this.roleCode = '',
    this.permissions = const [],
    super.key,
  });

  final ModuleDefinition module;
  final String tenantName;
  final String? tenantId;
  final String? token;
  final List<String> branchIds;
  final String roleCode;
  final List<String> permissions;

  @override
  State<ModuleWorkspacePage> createState() => _ModuleWorkspacePageState();
}

class _ModuleWorkspacePageState extends State<ModuleWorkspacePage> {
  String get _tenantScope => widget.tenantId ?? widget.tenantName;
  final _searchController = TextEditingController();
  final List<_ModuleRecord> _records = [];
  String _query = '';
  String? _accountingWarning;
  String _categoryFilter = '';
  String _subcategoryFilter = '';
  String _statusFilter = 'all';
  DateTimeRange? _dateRange;
  bool _exporting = false;
  bool _recordsLoaded = false;
  int _loadSequence = 0;
  StreamSubscription<Set<String>>? _syncSubscription;
  final ContactStatementOpenGuard _contactStatementGuard =
      ContactStatementOpenGuard();

  bool get _isDebt => widget.module.key == 'debts.dues';
  bool get _isSettlementModule =>
      widget.module.key == 'debts.receipts' ||
      widget.module.key == 'debts.payments';
  bool get _isReport => widget.module.key.startsWith('reports.');
  bool get _isReadOnlyModule =>
      _isReport ||
      const {
        'debts.dues',
        'accounts.statements',
        'inventory.movements',
        'inventory.valuation',
      }.contains(widget.module.key);
  bool get _isDocument =>
      (widget.module.key.contains('.') &&
      !_isReport &&
      widget.module.key != 'debts.dues' &&
      !_isSettlementModule);
  bool _hasPermission(String permission) =>
      widget.roleCode == 'owner' || widget.permissions.contains(permission);
  bool get _canViewContactStatement =>
      _hasPermission('contacts.read') && _hasPermission('invoices.read');
  bool get _canAddRecord {
    if (_isReadOnlyModule) return false;
    return switch (widget.module.key) {
      'products' => _hasPermission('catalog.write'),
      'customers' || 'suppliers' => _hasPermission('contacts.write'),
      'debts.receipts' ||
      'debts.payments' => NineSoftModuleAccessPolicy.canCreateSettlement(
        moduleKey: widget.module.key,
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      ),
      _ when _isDocument => _hasPermission('documents.create'),
      _ => false,
    };
  }

  bool get _canEditRecord {
    if (_isReadOnlyModule ||
        widget.module.key == 'debts.receipts' ||
        widget.module.key == 'debts.payments') {
      return false;
    }
    return switch (widget.module.key) {
      'products' => _hasPermission('catalog.write'),
      'customers' || 'suppliers' => _hasPermission('contacts.write'),
      _ when _isDocument => _hasPermission('documents.update'),
      _ => false,
    };
  }

  bool get _canDeleteRecord {
    if (_isReadOnlyModule) return false;
    return switch (widget.module.key) {
      'products' => _hasPermission('catalog.write'),
      'customers' || 'suppliers' => _hasPermission('contacts.write'),
      'debts.receipts' => _hasPermission('receipts.void'),
      'debts.payments' => _hasPermission('payments.void'),
      _ when _isDocument => _hasPermission('documents.delete'),
      _ => false,
    };
  }

  BusinessDocumentApi? get _documentApi =>
      widget.token == null || widget.token!.isEmpty
      ? null
      : BusinessDocumentApi(token: widget.token!);
  CatalogSyncApi? get _catalogApi =>
      widget.token == null || widget.token!.isEmpty
      ? null
      : CatalogSyncApi(token: widget.token!);
  AccountingApi? get _accountingApi =>
      widget.token == null || widget.token!.isEmpty
      ? null
      : AccountingApi(token: widget.token!);
  String? get _branchId =>
      widget.branchIds.isEmpty ? null : widget.branchIds.first;
  BranchBusinessProfile get _profile =>
      BusinessIdentityStore.instance.profileFor(
        _branchId ?? 'MAIN',
        _tenantScope,
        displayName: widget.tenantName,
      );

  String get _storageKey =>
      'ninesoft.records.v1.$_tenantScope.${widget.module.key}';

  Future<List<_ModuleRecord>> _readModuleRecords(String moduleKey) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'ninesoft.records.v1.$_tenantScope.$moduleKey',
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (item) => _ModuleRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<_ModuleRecord>> _canonicalSettlementRecords(
    String moduleKey,
  ) async {
    final api = _accountingApi;
    final branchId = _branchId;
    if (api == null || branchId == null) return const [];
    final rows = moduleKey == 'debts.receipts'
        ? await api.listReceipts(branchId: branchId)
        : await api.listSupplierPayments(branchId: branchId);
    final isReceipt = moduleKey == 'debts.receipts';
    return rows
        .map((row) => _ModuleRecord.fromSettlementJson(row, isReceipt))
        .where((record) => record.serverId.isNotEmpty)
        .toList(growable: false);
  }

  // Canonical reports must be cached by tenant AND branch, separately from
  // legacy generic business documents. Never present unposted notes as ledgers.
  String get _verifiedReportKey =>
      'ninesoft.verified.report.v1.$_tenantScope.${_branchId ?? 'none'}.${widget.module.key}';

  Future<List<_ModuleRecord>> _readVerifiedReportCache() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _verifiedReportKey,
    );
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (entry) => _ModuleRecord.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();
    } catch (_) {
      return const []; // Corrupt cache is not a source of accounting truth.
    }
  }

  Future<void> _saveVerifiedReportCache(List<_ModuleRecord> records) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _verifiedReportKey,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
    if (!saved) throw StateError('تعذر تخزين التقرير المحاسبي المعتمد محليًا.');
  }

  // Retained for the verified-report path that is enabled by staged modules.
  // ignore: unused_element
  Future<List<_ModuleRecord>> _reportSourceRecords(
    Map<String, String> sources, {
    int? requestSequence,
  }) async {
    final result = <_ModuleRecord>[];
    for (final source in sources.entries) {
      var sourceRecords = await _readModuleRecords(source.key);
      if ((source.key == 'debts.receipts' || source.key == 'debts.payments') &&
          _accountingApi != null &&
          _branchId != null) {
        try {
          sourceRecords = await _canonicalSettlementRecords(source.key);
          if (requestSequence != null && !_isCurrentLoad(requestSequence)) {
            return result;
          }
          await (await SharedPreferences.getInstance()).setString(
            'ninesoft.records.v1.$_tenantScope.${source.key}',
            jsonEncode(sourceRecords.map((record) => record.toJson()).toList()),
          );
        } catch (_) {
          // Reports remain available from the last canonical local copy.
        }
      } else if (_documentApi != null && _branchId != null) {
        try {
          sourceRecords = (await _documentApi!.list(
            _branchId!,
            source.key,
          )).map(_ModuleRecord.fromServerJson).toList();
          if (requestSequence != null && !_isCurrentLoad(requestSequence)) {
            return result;
          }
          await (await SharedPreferences.getInstance()).setString(
            'ninesoft.records.v1.$_tenantScope.${source.key}',
            jsonEncode(sourceRecords.map((record) => record.toJson()).toList()),
          );
        } catch (_) {
          // Reports remain available from the last synchronized local copy.
        }
      }
      for (final record in sourceRecords) {
        result.add(
          _ModuleRecord(
            title: record.title,
            details: '${source.value} • ${record.details}',
            updatedAt: record.updatedAt,
            purchasePrice: record.purchasePrice,
            salePrice: record.salePrice,
            barcode: record.barcode,
            amount: source.key == 'debts.payments'
                ? -record.amount.abs()
                : record.amount,
            currency: record.currency,
            dueAt: record.dueAt,
            settled: record.settled,
            serverId:
                'report:${source.key}:${record.serverId}:${record.updatedAt.microsecondsSinceEpoch}',
          ),
        );
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _syncSubscription = RealtimeSyncCoordinator.instance.changes.listen((
      types,
    ) {
      final key = widget.module.key;
      final shouldReload =
          (key == 'products' && types.contains('product')) ||
          (key == 'customers' &&
              (types.contains('contact') || types.contains('invoice'))) ||
          (key == 'suppliers' &&
              (types.contains('contact') || types.contains('invoice'))) ||
          ((key.startsWith('accounts.') || key.startsWith('inventory.')) &&
              types.intersection({
                'invoice',
                'journal_entry',
                'return_invoice',
              }).isNotEmpty) ||
          (key.startsWith('reports.') &&
              types.intersection({
                'invoice',
                'journal_entry',
                'business_document',
                'chart_account',
                'receipt',
                'supplier_payment',
              }).isNotEmpty) ||
          (key.startsWith('debts.') &&
              types.intersection({
                'invoice',
                'journal_entry',
                'receipt',
                'supplier_payment',
              }).isNotEmpty) ||
          (types.contains('business_document') && key.contains('.'));
      if (mounted && (shouldReload || types.contains('snapshot_restore'))) {
        unawaited(
          _loadRecords(
            remoteRefresh:
                types.contains('snapshot_restore') || _isSettlementModule,
          ),
        );
      }
    });
    _loadRecords();
  }

  Future<void> _loadRecords({bool remoteRefresh = true}) async {
    final requestSequence = ++_loadSequence;
    try {
      await _loadRecordsForRequest(
        requestSequence,
        remoteRefresh: remoteRefresh,
      );
    } catch (error) {
      if (!_isCurrentLoad(requestSequence)) return;
      setState(() {
        _recordsLoaded = true;
        _accountingWarning =
            'تعذر إكمال تحديث السجلات. احتفظ النظام بآخر نسخة محلية آمنة. حاول المزامنة مرة أخرى.';
      });
    }
  }

  bool _isCurrentLoad(int requestSequence) =>
      mounted &&
      isCurrentModuleLoad(
        requestSequence: requestSequence,
        activeSequence: _loadSequence,
      );

  Future<void> _loadRecordsForRequest(
    int requestSequence, {
    required bool remoteRefresh,
  }) async {
    await BusinessIdentityStore.instance.ensureLoaded();
    final raw = (await SharedPreferences.getInstance()).getString(_storageKey);
    List<_ModuleRecord> current = [];
    try {
      if (raw != null) {
        current = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map(
              (item) => _ModuleRecord.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
    } catch (_) {
      /* Corrupt local cache: do not destroy existing records. */
    }
    final verifiedDisplay =
        widget.module.key.startsWith('reports.') ||
        const {
          'inventory.movements',
          'inventory.valuation',
          'accounts.journals',
          'accounts.statements',
          'debts.dues',
        }.contains(widget.module.key);
    if (verifiedDisplay) {
      current = await _readVerifiedReportCache();
    }
    if (_isSettlementModule && remoteRefresh) {
      try {
        current = await _canonicalSettlementRecords(widget.module.key);
        if (!_isCurrentLoad(requestSequence)) return;
        await (await SharedPreferences.getInstance()).setString(
          _storageKey,
          jsonEncode(current.map((record) => record.toJson()).toList()),
        );
      } catch (_) {
        // Offline-first: keep the last canonical settlement snapshot.
      }
    }
    if (_isDocument &&
        !_isSettlementModule &&
        !verifiedDisplay &&
        remoteRefresh &&
        _documentApi != null &&
        _branchId != null) {
      try {
        final remote = await _documentApi!.list(_branchId!, widget.module.key);
        if (!_isCurrentLoad(requestSequence)) return;
        final synchronized = remote.map(_ModuleRecord.fromServerJson).toList();
        // Never submit pending accounting documents while merely opening or
        // refreshing a page. The durable outbox owns all retries.
        synchronized.addAll(current.where((record) => record.serverId.isEmpty));
        current = synchronized;
        await (await SharedPreferences.getInstance()).setString(
          _storageKey,
          jsonEncode(current.map((record) => record.toJson()).toList()),
        );
      } catch (_) {
        // Offline-first: keep the local cache when the server is unavailable.
      }
    }
    // Canonical catalog: never mix outdated generic module records with
    // freshly synchronized catalog rows; server IDs make updates idempotent.
    if (widget.module.key == 'products') {
      if (remoteRefresh && _catalogApi != null) {
        try {
          final remote = await _catalogApi!.list(
            'products',
            branchId: _branchId,
          );
          if (!_isCurrentLoad(requestSequence)) return;
          await ProductCatalogStore(
            _tenantScope,
          ).replaceRemoteSnapshot(remote.map(CatalogProduct.fromServer));
        } catch (_) {
          // Offline: retain the most recent device catalog.
        }
      }
      current = (await ProductCatalogStore(_tenantScope).read())
          .map(
            (p) => _ModuleRecord(
              title: p.name,
              details: [
                p.category,
                p.subcategory,
              ].where((value) => value.isNotEmpty).join(' • '),
              barcode: p.barcode,
              salePrice: p.salePrice,
              purchasePrice: p.purchasePrice,
              stockQuantity: p.stockQuantity ?? 0,
              unitName: p.unitName,
              serverId: p.id,
              version: p.version,
              updatedAt: DateTime.now(),
            ),
          )
          .toList();
    }
    if (widget.module.key == 'customers') {
      if (remoteRefresh && _catalogApi != null) {
        try {
          final remote = await _catalogApi!.list('customers');
          if (!_isCurrentLoad(requestSequence)) return;
          await CustomerStore(_tenantScope).replaceRemoteSnapshot(remote);
        } catch (_) {
          // Offline: last known customer state remains visible.
        }
      }
      current = (await CustomerStore(_tenantScope).read())
          .map(
            (p) => _ModuleRecord(
              title: p.name,
              details: p.phone,
              serverId: p.id,
              version: p.version,
              updatedAt: p.updatedAt,
            ),
          )
          .toList();
    }
    if (widget.module.key == 'suppliers' && _catalogApi != null) {
      try {
        final remote = await _catalogApi!.list('suppliers');
        if (!_isCurrentLoad(requestSequence)) return;
        current = remote
            .map(
              (item) => _ModuleRecord(
                title: item['name']?.toString() ?? '',
                details: item['phone']?.toString() ?? '',
                serverId: item['id']?.toString() ?? '',
                version: (item['version'] as num?)?.toInt() ?? 1,
                updatedAt:
                    DateTime.tryParse(item['updated_at']?.toString() ?? '') ??
                    DateTime.now(),
              ),
            )
            .where((record) => record.title.isNotEmpty)
            .toList();
      } catch (_) {
        // Keep the last local supplier directory while offline.
      }
    }
    // Customer directory may display a local pending receivable indicator,
    // but audited debt reports use only the server accounting API or a cached
    // previously verified snapshot (never unposted local invoice drafts).
    if (widget.module.key == 'customers') {
      final invoices = <InvoiceDocument>[];
      for (final branch
          in widget.branchIds.isEmpty ? const ['MAIN'] : widget.branchIds) {
        invoices.addAll(await InvoiceHistoryStore().read(_tenantScope, branch));
        if (!_isCurrentLoad(requestSequence)) return;
      }
      if (widget.module.key == 'debts.dues' ||
          widget.module.key == 'reports.debts') {
        current.removeWhere((record) => record.serverId.startsWith('invoice:'));
        current.addAll(
          invoices
              .where((invoice) => invoice.currentDueAmount > 0)
              .map(
                (invoice) => _ModuleRecord(
                  title: invoice.customerName,
                  details:
                      '${invoice.displayNumber} • آجل • الإجمالي ${invoice.total.toStringAsFixed(2)} • المتبقي ${invoice.currentDueAmount.toStringAsFixed(2)} YER',
                  amount: invoice.currentDueAmount,
                  dueAt: invoice.createdAt.add(const Duration(hours: 48)),
                  settled: invoice.currentDueAmount <= 0,
                  serverId: 'invoice:${invoice.displayNumber}',
                  updatedAt: invoice.createdAt,
                ),
              ),
        );
      } else if (widget.module.key == 'reports.sales' ||
          widget.module.key == 'reports.daily') {
        current.removeWhere((record) => record.serverId.startsWith('invoice:'));
        current.addAll(
          invoices.map(
            (invoice) => _ModuleRecord(
              title: invoice.displayNumber,
              details:
                  '${invoice.customerName} • ${invoice.currentPaymentLabel} • مدفوع ${invoice.currentPaidAmount.toStringAsFixed(2)} • متبقٍ ${invoice.currentDueAmount.toStringAsFixed(2)} YER',
              amount: invoice.total - invoice.returnedAmount,
              settled: invoice.currentDueAmount <= 0,
              serverId: 'invoice:${invoice.displayNumber}',
              updatedAt: invoice.createdAt,
            ),
          ),
        );
      } else if (widget.module.key == 'reports.cash') {
        current.removeWhere((record) => record.serverId.startsWith('invoice:'));
        current.addAll(
          invoices
              .where((invoice) => invoice.currentPaidAmount > 0)
              .map(
                (invoice) => _ModuleRecord(
                  title: invoice.displayNumber,
                  details:
                      '${invoice.customerName} • ${invoice.currentPaymentLabel} • المحصل ${invoice.currentPaidAmount.toStringAsFixed(2)} YER',
                  amount: invoice.currentPaidAmount,
                  settled: true,
                  serverId: 'invoice:${invoice.displayNumber}',
                  updatedAt: invoice.createdAt,
                ),
              ),
        );
      } else if (widget.module.key == 'reports.customers') {
        current.removeWhere(
          (record) => record.serverId.startsWith('customer:'),
        );
        final totals = <String, double>{};
        for (final invoice in invoices.where(
          (item) => item.currentDueAmount > 0,
        )) {
          totals[invoice.customerName] =
              (totals[invoice.customerName] ?? 0) + invoice.currentDueAmount;
        }
        current.addAll(
          totals.entries.map(
            (entry) => _ModuleRecord(
              title: entry.key,
              details:
                  'إجمالي الدين المستحق: ${entry.value.toStringAsFixed(2)} YER',
              amount: entry.value,
              serverId: 'customer:${entry.key}',
              updatedAt: DateTime.now(),
            ),
          ),
        );
      } else if (widget.module.key == 'customers') {
        final totals = <String, double>{};
        for (final invoice in invoices.where(
          (item) => item.currentDueAmount > 0,
        )) {
          totals[invoice.customerName.toLowerCase()] =
              (totals[invoice.customerName.toLowerCase()] ?? 0) +
              invoice.currentDueAmount;
        }
        current = current.map((record) {
          final due = totals[record.title.toLowerCase()] ?? 0;
          return due <= 0
              ? record
              : _ModuleRecord(
                  title: record.title,
                  details:
                      '${record.details}\nدين مستحق: ${due.toStringAsFixed(2)} YER',
                  amount: due,
                  updatedAt: record.updatedAt,
                  serverId: record.serverId,
                  version: record.version,
                  clientOperationId: record.clientOperationId,
                  restoreGenerationAtCreation:
                      record.restoreGenerationAtCreation,
                );
        }).toList();
      }
    }
    current = await _accountingRecords(current, requestSequence);
    if (!_isCurrentLoad(requestSequence)) return;
    if (verifiedDisplay &&
        _accountingWarning == null &&
        _accountingApi != null &&
        _branchId != null) {
      try {
        await _saveVerifiedReportCache(current);
      } catch (_) {
        // A cache write failure must not hide an otherwise valid report.
        _accountingWarning =
            'عُرض التقرير الحالي، لكن تعذر حفظ نسخة محلية منه.';
      }
      if (!_isCurrentLoad(requestSequence)) return;
    }
    setState(() {
      _records
        ..clear()
        ..addAll(current);
      _recordsLoaded = true;
    });
    final overdue = current.where((record) => record.isOverdue).length;
    if (overdue > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrentLoad(requestSequence)) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(
              'تنبيه: يوجد $overdue دين تجاوز مهلة التذكير 48 ساعة.',
            ),
            action: SnackBarAction(
              label: 'عرض',
              onPressed: () {
                if (mounted) setState(() => _statusFilter = 'overdue');
              },
            ),
          ),
        );
      });
    }
  }

  Future<void> _persistRecords() async {
    await (await SharedPreferences.getInstance()).setString(
      _storageKey,
      jsonEncode(_records.map((record) => record.toJson()).toList()),
    );
  }

  Future<List<_ModuleRecord>> _accountingRecords(
    List<_ModuleRecord> current,
    int requestSequence,
  ) async {
    final token = widget.token;
    final branchId = _branchId;
    if (token == null || token.isEmpty || branchId == null) return current;
    final key = widget.module.key;
    const supported = {
      'accounts.journals',
      'accounts.statements',
      'inventory.movements',
      'inventory.valuation',
      'reports.inventory',
      'reports.purchases',
      'reports.sales',
      'reports.daily',
      'reports.cash',
      'reports.debts',
      'reports.customers',
      'debts.dues',
      'customers',
    };
    if (!supported.contains(key)) return current;
    final api = AccountingApi(token: token);
    if (_isCurrentLoad(requestSequence)) _accountingWarning = null;
    try {
      if (key == 'reports.cash') {
        final entries = await api.listJournals(branchId: branchId);
        return entries
            .where((entry) => FinancialProjection.cashMovement(entry) != 0)
            .map((entry) {
              final value = FinancialProjection.cashMovement(entry);
              return _ModuleRecord(
                title: _journalLabel(entry['reference_type']?.toString() ?? ''),
                details:
                    'صافي حركة النقد والبنوك والمحافظ من القيود المرحلة • ${(value / 100).toStringAsFixed(2)} YER',
                amount: value / 100,
                settled: true,
                serverId: 'cash-journal:${entry['id']}',
                updatedAt:
                    DateTime.tryParse(entry['posted_at']?.toString() ?? '') ??
                    DateTime.now(),
              );
            })
            .toList();
      }
      if (key == 'accounts.journals') {
        final entries = await api.listJournals(branchId: branchId);
        return entries.map((entry) {
          final lines = entry['lines'] is List
              ? entry['lines'] as List
              : const [];
          final debit = lines.whereType<Map>().fold<int>(
            0,
            (sum, line) => sum + ((line['debit_minor'] as num?)?.toInt() ?? 0),
          );
          final accounts = lines
              .whereType<Map>()
              .map((line) => line['account_code']?.toString() ?? '')
              .where((code) => code.isNotEmpty)
              .join(' ↔ ');
          return _ModuleRecord(
            title: _journalLabel(entry['reference_type']?.toString() ?? ''),
            details: '$accounts • ${(debit / 100).toStringAsFixed(2)} YER',
            amount: debit / 100,
            settled: true,
            serverId: 'journal:${entry['id']}',
            updatedAt:
                DateTime.tryParse(entry['posted_at']?.toString() ?? '') ??
                DateTime.now(),
          );
        }).toList();
      }
      if (key == 'accounts.statements') {
        final balances = await api.trialBalance(branchId: branchId);
        return balances.map((balance) {
          final debit = (balance['debit_minor'] as num?)?.toInt() ?? 0;
          final credit = (balance['credit_minor'] as num?)?.toInt() ?? 0;
          final net = (balance['balance_minor'] as num?)?.toInt() ?? 0;
          return _ModuleRecord(
            title:
                '${balance['account_code'] ?? ''} • ${balance['name_ar'] ?? balance['name_en'] ?? ''}',
            details:
                'مدين ${(debit / 100).toStringAsFixed(2)} • دائن ${(credit / 100).toStringAsFixed(2)} YER',
            amount: net.abs() / 100,
            settled: net == 0,
            serverId: 'balance:${balance['account_code']}',
            updatedAt: DateTime.now(),
          );
        }).toList();
      }
      if ({
        'inventory.movements',
        'inventory.valuation',
        'reports.inventory',
      }.contains(key)) {
        if (key == 'inventory.valuation') {
          final totals = await api.stockValuation(branchId: branchId);
          if (totals.any((row) => row['value_minor'] == null)) {
            throw StateError(
              'توجد حركات تاريخية غير مقيمة. يلزم فحص مطابقة المخزون قبل عرض إجمالي مالي.',
            );
          }
          return totals
              .map((row) {
                final quantity =
                    ((row['quantity_milli'] as num?)?.toDouble() ?? 0) / 1000;
                final value = (row['value_minor'] as num).toDouble() / 100;
                return _ModuleRecord(
                  title: row['product_name']?.toString() ?? 'صنف',
                  details:
                      'الرصيد ${quantity.toStringAsFixed(3)} • القيمة بالتكلفة ${value.toStringAsFixed(2)} YER',
                  amount: value,
                  settled: true,
                  serverId:
                      'valuation:${row['branch_id']}:${row['product_id']}',
                  updatedAt: DateTime.now(),
                );
              })
              .toList(growable: false);
        }
        final movements = await api.listStockMovements(branchId: branchId);
        final records = movements.map((movement) {
          final quantity =
              ((movement['quantity_milli'] as num?)?.toDouble() ?? 0) / 1000;
          final cost =
              ((movement['unit_cost_minor'] as num?)?.toDouble() ?? 0) / 100;
          return _ModuleRecord(
            title: movement['product_name']?.toString() ?? 'صنف',
            details:
                '${_movementLabel(movement['reference_type']?.toString() ?? '')} • كمية ${quantity.toStringAsFixed(3)} • ${movement['value_minor'] == null ? 'قيمة الحركة غير مقيمة' : 'تكلفة ${cost.toStringAsFixed(2)} YER'} • ${movement['invoice_number'] ?? ''}',
            amount: movement['value_minor'] is num
                ? (movement['value_minor'] as num).toDouble() / 100
                : 0, // Unknown historical valuation is NOT quantity × latest cost.
            settled: true,
            serverId: 'stock:${movement['id']}',
            updatedAt:
                DateTime.tryParse(movement['occurred_at']?.toString() ?? '') ??
                DateTime.now(),
          );
        }).toList();
        // Generic stock notes are not posted stock movements and must not inflate this ledger report.
        records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return records;
      }

      final needsSales = {
        'reports.sales',
        'reports.daily',
        'reports.cash',
        'reports.debts',
        'reports.customers',
        'debts.dues',
        'customers',
      }.contains(key);
      final needsPurchases = {
        'reports.purchases',
        'reports.daily',
        'reports.cash',
        'reports.debts',
        'debts.dues',
      }.contains(key);
      final sales = needsSales
          ? await api.listInvoices(branchId: branchId)
          : const <Map<String, dynamic>>[];
      final purchases = needsPurchases
          ? await api.listPurchases(branchId: branchId)
          : const <Map<String, dynamic>>[];

      if (key == 'customers' || key == 'reports.customers') {
        // Group by the immutable contact ID. Two customers with the same
        // display name must NEVER share a balance in receivables reports.
        String customerKey(Map<String, dynamic> invoice) {
          final contact = invoice['contact_id']?.toString().trim() ?? '';
          if (contact.isNotEmpty) return 'id:$contact';
          return 'legacy:${(invoice['customer_name']?.toString() ?? '').trim().toLowerCase()}';
        }

        final grouped = <String, int>{};
        final names = <String, String>{};
        for (final invoice in sales) {
          final dueMinor = (invoice['due_minor'] as num?)?.toInt() ?? 0;
          if (dueMinor <= 0 || invoice['status']?.toString() == 'voided') {
            continue;
          }
          final group = customerKey(invoice);
          grouped[group] = (grouped[group] ?? 0) + dueMinor;
          names[group] = invoice['customer_name']?.toString() ?? 'عميل';
        }
        if (key == 'customers') {
          return current.map((record) {
            final idKey = 'id:${record.serverId}';
            final legacyKey = 'legacy:${record.title.trim().toLowerCase()}';
            final dueMinor = (grouped[idKey] ?? 0) + (grouped[legacyKey] ?? 0);
            final due = dueMinor / 100;
            return record.copyWith(
              details: dueMinor > 0
                  ? '${record.details}\nدين مستحق: ${due.toStringAsFixed(2)} YER'
                  : record.details,
              amount: due,
            );
          }).toList();
        }
        return grouped.entries.map((entry) {
          final due = entry.value / 100;
          return _ModuleRecord(
            title: names[entry.key] ?? 'عميل',
            details: 'إجمالي الدين المستحق: ${due.toStringAsFixed(2)} YER',
            amount: due,
            serverId: 'customer-balance:${entry.key}',
            updatedAt: DateTime.now(),
          );
        }).toList();
      }
      final result = <_ModuleRecord>[];
      if (needsSales) {
        for (final invoice in sales) {
          final due = ((invoice['due_minor'] as num?)?.toDouble() ?? 0) / 100;
          if ({'reports.debts', 'debts.dues'}.contains(key) && due <= 0) {
            continue;
          }
          final mode =
              invoice['payment_mode_at_issue']?.toString() ??
              invoice['payment_mode']?.toString() ??
              '';
          if (key == 'reports.cash' && mode != 'cash') {
            continue;
          }
          result.add(
            _serverInvoiceRecord(
              invoice,
              party: invoice['customer_name']?.toString() ?? 'عميل نقدي',
              kind: 'مبيعات',
              amount: {'reports.debts', 'debts.dues'}.contains(key)
                  ? due
                  : null,
            ),
          );
        }
      }
      if (needsPurchases) {
        for (final invoice in purchases) {
          if (invoice['status']?.toString() == 'voided') continue;
          final supplierDue = (invoice['due_minor'] as num?)?.toInt() ?? 0;
          if ({'reports.debts', 'debts.dues'}.contains(key) &&
              supplierDue <= 0) {
            continue;
          }
          final mode =
              invoice['payment_mode_at_issue']?.toString() ??
              invoice['payment_mode']?.toString() ??
              '';
          if (key == 'reports.cash' && mode != 'cash') {
            continue;
          }
          result.add(
            _serverInvoiceRecord(
              invoice,
              party: invoice['supplier_name']?.toString() ?? 'مورد',
              kind: {'reports.debts', 'debts.dues'}.contains(key)
                  ? 'ذمم موردين'
                  : 'مشتريات',
              // Sign is negative for supplier obligations: these are
              // liabilities, not customer receivables.
              amount: {'reports.debts', 'debts.dues'}.contains(key)
                  ? -(supplierDue / 100)
                  : key == 'reports.cash'
                  ? -(((invoice['total_minor'] as num?)?.toDouble() ?? 0) / 100)
                  : null,
            ),
          );
        }
      }
      if ({'reports.sales', 'reports.daily'}.contains(key)) {
        for (final invoice in await api.listReturns(
          branchId: branchId,
          type: 'sale_return',
        )) {
          result.add(
            _serverInvoiceRecord(
              invoice,
              party: invoice['party_name_snapshot']?.toString() ?? 'عميل',
              kind: 'مرتجع مبيعات',
            ),
          );
        }
      }
      if ({'reports.purchases', 'reports.daily'}.contains(key)) {
        for (final invoice in await api.listReturns(
          branchId: branchId,
          type: 'purchase_return',
        )) {
          result.add(
            _serverInvoiceRecord(
              invoice,
              party: invoice['party_name_snapshot']?.toString() ?? 'مورد',
              kind: 'مرتجع مشتريات',
            ),
          );
        }
      }
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (error) {
      if (_isCurrentLoad(requestSequence)) {
        _accountingWarning =
            'تعذر التحقق من الخادم: $error. البيانات المحلية ليست تقريرًا ماليًا مؤكدًا.';
      }
      return key == 'inventory.valuation' || key == 'reports.cash'
          ? []
          : current;
    }
  }

  _ModuleRecord _serverInvoiceRecord(
    Map<String, dynamic> invoice, {
    required String party,
    required String kind,
    double? amount,
  }) {
    final total = ((invoice['total_minor'] as num?)?.toDouble() ?? 0) / 100;
    final paid = ((invoice['paid_minor'] as num?)?.toDouble() ?? 0) / 100;
    final due = ((invoice['due_minor'] as num?)?.toDouble() ?? 0) / 100;
    final isReturn = const {
      'sale_return',
      'purchase_return',
    }.contains(invoice['type']);
    return _ModuleRecord(
      title: invoice['number']?.toString() ?? kind,
      details: isReturn
          ? '$kind • $party • المرتجع ${total.toStringAsFixed(2)} • رد المال ${paid.toStringAsFixed(2)} • خفض الدين ${due.toStringAsFixed(2)} YER'
          : '$kind • $party • الإجمالي الأصلي ${total.toStringAsFixed(2)} • المدفوع الحالي ${paid.toStringAsFixed(2)} • المتبقي ${due.toStringAsFixed(2)} YER',
      amount: amount ?? FinancialProjection.invoiceAmount(invoice) / 100,
      settled: isReturn || due <= 0,
      serverId: 'server-invoice:${invoice['id']}',
      updatedAt:
          DateTime.tryParse(invoice['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String _journalLabel(String type) => switch (type) {
    'manual_journal' => 'قيد يومية بسيط',
    'sale_invoice' => 'قيد فاتورة مبيعات',
    'sale_cogs' => 'قيد تكلفة مبيعات',
    'purchase_invoice' => 'قيد فاتورة مشتريات',
    'receipt' => 'قيد سند قبض',
    'supplier_payment' => 'قيد سند صرف',
    'sale_return' => 'قيد مرتجع مبيعات',
    'sale_return_cogs' => 'عكس تكلفة المرتجع',
    'purchase_return' => 'قيد مرتجع مشتريات',
    _ when type.endsWith('_void') => 'قيد عكسي',
    _ => 'قيد يومي',
  };

  String _movementLabel(String type) => switch (type) {
    'purchase_invoice' => 'وارد مشتريات',
    'purchase_invoice_void' => 'عكس مشتريات',
    'sale_invoice' => 'صادر مبيعات',
    'sale_invoice_void' => 'عكس مبيعات',
    'sale_return' => 'وارد مرتجع بيع',
    'purchase_return' => 'صادر مرتجع شراء',
    _ => 'حركة مخزون',
  };

  List<_ModuleFilterOption> get _filterOptions {
    final key = widget.module.key;
    if (key == 'products' || key.startsWith('reports.')) return const [];
    if (key == 'customers') {
      if (!_records.any((record) => record.amount != 0)) return const [];
      return const [
        _ModuleFilterOption('balance', 'عليه رصيد'),
        _ModuleFilterOption('zero_balance', 'بدون رصيد'),
      ];
    }
    if (key == 'suppliers') {
      if (!_records.any((record) => record.amount != 0)) return const [];
      return const [
        _ModuleFilterOption('balance', 'له مستحقات'),
        _ModuleFilterOption('zero_balance', 'بدون مستحقات'),
      ];
    }
    if (key == 'inventory.valuation') {
      return const [
        _ModuleFilterOption('available', 'متوفر'),
        _ModuleFilterOption('low_stock', 'منخفض'),
        _ModuleFilterOption('out_of_stock', 'نافد'),
      ];
    }
    if (key.startsWith('purchases.')) {
      return const [
        _ModuleFilterOption('settled', 'مدفوعة'),
        _ModuleFilterOption('open', 'غير مدفوعة'),
      ];
    }
    if (key == 'debts.receipts' || key == 'debts.payments') {
      return const [
        _ModuleFilterOption('settled', 'مرحّل'),
        _ModuleFilterOption('open', 'معلّق'),
      ];
    }
    if (_isDocument) {
      return const [
        _ModuleFilterOption('open', 'مفتوح'),
        _ModuleFilterOption('settled', 'مكتمل'),
        _ModuleFilterOption('overdue', 'متأخر'),
      ];
    }
    return const [];
  }

  bool get _supportsDateFilter {
    final key = widget.module.key;
    return key.startsWith('reports.') ||
        key.startsWith('purchases.') ||
        key.startsWith('debts.') ||
        key.startsWith('accounting.') ||
        _isDocument;
  }

  double _inventoryQuantity(_ModuleRecord record) {
    final match = RegExp(
      r'(?:الرصيد|كمية)\s+(-?[0-9]+(?:\.[0-9]+)?)',
    ).firstMatch(record.details);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  List<_ModuleRecord> get _visibleRecords {
    final normalizedQuery = _query.trim().toLowerCase();
    return _records
        .where((record) {
          final matchesQuery =
              normalizedQuery.isEmpty ||
              record.title.toLowerCase().contains(normalizedQuery) ||
              record.details.toLowerCase().contains(normalizedQuery);
          final categoryParts = record.details.split(' • ');
          final matchesCategory =
              widget.module.key != 'products' ||
              (_categoryFilter.isEmpty ||
                      (categoryParts.isNotEmpty &&
                          categoryParts.first == _categoryFilter)) &&
                  (_subcategoryFilter.isEmpty ||
                      (categoryParts.length > 1 &&
                          categoryParts[1] == _subcategoryFilter));
          final matchesStatus = switch (_statusFilter) {
            'open' => !record.settled && !record.isVoided,
            'settled' => record.settled,
            'overdue' => record.isOverdue,
            'balance' => record.amount > 0,
            'zero_balance' => record.amount == 0,
            'available' => _inventoryQuantity(record) > 5,
            'low_stock' =>
              _inventoryQuantity(record) > 0 && _inventoryQuantity(record) <= 5,
            'out_of_stock' => _inventoryQuantity(record) <= 0,
            _ => true,
          };
          final day = DateTime(
            record.updatedAt.year,
            record.updatedAt.month,
            record.updatedAt.day,
          );
          final matchesDate =
              _dateRange == null ||
              (!day.isBefore(_dateRange!.start) &&
                  !day.isAfter(_dateRange!.end));
          return matchesQuery &&
              matchesCategory &&
              matchesStatus &&
              matchesDate;
        })
        .toList(growable: false);
  }

  Future<void> _pickDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
      helpText: 'اختر فترة العرض',
      cancelText: 'إلغاء',
      confirmText: 'اعتماد',
    );
    if (selected != null && mounted) setState(() => _dateRange = selected);
  }

  Future<Uint8List> _buildListPdf(List<_ModuleRecord> records) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latinFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final profile = _profile;
    final document = pw.Document(
      title: '${widget.module.title} - ${profile.businessName}',
      author: widget.tenantName,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latinFont],
        ),
        margin: const pw.EdgeInsets.all(20),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              profile.businessName,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            if (profile.businessNameEn.isNotEmpty)
              pw.Text(
                profile.businessNameEn,
                textDirection: pw.TextDirection.ltr,
                style: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 5),
            pw.Text(
              widget.module.title,
              style: pw.TextStyle(
                color: PdfColor.fromInt(widget.module.color.toARGB32()),
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'البيان',
              'التفاصيل',
              'المبلغ',
              'الحالة',
              'التاريخ',
            ],
            data: [
              for (var i = 0; i < records.length; i++)
                [
                  _pdfLatin('${i + 1}', latinFont),
                  _pdfMixed(records[i].title, font, latinFont),
                  _pdfMixed(
                    records[i].details.replaceAll('\n', ' '),
                    font,
                    latinFont,
                  ),
                  _pdfLatin(
                    records[i].amount == 0
                        ? '-'
                        : '${records[i].amount.toStringAsFixed(2)} ${records[i].currency}',
                    latinFont,
                  ),
                  records[i].statusLabel,
                  _pdfLatin(_dateLabel(records[i].updatedAt), latinFont),
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromInt(widget.module.color.toARGB32()),
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerRight,
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Text(
                'عدد السجلات',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 5),
              _pdfLatin('${records.length}', latinFont, bold: true),
              pw.SizedBox(width: 14),
              pw.Text(
                'الإجمالي',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 5),
              _pdfLatin(
                '${records.fold<double>(0, (sum, item) => sum + item.amount).toStringAsFixed(2)} YER',
                latinFont,
                bold: true,
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  // Kept for legacy exports that may be restored from older navigation paths.
  // ignore: unused_element
  Future<Uint8List> _buildContactStatementPdf({
    required String contactName,
    required String contactPhone,
    required List<Map<String, dynamic>> rows,
    required int closingBalanceMinor,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latinFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final profile = _profile;
    final document = pw.Document(
      title: 'كشف حساب $contactName - ${profile.businessName}',
      author: widget.tenantName,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latinFont],
        ),
        margin: const pw.EdgeInsets.all(20),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              profile.businessName,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'كشف حساب $contactName',
              style: pw.TextStyle(
                color: PdfColor.fromInt(widget.module.color.toARGB32()),
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (contactPhone.trim().isNotEmpty)
              _pdfLatin(contactPhone.trim(), latinFont),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'],
            data: [
              for (final row in rows)
                [
                  _pdfLatin(
                    row['posted_at']?.toString().split('T').first ?? '',
                    latinFont,
                  ),
                  _pdfMixed(
                    row['description']?.toString() ?? 'حركة حساب',
                    font,
                    latinFont,
                  ),
                  _pdfLatin(
                    (((row['debit_minor'] as num?)?.toInt() ?? 0) / 100)
                        .toStringAsFixed(2),
                    latinFont,
                  ),
                  _pdfLatin(
                    (((row['credit_minor'] as num?)?.toInt() ?? 0) / 100)
                        .toStringAsFixed(2),
                    latinFont,
                  ),
                  _pdfLatin(
                    (((row['balance_minor'] as num?)?.toInt() ?? 0) / 100)
                        .toStringAsFixed(2),
                    latinFont,
                    bold: true,
                  ),
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromInt(widget.module.color.toARGB32()),
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerRight,
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Text(
                'الرصيد الختامي',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 6),
              _pdfLatin(
                '${(closingBalanceMinor / 100).toStringAsFixed(2)} YER',
                latinFont,
                bold: true,
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _exportList(String action) async {
    final records = _visibleRecords;
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _buildListPdf(records);
      final name =
          '${widget.module.key}-${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (action == 'share') {
        await PdfExportService.share(bytes: bytes, filename: name);
      } else if (action == 'print') {
        await PdfExportService.print(bytes: bytes, filename: name);
      } else {
        await PdfExportService.save(bytes: bytes, filename: name);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تجهيز ملف PDF بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تصدير PDF: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _loadSequence++;
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addRecord() async {
    if (!_canAddRecord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا تملك صلاحية إضافة سجل في هذا القسم.')),
      );
      return;
    }
    if (widget.module.key == 'debts.receipts') {
      await _addCustomerReceipt();
      return;
    }
    if (widget.module.key == 'debts.payments') {
      await _addSupplierPayment();
      return;
    }
    var record = await showDialog<_ModuleRecord>(
      context: context,
      builder: (context) => _AddRecordDialog(module: widget.module),
    );
    if (record == null || !mounted) {
      return;
    }
    if (widget.module.key == 'products') {
      final saved = await ProductCatalogStore(_tenantScope).save(
        CatalogProduct(
          name: record.title,
          purchasePrice: record.purchasePrice,
          salePrice: record.salePrice,
          barcode: record.barcode,
        ),
      );
      record = record.copyWith(barcode: saved.barcode);
    }
    if (widget.module.key == 'customers') {
      await CustomerStore(_tenantScope).save(record.title, record.details);
    }
    setState(() => _records.insert(0, record!));
    await _persistRecords();
    await _syncRecord(record);
    record = await _syncCatalogRecord(record);
    if (widget.module.key == 'purchases') await _saveCatalogProduct(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ ${widget.module.entityLabel} بنجاح.')),
    );
  }

  Future<void> _addCustomerReceipt() => _addGeneralVoucher(receipt: true);

  Future<void> _addSupplierPayment() => _addGeneralVoucher(receipt: false);

  Future<void> _addGeneralVoucher({required bool receipt}) async {
    final token = widget.token;
    final branchId = _branchId;
    if (token == null || token.isEmpty || branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يلزم الاتصال بالخادم لإصدار سند ${receipt ? 'قبض' : 'صرف'}.',
          ),
        ),
      );
      return;
    }
    try {
      final api = AccountingApi(token: token);
      final allAccounts = (await ChartAccountsApi(token).list(branchId))
          .where((item) => item.active && item.allowPosting)
          .toList(growable: false);
      final cashAccounts = allAccounts
          .where((item) => item.isCashEquivalent)
          .toList(growable: false);
      final counterAccounts = allAccounts
          .where((item) => !item.isCashEquivalent)
          .toList(growable: false);
      final directory = await api.accountDirectory(branchId: branchId);
      final contacts = directory
          .where((item) => item['kind'] == 'contact')
          .toList(growable: false);
      if (!mounted) return;

      var partyKind = receipt ? 'customer' : 'supplier';
      Map<String, dynamic>? selectedContact;
      List<Map<String, dynamic>> candidates() => contacts
          .where((item) => item['role'] == partyKind || item['role'] == 'both')
          .toList(growable: false);
      if (candidates().isNotEmpty) {
        selectedContact = candidates().first;
      } else {
        partyKind = 'other';
      }
      final partyName = TextEditingController();
      final partyPhone = TextEditingController();
      final amount = TextEditingController();
      final notes = TextEditingController(
        text: receipt ? 'سند قبض من الطرف' : 'سند صرف للطرف',
      );
      var cashAccountCode = cashAccounts.firstOrNull?.code ?? '';
      var counterAccountCode =
          counterAccounts
              .where((item) => item.code == (receipt ? '1200-AR' : '2100-AP'))
              .firstOrNull
              ?.code ??
          counterAccounts.firstOrNull?.code ??
          '';
      var channel = _channelForAccount(cashAccountCode);

      final decision = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) {
            final availableContacts = candidates();
            return AlertDialog(
              key: const ValueKey('voucher-document-shell'),
              titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
              title: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      receipt ? Icons.wallet_rounded : Icons.outbox_rounded,
                      color: const Color(0xFF1554B8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      receipt
                          ? 'سند قبض لأي شخص أو جهة'
                          : 'سند صرف لأي شخص أو جهة',
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NineSoftDocumentTypeSwitch(
                        value: receipt ? 'receipt' : 'payment',
                        onChanged: (value) {
                          if (value == (receipt ? 'receipt' : 'payment')) {
                            return;
                          }
                          Navigator.pop(dialogContext, value);
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: partyKind,
                        decoration: const InputDecoration(
                          labelText: 'نوع الطرف',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'customer',
                            child: Text('عميل'),
                          ),
                          DropdownMenuItem(
                            value: 'supplier',
                            child: Text('مورد'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('موظف / عامل / شخص أو جهة أخرى'),
                          ),
                        ],
                        onChanged: (value) => update(() {
                          partyKind = value ?? 'other';
                          final matches = candidates();
                          selectedContact = matches.firstOrNull;
                          final preferred = partyKind == 'customer'
                              ? '1200-AR'
                              : partyKind == 'supplier'
                              ? '2100-AP'
                              : (receipt ? '4100-SALES' : '5200-EXPENSES');
                          counterAccountCode =
                              counterAccounts
                                  .where((item) => item.code == preferred)
                                  .firstOrNull
                                  ?.code ??
                              counterAccountCode;
                        }),
                      ),
                      const SizedBox(height: 10),
                      if (partyKind != 'other')
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue:
                              availableContacts.contains(selectedContact)
                              ? selectedContact
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'اسم الطرف',
                          ),
                          items: availableContacts
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item['name']?.toString() ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              update(() => selectedContact = value),
                        )
                      else ...[
                        TextField(
                          controller: partyName,
                          decoration: const InputDecoration(
                            labelText: 'اسم الشخص أو الجهة',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: partyPhone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف (اختياري)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [latinDigitFormatter],
                        decoration: InputDecoration(
                          labelText: receipt
                              ? 'المبلغ المقبوض'
                              : 'المبلغ المصروف',
                          suffixText: 'YER',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: cashAccountCode.isEmpty
                            ? null
                            : cashAccountCode,
                        decoration: InputDecoration(
                          labelText: receipt
                              ? 'حساب استلام المبلغ'
                              : 'حساب دفع المبلغ',
                        ),
                        items: cashAccounts
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.code,
                                child: Text('${item.code} — ${item.nameAr}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => update(() {
                          cashAccountCode = value ?? '';
                          channel = _channelForAccount(cashAccountCode);
                        }),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: counterAccountCode.isEmpty
                            ? null
                            : counterAccountCode,
                        decoration: const InputDecoration(
                          labelText: 'الحساب المقابل',
                        ),
                        items: counterAccounts
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.code,
                                child: Text('${item.code} — ${item.nameAr}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            update(() => counterAccountCode = value ?? ''),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notes,
                        decoration: const InputDecoration(
                          labelText: 'البيان / الملاحظة',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'save'),
                  child: Text(
                    receipt ? 'اعتماد سند القبض' : 'اعتماد سند الصرف',
                  ),
                ),
              ],
            );
          },
        ),
      );
      if (!mounted) return;
      if (decision == 'journal') {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SimpleJournalPage(
              token: token,
              branchIds: widget.branchIds,
              roleCode: widget.roleCode,
              permissions: widget.permissions,
            ),
          ),
        );
        return;
      }
      if (decision == 'receipt' || decision == 'payment') {
        await _addGeneralVoucher(receipt: decision == 'receipt');
        return;
      }
      if (decision != 'save') return;
      final value = double.tryParse(amount.text) ?? 0;
      final selectedName = partyKind == 'other'
          ? partyName.text.trim()
          : selectedContact?['name']?.toString().trim() ?? '';
      if (value <= 0 ||
          selectedName.isEmpty ||
          cashAccountCode.isEmpty ||
          counterAccountCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أكمل اسم الطرف والمبلغ والحسابات المطلوبة.'),
          ),
        );
        return;
      }
      final reason = notes.text.trim().length >= 8
          ? notes.text.trim()
          : (receipt ? 'سند قبض معتمد من الطرف' : 'سند صرف معتمد للطرف');
      final idempotencyStore = SettlementIdempotencyStore(
        tenantScope: _tenantScope,
        branchId: branchId,
      );
      final claim = await idempotencyStore.claim(
        kind: receipt
            ? SettlementOperationKind.customerReceipt
            : SettlementOperationKind.supplierPayment,
        invoiceId:
            'direct|$partyKind|${selectedContact?['contact_id'] ?? selectedName}|$counterAccountCode',
        amountMinor: (value * 100).round(),
        currency: 'YER',
        channel: channel,
        accountCode: cashAccountCode,
        reason: reason,
      );
      final id = await api.storeDirectVoucher(
        receipt: receipt,
        branchId: branchId,
        partyKind: partyKind,
        contactId: selectedContact?['contact_id']?.toString() ?? '',
        partyName: selectedName,
        partyPhone: partyPhone.text.trim(),
        amount: value,
        currency: 'YER',
        idempotencyKey: claim.idempotencyKey,
        channel: channel,
        accountCode: cashAccountCode,
        counterAccountCode: counterAccountCode,
        reason: reason,
      );
      await idempotencyStore.acknowledge(claim);
      if (!mounted) return;
      setState(() {
        _records.insert(
          0,
          _ModuleRecord(
            title: selectedName,
            details: '${receipt ? 'سند قبض' : 'سند صرف'} • $reason',
            amount: value,
            currency: 'YER',
            settled: true,
            serverId: id,
            clientOperationId: claim.idempotencyKey,
            updatedAt: DateTime.now(),
          ),
        );
      });
      await _persistRecords();
      await _loadRecords(remoteRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم اعتماد سند ${receipt ? 'القبض' : 'الصرف'} وترحيله محاسبيًا.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  // Kept as a rollback-compatible implementation for legacy linked invoices.
  // ignore: unused_element
  Future<void> _addCustomerReceiptLinkedInvoice() async {
    final token = widget.token;
    final branchId = _branchId;
    if (token == null || token.isEmpty || branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يلزم الاتصال بالخادم لإصدار سند قبض.')),
      );
      return;
    }
    try {
      final api = AccountingApi(token: token);
      final paymentAccounts = (await ChartAccountsApi(token).list(branchId))
          .where(
            (item) => item.active && item.allowPosting && item.isCashEquivalent,
          )
          .toList(growable: false);
      final invoices = (await api.listInvoices(branchId: branchId))
          .where((item) => ((item['due_minor'] as num?)?.toInt() ?? 0) > 0)
          .toList(growable: false);
      if (!mounted) return;
      if (invoices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد ديون مفتوحة على العملاء.')),
        );
        return;
      }
      var selected = invoices.first;
      final amount = TextEditingController(
        text: (((selected['due_minor'] as num).toDouble()) / 100)
            .toStringAsFixed(2),
      );
      final notes = TextEditingController(text: 'سداد من العميل');
      String channel = 'cash';
      var accountCode = paymentAccounts.firstOrNull?.code ?? '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('سند قبض من عميل'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'العميل والفاتورة الآجلة',
                      prefixIcon: Icon(Icons.person_search_outlined),
                    ),
                    items: invoices
                        .map(
                          (invoice) => DropdownMenuItem(
                            value: invoice,
                            child: Text(
                              '${invoice['customer_name']} • ${invoice['number']} • ${(((invoice['due_minor'] as num).toDouble()) / 100).toStringAsFixed(2)} YER',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      if (value == null) return;
                      selected = value;
                      amount.text =
                          (((value['due_minor'] as num).toDouble()) / 100)
                              .toStringAsFixed(2);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [latinDigitFormatter],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المقبوض',
                      suffixText: 'YER',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SearchableChartAccountField(
                    accounts: paymentAccounts,
                    value: accountCode.isEmpty ? null : accountCode,
                    label: 'حساب القبض الفعلي',
                    hint: 'ابحث عن الصندوق أو البنك أو المحفظة',
                    onChanged: (value) => update(() {
                      accountCode = value ?? '';
                      channel = _channelForAccount(accountCode);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'البيان'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('اعتماد سند القبض'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final paid = double.tryParse(amount.text) ?? 0;
      final due = ((selected['due_minor'] as num).toDouble()) / 100;
      if (paid <= 0 || paid > due) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المبلغ غير صالح أو أكبر من الدين.')),
        );
        return;
      }
      final idempotencyStore = SettlementIdempotencyStore(
        tenantScope: _tenantScope,
        branchId: branchId,
      );
      final idempotencyClaim = await idempotencyStore.claim(
        kind: SettlementOperationKind.customerReceipt,
        invoiceId: selected['id'].toString(),
        amountMinor: (paid * 100).round(),
        currency: 'YER',
        channel: channel,
        accountCode: accountCode,
        reason: notes.text,
      );
      final receiptId = await api.storeReceipt(
        invoiceId: selected['id'].toString(),
        amount: paid,
        currency: 'YER',
        idempotencyKey: idempotencyClaim.idempotencyKey,
        channel: channel,
        accountCode: accountCode,
        reason: notes.text,
      );
      final record = _ModuleRecord(
        title: selected['customer_name']?.toString() ?? 'عميل',
        details: '${selected['number']} • ${notes.text}',
        amount: paid,
        currency: 'YER',
        settled: true,
        serverId: receiptId,
        clientOperationId: idempotencyClaim.idempotencyKey,
        updatedAt: DateTime.now(),
      );
      setState(() => _records.insert(0, record));
      await _persistRecords();
      await _loadRecords(remoteRefresh: true);
      await idempotencyStore.acknowledge(idempotencyClaim);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم اعتماد سند القبض وتخفيض دين العميل مباشرة.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  // Kept as a rollback-compatible implementation for legacy linked invoices.
  // ignore: unused_element
  Future<void> _addSupplierPaymentLinkedInvoice() async {
    final token = widget.token;
    final branchId = _branchId;
    if (token == null || token.isEmpty || branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يلزم الاتصال بالخادم لإصدار سند صرف.')),
      );
      return;
    }
    try {
      final api = AccountingApi(token: token);
      final paymentAccounts = (await ChartAccountsApi(token).list(branchId))
          .where(
            (item) => item.active && item.allowPosting && item.isCashEquivalent,
          )
          .toList(growable: false);
      final invoices = (await api.listPurchases(branchId: branchId))
          .where((item) => ((item['due_minor'] as num?)?.toInt() ?? 0) > 0)
          .toList(growable: false);
      if (!mounted) return;
      if (invoices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد أرصدة مستحقة للموردين.')),
        );
        return;
      }
      var selected = invoices.first;
      final amount = TextEditingController(
        text: (((selected['due_minor'] as num).toDouble()) / 100)
            .toStringAsFixed(2),
      );
      final notes = TextEditingController(text: 'دفعة للمورد');
      var channel = 'cash';
      var accountCode = paymentAccounts.firstOrNull?.code ?? '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('سند صرف لمورد'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'المورد وفاتورة الشراء الآجلة',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: invoices
                        .map(
                          (invoice) => DropdownMenuItem(
                            value: invoice,
                            child: Text(
                              '${invoice['supplier_name']} • ${invoice['number']} • ${(((invoice['due_minor'] as num).toDouble()) / 100).toStringAsFixed(2)} YER',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      if (value == null) return;
                      selected = value;
                      amount.text =
                          (((value['due_minor'] as num).toDouble()) / 100)
                              .toStringAsFixed(2);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [latinDigitFormatter],
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المصروف',
                      suffixText: 'YER',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SearchableChartAccountField(
                    accounts: paymentAccounts,
                    value: accountCode.isEmpty ? null : accountCode,
                    label: 'حساب الصرف الفعلي',
                    hint: 'ابحث عن الصندوق أو البنك أو المحفظة',
                    onChanged: (value) => update(() {
                      accountCode = value ?? '';
                      channel = _channelForAccount(accountCode);
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'البيان'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('اعتماد سند الصرف'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final paid = double.tryParse(amount.text) ?? 0;
      final due = ((selected['due_minor'] as num).toDouble()) / 100;
      if (paid <= 0 || paid > due) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المبلغ غير صالح أو أكبر من المستحق.')),
        );
        return;
      }
      final idempotencyStore = SettlementIdempotencyStore(
        tenantScope: _tenantScope,
        branchId: branchId,
      );
      final idempotencyClaim = await idempotencyStore.claim(
        kind: SettlementOperationKind.supplierPayment,
        invoiceId: selected['id'].toString(),
        amountMinor: (paid * 100).round(),
        currency: 'YER',
        channel: channel,
        accountCode: accountCode,
        reason: notes.text,
      );
      final paymentId = await api.storeSupplierPayment(
        invoiceId: selected['id'].toString(),
        amount: paid,
        currency: 'YER',
        idempotencyKey: idempotencyClaim.idempotencyKey,
        channel: channel,
        accountCode: accountCode,
        reason: notes.text,
      );
      final record = _ModuleRecord(
        title: selected['supplier_name']?.toString() ?? 'مورد',
        details: '${selected['number']} • ${notes.text}',
        amount: paid,
        currency: 'YER',
        settled: true,
        serverId: paymentId,
        clientOperationId: idempotencyClaim.idempotencyKey,
        updatedAt: DateTime.now(),
      );
      setState(() => _records.insert(0, record));
      await _persistRecords();
      await _loadRecords(remoteRefresh: true);
      await idempotencyStore.acknowledge(idempotencyClaim);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم اعتماد سند الصرف وتخفيض رصيد المورد مباشرة.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _editRecord(_ModuleRecord record) async {
    if (!_canEditRecord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا السجل للعرض فقط أو لا تملك صلاحية تعديله.'),
        ),
      );
      return;
    }
    final updated = await showDialog<_ModuleRecord>(
      context: context,
      builder: (context) =>
          _AddRecordDialog(module: widget.module, initial: record),
    );
    if (updated == null || !mounted) return;
    if (widget.module.key == 'products' && record.serverId.isNotEmpty) {
      final changed =
          (record.stockQuantity * 1000).round() !=
          (updated.stockQuantity * 1000).round();
      if (changed) {
        final ok =
            stableStockIncrease(
              current: record.stockQuantity,
              requested: updated.stockQuantity,
            )
            ? await _postStableStockSupply(record, updated)
            : await _postStableStockDecrease(record, updated);
        if (!ok || !mounted) return;
      }
    }
    if (record.serverId.isNotEmpty &&
        _catalogApi != null &&
        (widget.module.key == 'products' ||
            widget.module.key == 'customers' ||
            widget.module.key == 'suppliers')) {
      try {
        if (widget.module.key == 'products') {
          await _catalogApi!.updateProduct(
            id: record.serverId,
            expectedVersion: record.version,
            name: updated.title,
            barcode: updated.barcode,
            salePrice: updated.salePrice,
            purchasePrice: updated.purchasePrice,
            unitName: updated.unitName,
          );
        } else {
          await _catalogApi!.updateContact(
            entity: widget.module.key,
            id: record.serverId,
            expectedVersion: record.version,
            name: updated.title,
            phone: updated.details,
          );
        }
      } catch (error) {
        await CatalogOutbox(_tenantScope).enqueue(
          widget.module.key,
          {
            'id': record.serverId,
            'expected_version': record.version,
            'name': updated.title,
            'phone': updated.details,
            'barcode': updated.barcode,
            'sale_price': updated.salePrice,
            'purchase_price': updated.purchasePrice,
          },
          restoreGenerationAtCreation:
              RealtimeSyncCoordinator.instance.restoreGeneration,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تغيير الاسم على الخادم: $error')),
          );
        }
        return;
      }
    }
    final index = _records.indexOf(record);
    final stable = updated.copyWith(
      serverId: record.serverId,
      version:
          record.version +
          (record.serverId.isNotEmpty &&
                  const {
                    'products',
                    'customers',
                    'suppliers',
                  }.contains(widget.module.key)
              ? 1
              : 0),
    );
    setState(() => _records[index] = stable);
    await _persistRecords();
    await _syncRecord(stable);
    if (record.serverId.isEmpty) await _syncCatalogRecord(stable);
    if (widget.module.key == 'products' && record.title != stable.title) {
      await ProductCatalogStore(_tenantScope).remove(record.title);
    }
    await _saveCatalogProduct(stable);
    if (widget.module.key == 'customers') {
      if (record.title != stable.title) {
        await CustomerStore(_tenantScope).remove(record.title);
      }
      await CustomerStore(_tenantScope).save(updated.title, updated.details);
    }
  }

  Future<bool> _postStableStockSupply(
    _ModuleRecord current,
    _ModuleRecord updated,
  ) async {
    final api = _accountingApi;
    final branchId = _branchId;
    if (api == null || branchId == null || updated.purchasePrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أدخل سعر شراء صحيح قبل زيادة المخزون.'),
          ),
        );
      }
      return false;
    }
    List<Map<String, dynamic>> suppliers = const [];
    try {
      suppliers = await _catalogApi?.list('suppliers') ?? const [];
    } catch (_) {
      // Keep manual supplier entry available if the catalog cannot be refreshed.
    }
    if (!mounted) return false;
    final request = await showDialog<_StableStockSupplyRequest>(
      context: context,
      builder: (_) => _StableStockSupplyDialog(
        productName: updated.title,
        quantity: updated.stockQuantity - current.stockQuantity,
        unitCost: updated.purchasePrice,
        suppliers: suppliers,
      ),
    );
    if (request == null || !mounted) return false;
    try {
      final payload = await api.preparePurchaseRequest(
        branchId: branchId,
        supplierName: request.supplierName,
        supplierPhone: request.supplierPhone,
        paymentMode: request.paymentMode,
        paymentChannel: 'cash',
        operationId: request.operationId,
        restoreGeneration: RealtimeSyncCoordinator.instance.restoreGeneration,
        notes: 'توريد مخزون المحل من شاشة الصنف ${current.title}',
        items: [
          {
            'product_id': current.serverId,
            'name': current.title,
            'kind': 'stock',
            'quantity_milli':
                ((updated.stockQuantity - current.stockQuantity) * 1000)
                    .round(),
            'unit_name': updated.unitName,
            'unit_price_minor': (updated.purchasePrice * 100).round(),
            'sale_price_minor': (updated.salePrice * 100).round(),
          },
        ],
      );
      final outbox = PurchaseOutbox(_tenantScope, branchId);
      await outbox.enqueue(payload);
      final result = await outbox.flush(
        api: api,
        currentRestoreGeneration:
            RealtimeSyncCoordinator.instance.restoreGeneration,
        restoreEpoch: RealtimeSyncCoordinator.instance.restoreEpoch,
      );
      if (result.sent > 0) return true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ طلب التوريد محليًا وسيعاد إرساله تلقائيًا. لن يظهر المخزون الجديد قبل تأكيد الخادم.',
            ),
          ),
        );
      }
      return false;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('لم يتم توريد المخزون: $error')));
      }
      return false;
    }
  }

  Future<bool> _postStableStockDecrease(
    _ModuleRecord current,
    _ModuleRecord updated,
  ) async {
    final api = _catalogApi;
    final branchId = _branchId;
    if (api == null || branchId == null) return false;
    try {
      await api.setProductStock(
        productId: current.serverId,
        branchId: branchId,
        expectedQuantity: current.stockQuantity,
        targetQuantity: updated.stockQuantity,
        operationId: const Uuid().v4(),
        reason: 'تسوية جرد من شاشة الصنف ${current.title}',
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لم يتم حفظ تسوية المخزون: $error')),
        );
      }
      return false;
    }
  }

  String _channelForAccount(String code) {
    final upper = code.toUpperCase();
    if (upper.contains('WALLET')) return 'wallet';
    if (upper.contains('BANK')) return 'bank';
    return 'cash';
  }

  Future<void> _saveCatalogProduct(_ModuleRecord record) async {
    if (widget.module.key != 'products' && widget.module.key != 'purchases') {
      return;
    }
    await ProductCatalogStore(_tenantScope).save(
      CatalogProduct(
        id: record.serverId,
        name: record.title,
        purchasePrice: record.purchasePrice,
        salePrice: record.salePrice,
        barcode: record.barcode,
        stockQuantity: record.stockQuantity,
        unitName: record.unitName,
        version: record.version,
      ),
    );
  }

  Future<_ModuleRecord> _adoptCanonicalContact(
    _ModuleRecord record,
    CatalogContact contact,
  ) async {
    if (contact.id.isEmpty) return record;
    final linked = record.copyWith(
      serverId: contact.id,
      version: contact.version,
    );
    if (widget.module.key == 'customers') {
      await CustomerStore(
        _tenantScope,
      ).applyRemoteChange(contact.id, 'upsert', {
        'name': contact.name.isEmpty ? record.title : contact.name,
        'phone': contact.phone,
        'type': contact.type.isEmpty ? 'customer' : contact.type,
        'version': contact.version,
      });
    }
    final directIndex = _records.indexOf(record);
    final index = directIndex >= 0
        ? directIndex
        : _records.indexWhere(
            (candidate) =>
                (candidate.serverId.isEmpty ||
                    candidate.serverId.startsWith('local:')) &&
                candidate.title.trim().toLowerCase() ==
                    record.title.trim().toLowerCase(),
          );
    if (index >= 0 && mounted) {
      setState(() => _records[index] = linked);
      await _persistRecords();
    }
    return linked;
  }

  Future<_ModuleRecord> _syncCatalogRecord(_ModuleRecord record) async {
    final api = _catalogApi;
    if (api == null) return record;
    final entity = switch (widget.module.key) {
      'products' || 'purchases' => 'products',
      'customers' => 'customers',
      'suppliers' => 'suppliers',
      _ => '',
    };
    if (entity.isEmpty) return record;
    final outbox = CatalogOutbox(_tenantScope);
    final payload = <String, dynamic>{
      'name': record.title,
      'phone': record.details,
      'barcode': record.barcode,
      'sale_price': record.salePrice,
      'purchase_price': record.purchasePrice,
    };
    try {
      CatalogContact? canonicalContact;
      if (entity == 'products') {
        await api.saveProduct(
          name: record.title,
          barcode: record.barcode,
          salePrice: record.salePrice,
          purchasePrice: record.purchasePrice,
          unitName: record.unitName,
        );
      } else if (entity == 'customers') {
        canonicalContact = await api.saveCustomer(
          name: record.title,
          phone: record.details,
        );
      } else {
        canonicalContact = await api.saveSupplier(
          name: record.title,
          phone: record.details,
        );
      }
      await outbox.discard(entity, record.title);
      if (canonicalContact != null) {
        return _adoptCanonicalContact(record, canonicalContact);
      }
    } catch (error) {
      // Do not claim that an offline operation will sync unless persisted.
      try {
        await outbox.enqueue(
          entity,
          payload,
          restoreGenerationAtCreation:
              RealtimeSyncCoordinator.instance.restoreGeneration,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حُفظ محليًا وسيعاد الإرسال عند الاتصال: $error'),
            ),
          );
        }
      } catch (queueError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('لم يمكن جدولة المزامنة: $queueError')),
          );
        }
      }
    }
    return record;
  }

  Future<void> _deleteRecord(_ModuleRecord record) async {
    if (!_canDeleteRecord) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا السجل للعرض فقط أو لا تملك صلاحية حذفه.'),
        ),
      );
      return;
    }
    if (_isSettlementModule &&
        (record.serverId.isEmpty ||
            widget.token == null ||
            widget.token!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحديد السند المتزامن؛ حدّث السجل ثم أعد المحاولة.',
          ),
        ),
      );
      return;
    }
    if (widget.module.key == 'debts.receipts' &&
        record.serverId.isNotEmpty &&
        widget.token != null &&
        widget.token!.isNotEmpty) {
      try {
        await AccountingApi(
          token: widget.token!,
        ).voidReceipt(record.serverId, reason: 'حذف سند القبض من السجل');
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('تعذر حذف سند القبض: $error')));
        }
        return;
      }
    }
    if (widget.module.key == 'debts.payments' &&
        record.serverId.isNotEmpty &&
        widget.token != null &&
        widget.token!.isNotEmpty) {
      try {
        await AccountingApi(token: widget.token!).voidSupplierPayment(
          record.serverId,
          reason: 'حذف سند الصرف من السجل',
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('تعذر حذف سند الصرف: $error')));
        }
        return;
      }
    }
    if (_isSettlementModule) {
      await _loadRecords(remoteRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'تم حذف ${widget.module.entityLabel} وأثره المحاسبي.',
            ),
          ),
        );
      return;
    }
    final catalogApi = _catalogApi;
    if ((widget.module.key == 'products' ||
            widget.module.key == 'customers' ||
            widget.module.key == 'suppliers') &&
        catalogApi != null) {
      try {
        await catalogApi.remove(widget.module.key, name: record.title);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر حذف نسخة الخادم: $error')),
          );
        }
        return;
      }
    } else if (record.serverId.isNotEmpty &&
        _documentApi != null &&
        widget.module.key != 'debts.receipts' &&
        widget.module.key != 'debts.payments') {
      try {
        await _documentApi!.remove(record.serverId);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر حذف نسخة الخادم: $error')),
          );
        }
        return;
      }
    }
    final index = _records.indexOf(record);
    setState(() => _records.remove(record));
    await _persistRecords();
    if (widget.module.key == 'products') {
      await ProductCatalogStore(_tenantScope).remove(record.title);
    }
    if (widget.module.key == 'customers') {
      await CustomerStore(_tenantScope).remove(record.title);
    }
    if (!mounted) return;
    // A server-acknowledged DELETE cannot be undone by only restoring a
    // local cache row. That would create a misleading phantom record and
    // could later re-create a different contact/item on the server.
    final localOnly = record.serverId.isEmpty;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            localOnly
                ? 'تم حذف ${widget.module.entityLabel} محليًا.'
                : 'تم حذف ${widget.module.entityLabel} على الخادم. لا يتوفر تراجع لهذا الحذف.',
          ),
          action: localOnly
              ? SnackBarAction(
                  label: 'تراجع',
                  onPressed: () async {
                    if (!mounted) return;
                    setState(() => _records.insert(index, record));
                    await _persistRecords();
                    if (widget.module.key == 'products') {
                      await _saveCatalogProduct(record);
                    }
                    if (widget.module.key == 'customers') {
                      await CustomerStore(
                        _tenantScope,
                      ).save(record.title, record.details);
                    }
                    await _syncRecord(record);
                    await _syncCatalogRecord(record);
                  },
                )
              : null,
        ),
      );
  }

  Future<void> _printBarcode(_ModuleRecord record) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latinFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latinFont],
        ),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                record.title,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 18),
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: record.barcode,
                width: 280,
                height: 90,
                drawText: true,
              ),
              if (record.salePrice > 0) ...[
                pw.SizedBox(height: 12),
                pw.Text('Sale price: ${record.salePrice.toStringAsFixed(2)}'),
              ],
            ],
          ),
        ),
      ),
    );
    await PdfExportService.save(
      bytes: await document.save(),
      filename: 'barcode-${record.barcode}.pdf',
    );
  }

  Future<void> _syncRecord(_ModuleRecord record) async {
    if (_isSettlementModule ||
        !_isDocument ||
        _documentApi == null ||
        _branchId == null) {
      return;
    }
    if (record.serverId.isEmpty &&
        record.restoreGenerationAtCreation !=
            RealtimeSyncCoordinator.instance.restoreGeneration) {
      await QuarantinedOperationStore(_tenantScope).quarantine(
        operationId: record.clientOperationId,
        kind: 'business_document',
        reason: 'restore_generation_at_creation_mismatch',
        payload: record.toJson(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حُجز المستند للمراجعة لأنه أُنشئ قبل أحدث استعادة.'),
          ),
        );
      }
      return;
    }
    try {
      if (record.serverId.isNotEmpty) {
        final version = await _documentApi!.update(
          record.serverId,
          record.toServerJson(_branchId!, widget.module.key),
          expectedVersion: record.version,
          restoreGeneration: record.restoreGenerationAtCreation,
        );
        if (!mounted) return;
        final index = _records.indexOf(record);
        if (index >= 0) {
          setState(() => _records[index] = record.copyWith(version: version));
          await _persistRecords();
        }
        return;
      }
      final id = await _documentApi!.save(
        record.toServerJson(_branchId!, widget.module.key),
        restoreGeneration: record.restoreGenerationAtCreation,
      );
      if (!mounted || id.isEmpty || id == record.serverId) return;
      final index = _records.indexOf(record);
      if (index < 0) return;
      setState(() => _records[index] = record.copyWith(serverId: id));
      await _persistRecords();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حُفظ محليًا وتعذرت مزامنته الآن: $error')),
        );
      }
    }
  }

  Future<void> _printDocument(_ModuleRecord record) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latinFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final color = PdfColor.fromInt(widget.module.color.toARGB32());
    final profile = _profile;
    final logo = profile.logoBytes == null
        ? null
        : pw.MemoryImage(profile.logoBytes!);
    final document = pw.Document(
      title: '${widget.module.title} - ${record.title}',
      author: widget.tenantName,
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latinFont],
        ),
        margin: const pw.EdgeInsets.all(20),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 9),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: color, width: 2),
                ),
              ),
              child: pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (profile.phone.isNotEmpty)
                            pw.Text(
                              'هاتف: ${profile.phone}',
                              textDirection: pw.TextDirection.rtl,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          if (profile.email.isNotEmpty)
                            pw.Text(
                              'بريد: ${profile.email}',
                              textDirection: pw.TextDirection.rtl,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          if (profile.address.isNotEmpty)
                            pw.Text(
                              'العنوان: ${profile.address}',
                              textDirection: pw.TextDirection.rtl,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                        ],
                      ),
                    ),
                    pw.Container(
                      width: 82,
                      height: 48,
                      alignment: pw.Alignment.center,
                      child: logo == null
                          ? pw.Text(
                              '9',
                              style: pw.TextStyle(
                                color: color,
                                fontSize: 27,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            )
                          : pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
                    pw.Expanded(
                      child: pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              profile.businessName,
                              style: pw.TextStyle(
                                color: color,
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (profile.businessNameEn.isNotEmpty)
                              pw.Text(
                                profile.businessNameEn,
                                textDirection: pw.TextDirection.ltr,
                                style: pw.TextStyle(
                                  font: latinFont,
                                  fontSize: 8,
                                ),
                              ),
                            if (profile.tagline.isNotEmpty)
                              pw.Text(
                                profile.tagline,
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    widget.module.title,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    _dateLabel(record.updatedAt),
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _pdfField('البيان / الطرف', record.title, color),
                if (record.amount != 0)
                  _pdfField(
                    'المبلغ',
                    '${record.amount.toStringAsFixed(2)} ${record.currency}',
                    color,
                  ),
                if (record.dueAt != null)
                  _pdfField(
                    'تاريخ الاستحقاق',
                    _dateLabel(record.dueAt!),
                    color,
                  ),
                _pdfField('الحالة', record.statusLabel, color),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Text(
                  record.details.isEmpty
                      ? 'لا توجد ملاحظات إضافية.'
                      : record.details,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'توقيع المستلم: ____________________',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'توقيع المسؤول: ____________________',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await PdfExportService.save(
      bytes: await document.save(),
      filename:
          '${widget.module.key}-${record.updatedAt.millisecondsSinceEpoch}.pdf',
    );
  }

  Future<void> _printSimpleDocument(_ModuleRecord record) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latinFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final profile = _profile;
    final logo = profile.logoBytes == null
        ? null
        : pw.MemoryImage(profile.logoBytes!);
    final document = pw.Document(
      title: '${widget.module.title} - ${record.title}',
      author: profile.businessName,
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          150 * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.all(10),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latinFont],
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logo != null)
              pw.Center(
                child: pw.Image(
                  logo,
                  width: 42,
                  height: 42,
                  fit: pw.BoxFit.contain,
                ),
              ),
            pw.Text(
              profile.businessName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            if (profile.businessNameEn.isNotEmpty)
              pw.Text(
                profile.businessNameEn,
                textDirection: pw.TextDirection.ltr,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: latinFont, fontSize: 8),
              ),
            if (profile.phone.isNotEmpty)
              pw.Text(
                profile.phone,
                textDirection: pw.TextDirection.ltr,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: latinFont, fontSize: 7),
              ),
            if (profile.address.isNotEmpty)
              pw.Text(
                profile.address,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7),
              ),
            pw.Divider(thickness: .7),
            pw.Text(
              widget.module.title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 7),
            _simplePdfRow('البيان / الطرف', record.title, latinFont),
            _simplePdfRow('التاريخ', _dateLabel(record.updatedAt), latinFont),
            if (record.amount != 0)
              _simplePdfRow(
                'المبلغ',
                '${record.amount.toStringAsFixed(2)} ${record.currency}',
                latinFont,
              ),
            if (record.dueAt != null)
              _simplePdfRow('الاستحقاق', _dateLabel(record.dueAt!), latinFont),
            _simplePdfRow('الحالة', record.statusLabel, latinFont),
            pw.Divider(thickness: .4),
            pw.Text(
              record.details.isEmpty
                  ? 'لا توجد تفاصيل إضافية.'
                  : record.details,
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Spacer(),
            pw.Divider(thickness: .5),
            pw.Text(
              profile.footer.isEmpty ? 'شكراً لتعاملكم معنا' : profile.footer,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ),
    );
    await PdfExportService.print(
      bytes: await document.save(),
      filename:
          '${widget.module.key}-receipt-${record.updatedAt.millisecondsSinceEpoch}.pdf',
    );
  }

  pw.Widget _simplePdfRow(String label, String value, pw.Font latinFont) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Text('$label: ', style: const pw.TextStyle(fontSize: 7)),
            pw.Expanded(
              child: pw.Text(
                value,
                textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(value)
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
                textAlign: pw.TextAlign.left,
                style: pw.TextStyle(
                  font: RegExp(r'[\u0600-\u06FF]').hasMatch(value)
                      ? null
                      : latinFont,
                  fontSize: 7,
                ),
              ),
            ),
          ],
        ),
      );

  pw.Widget _pdfField(String label, String value, PdfColor color) =>
      pw.Container(
        width: 160,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 7, color: color)),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              maxLines: 2,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

  String _dateLabel(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  Future<void> _viewRecord(_ModuleRecord record) async {
    if (widget.module.key == 'customers' || widget.module.key == 'suppliers') {
      await _showContactStatement(record);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(widget.module.icon, color: widget.module.color),
            const SizedBox(width: 9),
            Expanded(child: Text(record.title)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (record.amount != 0)
                _detailRow(
                  'المبلغ',
                  '${record.amount.toStringAsFixed(2)} ${record.currency}',
                ),
              if (record.dueAt != null)
                _detailRow('الاستحقاق', _dateLabel(record.dueAt!)),
              _detailRow('الحالة', record.statusLabel),
              const Divider(),
              Text(record.details.isEmpty ? 'لا توجد تفاصيل.' : record.details),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printDocument(record);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('طباعة / PDF'),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(context);
              _printSimpleDocument(record);
            },
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('مستند مبسط'),
          ),
        ],
      ),
    );
  }

  Future<_ModuleRecord> _ensureContactServerRecord(_ModuleRecord record) async {
    if (record.serverId.isNotEmpty && !record.serverId.startsWith('local:')) {
      return record;
    }
    final api = _catalogApi;
    if (api == null) {
      throw StateError('يلزم الاتصال بالخادم لمزامنة بيانات الطرف.');
    }
    final entity = widget.module.key == 'suppliers' ? 'suppliers' : 'customers';
    var canonicalPhone = record.details;
    if (entity == 'customers') {
      final cached = await CustomerStore(_tenantScope).read();
      final matches = cached.where(
        (customer) =>
            (record.serverId.isNotEmpty && customer.id == record.serverId) ||
            customer.name.trim().toLowerCase() ==
                record.title.trim().toLowerCase(),
      );
      if (matches.isNotEmpty) canonicalPhone = matches.first.phone;
    }
    final remote = await api.list(entity);
    var canonical = selectCanonicalContact(
      remote,
      name: record.title,
      phone: canonicalPhone,
    );
    if (canonical == null) {
      if (!_hasPermission('contacts.write')) {
        throw StateError(
          'هذا الطرف غير موجود على الخادم، ولا تملك صلاحية مزامنته.',
        );
      }
      canonical = entity == 'customers'
          ? await api.saveCustomer(name: record.title, phone: canonicalPhone)
          : await api.saveSupplier(name: record.title, phone: canonicalPhone);
    }
    await CatalogOutbox(_tenantScope).discard(entity, record.title);
    return _adoptCanonicalContact(record, canonical);
  }

  Future<void> _showContactStatement(_ModuleRecord record) async {
    if (!_canViewContactStatement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا تملك صلاحية عرض كشف حساب هذا الطرف.')),
      );
      return;
    }
    final token = widget.token;
    final branchId = _branchId;
    if (token == null || token.isEmpty || branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يلزم الاتصال بالخادم لعرض كشف الحساب.')),
      );
      return;
    }
    final openingKey = [
      widget.module.key,
      record.serverId,
      record.clientOperationId,
      record.title.trim().toLowerCase(),
    ].join('|');
    if (!_contactStatementGuard.tryAcquire(openingKey)) return;
    try {
      var statementRecord = record;
      if (statementRecord.serverId.isEmpty ||
          statementRecord.serverId.startsWith('local:')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('جاري مزامنة بيانات الطرف وفتح كشف الحساب...'),
          ),
        );
        statementRecord = await _ensureContactServerRecord(statementRecord);
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AccountStatementPage(
            token: token,
            branchIds: [branchId],
            initialBranchId: branchId,
            initialContactId: statementRecord.serverId,
            initialContactRole: widget.module.key == 'suppliers'
                ? 'supplier'
                : 'customer',
            initialContactName: statementRecord.title,
            lockContact: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر جلب كشف الحساب: $error')));
    } finally {
      _contactStatementGuard.release(openingKey);
    }
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 105,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords;
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final categoryPairs = _records
        .map((record) => record.details.split(' • '))
        .where((parts) => parts.isNotEmpty && parts.first.isNotEmpty)
        .toList();
    final categories =
        categoryPairs.map((parts) => parts.first).toSet().toList()..sort();
    final subcategories =
        categoryPairs
            .where(
              (parts) =>
                  _categoryFilter.isEmpty || parts.first == _categoryFilter,
            )
            .where((parts) => parts.length > 1 && parts[1].isNotEmpty)
            .map((parts) => parts[1])
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.title),
        centerTitle: false,
        toolbarHeight: desktop ? 0 : null,
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'تصدير وطباعة',
              icon: const Icon(Icons.ios_share_rounded),
              onSelected: _exportList,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('حفظ PDF'),
                  ),
                ),
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print_outlined),
                    title: Text('طباعة'),
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('مشاركة التقرير'),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Icon(widget.module.icon, color: widget.module.color),
          ),
        ],
      ),
      floatingActionButton: _canAddRecord && !desktop
          ? FloatingActionButton.extended(
              key: ValueKey('add-${widget.module.key}'),
              onPressed: _addRecord,
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.module.actionLabel),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
            return RefreshIndicator(
              onRefresh: _loadRecords,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_accountingWarning != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_accountingWarning!),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      14,
                      horizontalPadding,
                      8,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NineSoftPageHeader(
                            title: widget.module.title,
                            subtitle:
                                'إدارة ${widget.module.entityLabel} والبحث والتصفية من شاشة واحدة',
                            icon: widget.module.icon,
                            color: widget.module.color,
                            actions: [
                              if (_canAddRecord)
                                FilledButton.icon(
                                  key: ValueKey(
                                    'header-add-${widget.module.key}',
                                  ),
                                  onPressed: _addRecord,
                                  icon: const Icon(Icons.add_rounded),
                                  label: Text(widget.module.actionLabel),
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'تصدير وطباعة',
                                onSelected: _exportList,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'pdf',
                                    child: Text('حفظ PDF'),
                                  ),
                                  PopupMenuItem(
                                    value: 'print',
                                    child: Text('طباعة'),
                                  ),
                                  PopupMenuItem(
                                    value: 'share',
                                    child: Text('مشاركة التقرير'),
                                  ),
                                ],
                                child: OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: const Text('تصدير'),
                                ),
                              ),
                            ],
                          ),
                          if (desktop) ...[
                            const SizedBox(height: 14),
                            NineSoftWorkspaceBanner(
                              title: 'مساحة ${widget.module.title}',
                              subtitle:
                                  'سجلات واضحة، إجراءات قريبة، وخطوة تالية سهلة.',
                              icon: widget.module.icon,
                              color: widget.module.color,
                              actionLabel: _canAddRecord
                                  ? widget.module.actionLabel
                                  : null,
                              onAction: _canAddRecord ? _addRecord : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SummaryPanel(
                        module: widget.module,
                        records: _records,
                      ),
                    ),
                  ),
                  if (_isReport)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        12,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _FinancialAnalysisPanel(
                          records: records,
                          color: widget.module.color,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_filterOptions.isNotEmpty) ...[
                            ChoiceChip(
                              label: const Text('الكل'),
                              selected: _statusFilter == 'all',
                              onSelected: (_) =>
                                  setState(() => _statusFilter = 'all'),
                            ),
                            for (final option in _filterOptions)
                              ChoiceChip(
                                label: Text(option.label),
                                selected: _statusFilter == option.value,
                                onSelected: (_) => setState(
                                  () => _statusFilter = option.value,
                                ),
                              ),
                          ],
                          if (_supportsDateFilter) ...[
                            OutlinedButton.icon(
                              onPressed: _pickDateRange,
                              icon: const Icon(
                                Icons.date_range_outlined,
                                size: 19,
                              ),
                              label: Text(
                                _dateRange == null
                                    ? 'الفترة الزمنية'
                                    : '${_dateLabel(_dateRange!.start)} - ${_dateLabel(_dateRange!.end)}',
                              ),
                            ),
                          ],
                          if (_supportsDateFilter && _dateRange != null)
                            IconButton(
                              tooltip: 'مسح الفترة',
                              onPressed: () =>
                                  setState(() => _dateRange = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      4,
                      horizontalPadding,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: TextField(
                        key: ValueKey('search-${widget.module.key}'),
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'ابحث في ${widget.module.title}',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.module.key == 'products' && categories.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        12,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('category-$_categoryFilter'),
                                initialValue: _categoryFilter,
                                decoration: const InputDecoration(
                                  labelText: 'القسم الرئيسي',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('كل الأقسام'),
                                  ),
                                  ...categories.map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  ),
                                ],
                                onChanged: (value) => setState(() {
                                  _categoryFilter = value ?? '';
                                  _subcategoryFilter = '';
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'subcategory-$_categoryFilter-$_subcategoryFilter',
                                ),
                                initialValue: _subcategoryFilter,
                                decoration: const InputDecoration(
                                  labelText: 'القسم الفرعي',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('كل الفروع'),
                                  ),
                                  ...subcategories.map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  ),
                                ],
                                onChanged: (value) => setState(
                                  () => _subcategoryFilter = value ?? '',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_recordsLoaded && records.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('جارٍ تحميل السجلات ومزامنتها...'),
                          ],
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        module: widget.module,
                        hasQuery: _query.trim().isNotEmpty,
                        onAdd: _canAddRecord ? _addRecord : null,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        100,
                      ),
                      sliver: desktop
                          ? SliverToBoxAdapter(
                              child: _RecordTable(
                                module: widget.module,
                                records: records,
                                canEdit: _canEditRecord,
                                canDelete: _canDeleteRecord,
                                canViewStatement: _canViewContactStatement,
                                isDocument:
                                    _isDocument ||
                                    _isSettlementModule ||
                                    _isDebt ||
                                    _isReport,
                                onView: _viewRecord,
                                onEdit: _editRecord,
                                onDelete: _deleteRecord,
                                onPrintDocument: _printDocument,
                              ),
                            )
                          : SliverList.separated(
                              itemCount: records.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final record = records[index];
                                return _RecordCard(
                                  module: widget.module,
                                  record: record,
                                  onEdit: _canEditRecord
                                      ? () => _editRecord(record)
                                      : null,
                                  onDelete: _canDeleteRecord
                                      ? () => _deleteRecord(record)
                                      : null,
                                  onPrintBarcode: () => _printBarcode(record),
                                  onView: () => _viewRecord(record),
                                  onPrintDocument: () => _printDocument(record),
                                  canViewStatement: _canViewContactStatement,
                                  isDocument:
                                      _isDocument ||
                                      _isSettlementModule ||
                                      _isDebt ||
                                      _isReport,
                                  isDebt: _isDebt,
                                );
                              },
                            ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FinancialAnalysisPanel extends StatelessWidget {
  const _FinancialAnalysisPanel({required this.records, required this.color});

  final List<_ModuleRecord> records;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final daily = <DateTime, double>{};
    for (final record in records) {
      final day = DateTime(
        record.updatedAt.year,
        record.updatedAt.month,
        record.updatedAt.day,
      );
      daily[day] = (daily[day] ?? 0) + record.amount;
    }
    final points = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final visible = points.length > 7
        ? points.sublist(points.length - 7)
        : points;
    final total = records.fold<double>(0, (sum, row) => sum + row.amount);
    final maxValue = visible.fold<double>(
      0,
      (value, item) => item.value.abs() > value ? item.value.abs() : value,
    );
    final average = records.isEmpty ? 0.0 : total / records.length;
    return NineSoftPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final metrics = [
            _AnalysisMetric(
              label: 'قيمة الفترة',
              value: '${total.toStringAsFixed(2)} YER',
              icon: Icons.account_balance_wallet_outlined,
              color: color,
            ),
            _AnalysisMetric(
              label: 'عدد الحركات',
              value: '${records.length}',
              icon: Icons.receipt_long_outlined,
              color: NizamiColors.blue,
            ),
            _AnalysisMetric(
              label: 'متوسط الحركة',
              value: '${average.toStringAsFixed(2)} YER',
              icon: Icons.analytics_outlined,
              color: NizamiColors.purple,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_rounded, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تحليل الفترة',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Chip(label: Text('آخر 7 أيام مسجلة')),
                ],
              ),
              const SizedBox(height: 12),
              if (compact)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final metric in metrics) ...[
                        SizedBox(width: 178, child: metric),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    for (var index = 0; index < metrics.length; index++) ...[
                      Expanded(child: metrics[index]),
                      if (index < metrics.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                const SizedBox(
                  height: 96,
                  child: Center(
                    child: Text('لا توجد حركات ضمن الفترة المختارة.'),
                  ),
                )
              else
                SizedBox(
                  height: 132,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final point in visible)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  point.value.toStringAsFixed(0),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    fontFamily: 'ArialMTBlack',
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  height: maxValue == 0
                                      ? 4
                                      : 72 * (point.value.abs() / maxValue),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        color,
                                        color.withValues(alpha: .45),
                                      ],
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(7),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${point.key.month}/${point.key.day}',
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    fontFamily: 'ArialMTBlack',
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AnalysisMetric extends StatelessWidget {
  const _AnalysisMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .075),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: .13),
          foregroundColor: color,
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: color,
                  fontFamily: 'ArialMTBlack',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.module, required this.records});

  final ModuleDefinition module;
  final List<_ModuleRecord> records;

  @override
  Widget build(BuildContext context) {
    final isDebt = module.key == 'debts.dues';
    final outstanding = records
        .where((record) => !record.settled)
        .fold<double>(0, (sum, record) => sum + record.amount);
    final overdue = records.where((record) => record.isOverdue).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryItem(
              icon: module.icon,
              color: module.color,
              label: 'إجمالي السجلات',
              value: '${records.length}',
            ),
            if (isDebt)
              _SummaryItem(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFE28B21),
                label: 'الرصيد غير المسدد',
                value: '${outstanding.toStringAsFixed(2)} YER',
              )
            else
              const _SummaryItem(
                icon: Icons.verified_rounded,
                color: Color(0xFF22B968),
                label: 'حالة القسم',
                value: 'سجلات محفوظة',
              ),
            _SummaryItem(
              icon: isDebt
                  ? Icons.notification_important_outlined
                  : Icons.cloud_done_rounded,
              color: isDebt && overdue > 0
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              label: isDebt ? 'متأخر بعد 48 ساعة' : 'وضع التشغيل',
              value: isDebt ? '$overdue' : 'حفظ ومزامنة',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 155, maxWidth: 285),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.module,
    required this.hasQuery,
    required this.onAdd,
  });

  final ModuleDefinition module;
  final bool hasQuery;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(module.icon, size: 58, color: module.color),
            const SizedBox(height: 14),
            Text(
              hasQuery ? 'لا توجد نتائج مطابقة' : 'لا توجد سجلات بعد',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'جرّب عبارة بحث أخرى.'
                  : onAdd == null
                  ? 'هذا القسم للعرض من السجلات المحاسبية المعتمدة.'
                  : 'ابدأ بإضافة ${module.entityLabel} جديد لهذا القسم.',
              textAlign: TextAlign.center,
            ),
            if (!hasQuery && onAdd != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(module.actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordTable extends StatelessWidget {
  const _RecordTable({
    required this.module,
    required this.records,
    required this.canEdit,
    required this.canDelete,
    required this.canViewStatement,
    required this.isDocument,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onPrintDocument,
  });

  final ModuleDefinition module;
  final List<_ModuleRecord> records;
  final bool canEdit;
  final bool canDelete;
  final bool canViewStatement;
  final bool isDocument;
  final ValueChanged<_ModuleRecord> onView;
  final ValueChanged<_ModuleRecord> onEdit;
  final ValueChanged<_ModuleRecord> onDelete;
  final ValueChanged<_ModuleRecord> onPrintDocument;

  @override
  Widget build(BuildContext context) => NineSoftResponsiveFinancialTable(
    columns: const [
      NineSoftFinancialColumn(label: 'الاسم / البيان', flex: 3),
      NineSoftFinancialColumn(label: 'التفاصيل', flex: 4),
      NineSoftFinancialColumn(label: 'المبلغ', flex: 2),
      NineSoftFinancialColumn(label: 'الحالة', flex: 2),
      NineSoftFinancialColumn(label: 'الإجراءات', flex: 3),
    ],
    rows: [for (final record in records) _row(record)],
    emptyDescription: 'لا توجد سجلات لعرضها.',
    emptyIcon: module.icon,
  );

  NineSoftFinancialRow _row(_ModuleRecord record) {
    final isContact = module.key == 'customers' || module.key == 'suppliers';
    final canOpen = !isContact || canViewStatement;
    final statusColor = record.isVoided
        ? const Color(0xFF6B7280)
        : record.settled
        ? const Color(0xFF08B66A)
        : record.isOverdue
        ? const Color(0xFFFF405D)
        : const Color(0xFFFF961F);
    return NineSoftFinancialRow(
      key: ValueKey('module-record-${record.clientOperationId}'),
      onTap: canOpen ? () => onView(record) : null,
      cells: [
        Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: module.color.withValues(alpha: .11),
              foregroundColor: module.color,
              child: Icon(module.icon, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        Text(
          record.details.isEmpty ? '—' : record.details,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            record.amount != 0
                ? '${record.amount.toStringAsFixed(2)} ${record.currency}'
                : '—',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'ArialMTBlack'),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(record.statusLabel),
          ),
        ),
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            IconButton(
              tooltip: isContact ? 'عرض كشف الحساب' : 'عرض',
              onPressed: canOpen ? () => onView(record) : null,
              icon: Icon(
                isContact
                    ? Icons.account_balance_wallet_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
            if (isDocument)
              IconButton(
                tooltip: 'طباعة / PDF',
                onPressed: () => onPrintDocument(record),
                icon: const Icon(Icons.print_outlined, size: 20),
              ),
            if (canEdit)
              IconButton(
                tooltip: 'تعديل',
                onPressed: () => onEdit(record),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'حذف',
                onPressed: () => onDelete(record),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.module,
    required this.record,
    required this.onEdit,
    required this.onDelete,
    required this.onPrintBarcode,
    required this.onView,
    required this.onPrintDocument,
    required this.canViewStatement,
    required this.isDocument,
    required this.isDebt,
  });

  final ModuleDefinition module;
  final _ModuleRecord record;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onPrintBarcode;
  final VoidCallback onView;
  final VoidCallback onPrintDocument;
  final bool canViewStatement;
  final bool isDocument;
  final bool isDebt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: module.color.withValues(alpha: .12),
              foregroundColor: module.color,
              child: Icon(module.icon),
            ),
            title: Text(
              record.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              [
                    if (record.details.isNotEmpty) record.details,
                    if (record.purchasePrice > 0)
                      'سعر الشراء: ${record.purchasePrice.toStringAsFixed(2)}',
                    if (record.salePrice > 0)
                      'سعر البيع: ${record.salePrice.toStringAsFixed(2)}',
                    if (record.barcode.isNotEmpty)
                      'باركود الصنف: ${record.barcode}',
                    if (record.amount != 0)
                      'المبلغ: ${record.amount.toStringAsFixed(2)} ${record.currency}',
                    if (record.dueAt != null)
                      'الاستحقاق: ${record.dueAt!.year}/${record.dueAt!.month.toString().padLeft(2, '0')}/${record.dueAt!.day.toString().padLeft(2, '0')}',
                    if (record.settled) 'الحالة: مسدد / مكتمل',
                    if (record.isVoided) 'الحالة: ملغي بقيد عكسي',
                    if (record.isOverdue) 'تنبيه: متأخر أكثر من 48 ساعة',
                  ].isEmpty
                  ? 'أضيف الآن'
                  : [
                      if (record.details.isNotEmpty) record.details,
                      if (record.purchasePrice > 0)
                        'سعر الشراء: ${record.purchasePrice.toStringAsFixed(2)}',
                      if (record.salePrice > 0)
                        'سعر البيع: ${record.salePrice.toStringAsFixed(2)}',
                      if (record.barcode.isNotEmpty)
                        'باركود الصنف: ${record.barcode}',
                      if (record.amount != 0)
                        'المبلغ: ${record.amount.toStringAsFixed(2)} ${record.currency}',
                      if (record.dueAt != null)
                        'الاستحقاق: ${record.dueAt!.year}/${record.dueAt!.month.toString().padLeft(2, '0')}/${record.dueAt!.day.toString().padLeft(2, '0')}',
                      if (record.settled) 'الحالة: مسدد / مكتمل',
                      if (record.isVoided) 'الحالة: ملغي بقيد عكسي',
                      if (record.isOverdue) 'تنبيه: متأخر أكثر من 48 ساعة',
                    ].join('\n'),
            ),
            isThreeLine:
                record.details.isNotEmpty ||
                record.purchasePrice > 0 ||
                record.salePrice > 0 ||
                record.barcode.isNotEmpty,
            onTap:
                (module.key == 'customers' || module.key == 'suppliers') &&
                    !canViewStatement
                ? null
                : onView,
            trailing: PopupMenuButton<String>(
              tooltip: 'إجراءات',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    onView();
                  case 'barcode':
                    onPrintBarcode();
                  case 'print':
                    onPrintDocument();
                  case 'edit':
                    onEdit?.call();
                  case 'delete':
                    onDelete?.call();
                }
              },
              itemBuilder: (_) => [
                if (!((module.key == 'customers' ||
                        module.key == 'suppliers') &&
                    !canViewStatement))
                  PopupMenuItem(
                    value: 'view',
                    child: ListTile(
                      leading: Icon(
                        module.key == 'customers' || module.key == 'suppliers'
                            ? Icons.account_balance_wallet_outlined
                            : Icons.visibility_outlined,
                      ),
                      title: Text(
                        module.key == 'customers' || module.key == 'suppliers'
                            ? 'عرض كشف الحساب'
                            : 'عرض التفاصيل',
                      ),
                    ),
                  ),
                if (record.barcode.isNotEmpty)
                  const PopupMenuItem(
                    value: 'barcode',
                    child: ListTile(
                      leading: Icon(Icons.qr_code_2_rounded),
                      title: Text('طباعة الباركود'),
                    ),
                  ),
                if (isDocument)
                  const PopupMenuItem(
                    value: 'print',
                    child: ListTile(
                      leading: Icon(Icons.print_outlined),
                      title: Text('طباعة / PDF'),
                    ),
                  ),
                if (onEdit != null)
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                    ),
                  ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: Text(isDebt ? 'إلغاء عبر سند قبض' : 'حذف'),
                    ),
                  ),
              ],
            ),
          ),
          if ((module.key == 'customers' || module.key == 'suppliers') &&
              canViewStatement)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(
                    module.key == 'customers'
                        ? 'عرض كشف حساب العميل'
                        : 'عرض كشف حساب المورد',
                  ),
                ),
              ),
            ),
          if (record.barcode.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(72, 0, 18, 14),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: record.barcode,
                height: 54,
                drawText: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _StableStockSupplyRequest {
  const _StableStockSupplyRequest({
    required this.paymentMode,
    required this.supplierName,
    required this.supplierPhone,
    required this.operationId,
  });

  final String paymentMode;
  final String supplierName;
  final String supplierPhone;
  final String operationId;
}

class _StableStockSupplyDialog extends StatefulWidget {
  const _StableStockSupplyDialog({
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.suppliers,
  });

  final String productName;
  final double quantity;
  final double unitCost;
  final List<Map<String, dynamic>> suppliers;

  @override
  State<_StableStockSupplyDialog> createState() =>
      _StableStockSupplyDialogState();
}

class _StableStockSupplyDialogState extends State<_StableStockSupplyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supplier = TextEditingController();
  final _phone = TextEditingController();
  String _paymentMode = 'cash';

  @override
  void dispose() {
    _supplier.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('توريد مخزون المحل'),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(widget.productName),
              subtitle: Text(
                'الزيادة ${widget.quantity.toStringAsFixed(3)} × ${widget.unitCost.toStringAsFixed(2)} YER',
              ),
            ),
            const Text(
              'سيُنشأ مستند شراء وقيد محاسبي متوازن، وليس تغيير رقم فقط.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('stable-stock-payment-mode'),
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'طريقة التوريد'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('مدفوع')),
                DropdownMenuItem(
                  value: 'credit',
                  child: Text('آجل على المورد'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _paymentMode = value ?? 'cash'),
            ),
            const SizedBox(height: 12),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (item) => item['name']?.toString() ?? '',
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                return widget.suppliers.where(
                  (item) => (item['name']?.toString().toLowerCase() ?? '')
                      .contains(query),
                );
              },
              onSelected: (item) {
                _supplier.text = item['name']?.toString() ?? '';
                _phone.text = item['phone']?.toString() ?? '';
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                controller.addListener(() => _supplier.text = controller.text);
                return TextFormField(
                  key: const ValueKey('stable-stock-supplier'),
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد (مطلوب)',
                    helperText:
                        'اختر المورد المسجل أو اكتب اسمه ليظهر في كشف المورد.',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'اختر أو اكتب اسم المورد، سواء كان التوريد مدفوعًا أو آجلًا.'
                      : null,
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'هاتف المورد (اختياري)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        key: const ValueKey('stable-post-stock-supply'),
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _StableStockSupplyRequest(
              paymentMode: _paymentMode,
              supplierName: _supplier.text.trim(),
              supplierPhone: _phone.text.trim(),
              operationId: const Uuid().v4(),
            ),
          );
        },
        child: const Text('ترحيل التوريد'),
      ),
    ],
  );
}

class _AddRecordDialog extends StatefulWidget {
  const _AddRecordDialog({required this.module, this.initial});

  final ModuleDefinition module;
  final _ModuleRecord? initial;

  @override
  State<_AddRecordDialog> createState() => _AddRecordDialogState();
}

class _AddRecordDialogState extends State<_AddRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _purchaseController = TextEditingController();
  final _saleController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _amountController = TextEditingController();
  final _stockController = TextEditingController();
  String _unitName = 'حبة';
  DateTime? _dueAt;
  bool _settled = false;
  String _currency = 'YER';

  bool get _isProduct =>
      widget.module.key == 'products' || widget.module.key == 'purchases';
  bool get _isDebt => widget.module.key == 'debts.dues';
  bool get _isCustomer => widget.module.key == 'customers';
  bool get _isSupplier => widget.module.key == 'suppliers';
  bool get _isContact => _isCustomer || _isSupplier;
  bool get _isBusinessDocument =>
      widget.module.key.contains('.') && !_isProduct && !_isDebt;
  bool get _acceptsAmount =>
      widget.module.key.contains('.') &&
      !widget.module.key.endsWith('.warehouses');

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initial?.title ?? '';
    _detailsController.text = widget.initial?.details ?? '';
    _purchaseController.text = (widget.initial?.purchasePrice ?? 0) == 0
        ? ''
        : widget.initial!.purchasePrice.toString();
    _saleController.text = (widget.initial?.salePrice ?? 0) == 0
        ? ''
        : widget.initial!.salePrice.toString();
    _barcodeController.text = widget.initial?.barcode ?? '';
    _amountController.text = (widget.initial?.amount ?? 0) == 0
        ? ''
        : widget.initial!.amount.toString();
    _stockController.text = (widget.initial?.stockQuantity ?? 0).toString();
    _unitName = widget.initial?.unitName.isNotEmpty == true
        ? widget.initial!.unitName
        : 'حبة';
    _dueAt =
        widget.initial?.dueAt ??
        (_isDebt ? DateTime.now().add(const Duration(hours: 48)) : null);
    _settled = widget.initial?.settled ?? false;
    _currency = widget.initial?.currency ?? 'YER';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _purchaseController.dispose();
    _saleController.dispose();
    _barcodeController.dispose();
    _amountController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _ModuleRecord(
        title: _titleController.text.trim(),
        details: _detailsController.text.trim(),
        purchasePrice: double.tryParse(_purchaseController.text) ?? 0,
        salePrice: double.tryParse(_saleController.text) ?? 0,
        barcode: _barcodeController.text.trim(),
        stockQuantity: double.tryParse(_stockController.text) ?? 0,
        unitName: _unitName,
        amount: double.tryParse(_amountController.text) ?? 0,
        currency: _currency,
        dueAt: _dueAt,
        settled: _settled,
        serverId: widget.initial?.serverId ?? '',
        clientOperationId:
            widget.initial?.clientOperationId ?? const Uuid().v4(),
        version: widget.initial?.version ?? 1,
        restoreGenerationAtCreation:
            widget.initial?.restoreGenerationAtCreation ??
            RealtimeSyncCoordinator.instance.restoreGeneration,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      scrollable: false,
      insetPadding: mobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: mobile
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: widget.module.color.withValues(alpha: .12),
            foregroundColor: widget.module.color,
            child: Icon(widget.module.icon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.initial == null
                  ? '${widget.module.actionLabel} جديد'
                  : 'تحرير ${widget.module.entityLabel}',
            ),
          ),
          if (mobile)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      content: SizedBox(
        width: mobile ? double.maxFinite : 420,
        height: (MediaQuery.sizeOf(context).height * (mobile ? .72 : .68))
            .clamp(360.0, 680.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NineSoftEntryHeading(
                  title: widget.initial == null
                      ? 'إضافة ${widget.module.entityLabel}'
                      : 'تعديل ${widget.module.entityLabel}',
                  subtitle: 'حقول منظمة لإدخال البيانات ومراجعتها قبل الحفظ',
                  icon: widget.module.icon,
                  status: 'إدخال جديد',
                  accent: widget.module.color,
                ),
                const SizedBox(height: 15),
                if (_isBusinessDocument) ...[
                  Card(
                    color: widget.module.color.withValues(alpha: .08),
                    child: ListTile(
                      leading: Icon(
                        widget.module.icon,
                        color: widget.module.color,
                      ),
                      title: Text(widget.module.entityLabel),
                      subtitle: const Text(
                        'يُحفظ محليًا فورًا ثم يتزامن مع الخادم عند توفر الإنترنت.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                NineSoftEntrySection(
                  title: _isContact ? 'بيانات التواصل' : 'المعلومات الرئيسية',
                  subtitle: _isContact
                      ? 'اسم الطرف ورقم هاتفه'
                      : 'الاسم والبيان أو الوصف',
                  icon: _isContact
                      ? Icons.people_outline_rounded
                      : widget.module.icon,
                  step: '01',
                  accent: widget.module.color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('record-title'),
                        controller: _titleController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: _isBusinessDocument
                              ? (widget.module.key.contains('receipt')
                                    ? 'استلمنا من'
                                    : 'اسم الطرف')
                              : 'اسم ${widget.module.entityLabel}',
                          prefixIcon: Icon(
                            _isBusinessDocument
                                ? Icons.person_outline_rounded
                                : widget.module.icon,
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'اكتب الاسم أولًا.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('record-details'),
                        controller: _detailsController,
                        keyboardType: _isContact
                            ? TextInputType.phone
                            : TextInputType.multiline,
                        inputFormatters: _isContact
                            ? const [latinDigitFormatter]
                            : const [],
                        decoration: InputDecoration(
                          labelText: _isContact
                              ? (_isSupplier
                                    ? 'رقم هاتف المورد'
                                    : 'رقم هاتف العميل')
                              : 'البيان والملاحظات',
                          prefixIcon: Icon(
                            _isContact
                                ? Icons.phone_outlined
                                : Icons.notes_outlined,
                          ),
                        ),
                        minLines: _isContact ? 1 : 2,
                        maxLines: _isContact ? 1 : 4,
                        validator: _isContact
                            ? (value) {
                                final phone = value?.trim() ?? '';
                                if (phone.isEmpty) {
                                  return _isSupplier
                                      ? 'اكتب رقم هاتف المورد.'
                                      : 'اكتب رقم هاتف العميل.';
                                }
                                if (phone
                                        .replaceAll(RegExp(r'[^0-9]'), '')
                                        .length <
                                    6) {
                                  return 'رقم الهاتف غير مكتمل.';
                                }
                                return null;
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_isProduct) ...[
                  NineSoftEntrySection(
                    title: 'التسعير والباركود والمخزون',
                    subtitle:
                        'أسعار الصنف ووحدته ورصيده مع إمكانية مسح الباركود',
                    icon: Icons.inventory_2_outlined,
                    step: '02',
                    accent: NizamiColors.amber,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isProduct) ...[
                          const SizedBox(height: 12),
                          NineSoftEntryFieldGrid(
                            minFieldWidth: 145,
                            maxColumns: 2,
                            children: [
                              TextFormField(
                                controller: _purchaseController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: const [latinDigitFormatter],
                                textDirection: TextDirection.ltr,
                                decoration: const InputDecoration(
                                  labelText: 'سعر الشراء',
                                ),
                              ),
                              TextFormField(
                                controller: _saleController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: const [latinDigitFormatter],
                                textDirection: TextDirection.ltr,
                                decoration: const InputDecoration(
                                  labelText: 'سعر البيع الثابت',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'باركود الصنف',
                              prefixIcon: Icon(Icons.qr_code_2_rounded),
                            ),
                          ),
                          if (widget.module.key == 'products') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: const ValueKey('stable-product-unit'),
                              initialValue:
                                  const [
                                    'حبة',
                                    'كجم',
                                    'جرام',
                                    'لتر',
                                    'متر',
                                  ].contains(_unitName)
                                  ? _unitName
                                  : 'حبة',
                              decoration: const InputDecoration(
                                labelText: 'وحدة المخزون الأساسية',
                              ),
                              items: const ['حبة', 'كجم', 'جرام', 'لتر', 'متر']
                                  .map(
                                    (unit) => DropdownMenuItem(
                                      value: unit,
                                      child: Text(unit),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _unitName = value ?? 'حبة'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const ValueKey('stable-product-stock'),
                              controller: _stockController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [latinDigitFormatter],
                              decoration: const InputDecoration(
                                labelText: 'الكمية الحالية في مخزون المحل',
                                helperText: 'عند الزيادة ستحدد: مدفوع أو آجل.',
                                prefixIcon: Icon(Icons.inventory_2_outlined),
                              ),
                              validator: (value) {
                                final number = double.tryParse(
                                  value?.trim() ?? '',
                                );
                                if (number == null || number < 0) {
                                  return 'أدخل كمية صحيحة غير سالبة.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                        if (_isProduct) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final code = await Navigator.of(context)
                                    .push<String>(
                                      MaterialPageRoute(
                                        builder: (_) => const WaslQrScannerPage(
                                          title: 'مسح باركود الصنف',
                                          instruction:
                                              'وجّه الكاميرا إلى باركود الصنف لإدخاله تلقائيًا.',
                                        ),
                                      ),
                                    );
                                if (code != null && mounted) {
                                  _barcodeController.text = code;
                                }
                              },
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('مسح بالكاميرا'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_acceptsAmount) ...[
                  NineSoftEntrySection(
                    title: 'بيانات المبلغ',
                    subtitle: 'المبلغ والعملة وتاريخ المستند',
                    icon: Icons.payments_outlined,
                    step: '02',
                    accent: NizamiColors.green,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_acceptsAmount) ...[
                          const SizedBox(height: 12),
                          if (_isBusinessDocument)
                            Row(
                              children: [
                                Expanded(
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'التاريخ',
                                      prefixIcon: Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                    ),
                                    child: Text(
                                      '${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _currency,
                                    isExpanded: true,
                                    selectedItemBuilder: (context) => const [
                                      Text(
                                        'YER',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'SAR',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'USD',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'العملة',
                                      prefixIcon: Icon(
                                        Icons.currency_exchange_rounded,
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'YER',
                                        child: Text('الريال اليمني (YER)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'SAR',
                                        child: Text('الريال السعودي (SAR)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'USD',
                                        child: Text('الدولار الأمريكي (USD)'),
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                      () => _currency = value ?? 'YER',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_isBusinessDocument) const SizedBox(height: 12),
                          TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [latinDigitFormatter],
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontFamily: 'ArialMTBlack'),
                            decoration: InputDecoration(
                              labelText: 'المبلغ',
                              prefixIcon: const Icon(Icons.payments_outlined),
                              suffixText: _currency,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isDebt) ...[
                  NineSoftEntrySection(
                    title: 'الاستحقاق والتذكير',
                    icon: Icons.event_outlined,
                    step: '03',
                    accent: NizamiColors.purple,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isDebt) ...[
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined),
                            title: const Text('موعد التذكير والاستحقاق'),
                            subtitle: Text(
                              _dueAt == null
                                  ? 'بعد 48 ساعة تلقائيًا'
                                  : '${_dueAt!.year}/${_dueAt!.month.toString().padLeft(2, '0')}/${_dueAt!.day.toString().padLeft(2, '0')} - ${_dueAt!.hour.toString().padLeft(2, '0')}:${_dueAt!.minute.toString().padLeft(2, '0')}',
                            ),
                            trailing: const Icon(Icons.edit_calendar_outlined),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate:
                                    _dueAt ??
                                    DateTime.now().add(const Duration(days: 2)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 3650),
                                ),
                              );
                              if (date != null && mounted) {
                                setState(
                                  () => _dueAt = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    9,
                                  ),
                                );
                              }
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _settled,
                            onChanged: (value) =>
                                setState(() => _settled = value),
                            title: const Text('تم سداد الدين'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('save-record'),
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

pw.Widget _pdfLatin(String value, pw.Font font, {bool bold = false}) =>
    pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: 7,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

pw.Widget _pdfMixed(String value, pw.Font arabic, pw.Font latin) {
  final parts = value.split(
    RegExp(
      r'(?<=[A-Za-z0-9@._+:/-])(?=[^A-Za-z0-9@._+:/-])|(?<=[^A-Za-z0-9@._+:/-])(?=[A-Za-z0-9@._+:/-])',
    ),
  );
  return pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.RichText(
      textAlign: pw.TextAlign.right,
      text: pw.TextSpan(
        children: [
          for (final part in parts)
            pw.TextSpan(
              text: part,
              style: pw.TextStyle(
                font: RegExp(r'[A-Za-z0-9]').hasMatch(part) ? latin : arabic,
                fontSize: 7,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ModuleFilterOption {
  const _ModuleFilterOption(this.value, this.label);

  final String value;
  final String label;
}

class _ModuleRecord {
  const _ModuleRecord({
    required this.title,
    required this.details,
    required this.updatedAt,
    this.purchasePrice = 0,
    this.salePrice = 0,
    this.barcode = '',
    this.stockQuantity = 0,
    this.unitName = 'حبة',
    this.amount = 0,
    this.currency = 'YER',
    this.dueAt,
    this.settled = false,
    this.status = '',
    this.serverId = '',
    this.version = 1,
    this.clientOperationId = '',
    this.restoreGenerationAtCreation = 0,
  });

  final String title;
  final String details;
  final DateTime updatedAt;
  final double purchasePrice;
  final double salePrice;
  final String barcode;
  final double stockQuantity;
  final String unitName;
  final double amount;
  final String currency;
  final DateTime? dueAt;
  final bool settled;
  final String status;
  final String serverId;
  final int version;
  final String clientOperationId;
  final int restoreGenerationAtCreation;
  bool get isVoided => status == 'voided';
  bool get isOverdue =>
      !settled && !isVoided && dueAt != null && DateTime.now().isAfter(dueAt!);
  String get statusLabel => isVoided
      ? 'ملغي بقيد عكسي'
      : settled
      ? 'مسدد / مكتمل'
      : isOverdue
      ? 'متأخر أكثر من 48 ساعة'
      : 'مفتوح';

  factory _ModuleRecord.fromJson(Map<String, dynamic> json) => _ModuleRecord(
    title: json['title']?.toString() ?? '',
    details: json['details']?.toString() ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
    purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0,
    salePrice: (json['salePrice'] as num?)?.toDouble() ?? 0,
    barcode: json['barcode']?.toString() ?? '',
    stockQuantity: (json['stockQuantity'] as num?)?.toDouble() ?? 0,
    unitName: json['unitName']?.toString() ?? 'حبة',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    currency: json['currency']?.toString() ?? 'YER',
    dueAt: DateTime.tryParse(json['dueAt']?.toString() ?? ''),
    settled: json['settled'] == true,
    status: json['status']?.toString() ?? '',
    serverId: json['serverId']?.toString() ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
    clientOperationId:
        (json['clientOperationId']?.toString().isNotEmpty ?? false)
        ? json['clientOperationId'].toString()
        : const Uuid().v4(),
    restoreGenerationAtCreation:
        (json['restoreGenerationAtCreation'] as num?)?.toInt() ?? 0,
  );

  factory _ModuleRecord.fromServerJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = const {};
    final rawPayload = json['payload'];
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String && rawPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return _ModuleRecord(
      serverId: json['id']?.toString() ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      clientOperationId:
          json['client_operation_id']?.toString() ??
          json['id']?.toString() ??
          '',
      title: json['title']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(json['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      amount: ((json['amount_minor'] as num?)?.toDouble() ?? 0) / 100,
      currency:
          json['currency']?.toString() ??
          payload['currency']?.toString() ??
          'YER',
      dueAt: DateTime.tryParse(json['due_at']?.toString() ?? ''),
      settled: json['settled'] == true || json['settled'] == 1,
      status: json['status']?.toString() ?? '',
      purchasePrice: (payload['purchasePrice'] as num?)?.toDouble() ?? 0,
      salePrice: (payload['salePrice'] as num?)?.toDouble() ?? 0,
      barcode: payload['barcode']?.toString() ?? '',
      stockQuantity: (payload['stockQuantity'] as num?)?.toDouble() ?? 0,
      unitName: payload['unitName']?.toString() ?? 'حبة',
      restoreGenerationAtCreation:
          (json['restore_generation'] as num?)?.toInt() ?? 0,
    );
  }

  factory _ModuleRecord.fromSettlementJson(
    Map<String, dynamic> json,
    bool isReceipt,
  ) {
    final projection = projectSettlementRecord(json, isReceipt: isReceipt);
    return _ModuleRecord(
      title: projection['title']! as String,
      details: projection['details']! as String,
      updatedAt: projection['updatedAt']! as DateTime,
      amount: projection['amount']! as double,
      currency: projection['currency']! as String,
      settled: projection['settled']! as bool,
      status: projection['status']! as String,
      serverId: projection['serverId']! as String,
      clientOperationId: projection['clientOperationId']! as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'details': details,
    'updatedAt': updatedAt.toIso8601String(),
    'purchasePrice': purchasePrice,
    'salePrice': salePrice,
    'barcode': barcode,
    'stockQuantity': stockQuantity,
    'unitName': unitName,
    'amount': amount,
    'currency': currency,
    'dueAt': dueAt?.toIso8601String(),
    'settled': settled,
    'status': status,
    'serverId': serverId,
    'version': version,
    'clientOperationId': clientOperationId,
    'restoreGenerationAtCreation': restoreGenerationAtCreation,
  };

  Map<String, Object?> toServerJson(String branchId, String moduleKey) => {
    'id': serverId.isNotEmpty ? serverId : clientOperationId,
    'client_operation_id': clientOperationId,
    'branch_id': branchId,
    'module_key': moduleKey,
    'title': title,
    'details': details,
    'amount_minor': (amount * 100).round(),
    'due_at': dueAt?.toUtc().toIso8601String(),
    'settled': settled,
    'occurred_at': updatedAt.toUtc().toIso8601String(),
    'payload': {
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'barcode': barcode,
      'stockQuantity': stockQuantity,
      'unitName': unitName,
      'currency': currency,
    },
  };

  _ModuleRecord copyWith({
    String? details,
    String? barcode,
    double? amount,
    bool? settled,
    String? status,
    String? serverId,
    int? version,
    String? clientOperationId,
    int? restoreGenerationAtCreation,
    double? stockQuantity,
    String? unitName,
  }) => _ModuleRecord(
    title: title,
    details: details ?? this.details,
    updatedAt: updatedAt,
    purchasePrice: purchasePrice,
    salePrice: salePrice,
    barcode: barcode ?? this.barcode,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    unitName: unitName ?? this.unitName,
    amount: amount ?? this.amount,
    currency: currency,
    dueAt: dueAt,
    settled: settled ?? this.settled,
    status: status ?? this.status,
    serverId: serverId ?? this.serverId,
    version: version ?? this.version,
    clientOperationId: clientOperationId ?? this.clientOperationId,
    restoreGenerationAtCreation:
        restoreGenerationAtCreation ?? this.restoreGenerationAtCreation,
  );
}
