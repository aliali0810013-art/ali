import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/pdf/pdf_export_service.dart';
import '../../settings/business_identity_store.dart';
import '../accounting/accounting_api.dart';
import '../accounting/chart_accounts_api.dart';
import '../accounting/searchable_chart_account_field.dart';
import '../accounting/settlement_idempotency_store.dart';
import '../modules/catalog_sync_api.dart';
import '../sync/realtime_sync_coordinator.dart';
import '../sync/purchase_outbox.dart';
import '../products/product_catalog_store.dart';
import 'purchase_reference_cache.dart';
import 'purchase_invoice_store.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';

String purchaseQueueSubtitle({
  required bool offline,
  required int queued,
  required int needsReview,
}) {
  final parts = <String>[];
  if (queued > 0) parts.add('$queued طلب بانتظار إرسال الخادم');
  if (needsReview > 0) parts.add('$needsReview طلب تحتاج إلى مراجعة');
  if (offline) {
    return parts.isEmpty
        ? 'وضع دون اتصال: سجل محفوظ محليًا'
        : 'وضع دون اتصال: سجل محفوظ محليًا • ${parts.join(' • ')}';
  }
  return parts.isEmpty
      ? 'إدارة فواتير الشراء والموردين والمدفوعات'
      : parts.join(' • ');
}

String purchaseCurrentOperationMessage({
  required PurchaseOutboxState? state,
  required bool sent,
  required bool quarantined,
  required bool permitted,
}) {
  if (sent) {
    return 'تم ترحيل الشراء وربطه بالمورد والمخزون والقيود.';
  }
  if (state == PurchaseOutboxState.needsReview) {
    return 'لم تُرحّل فاتورة الشراء؛ تحتاج إلى مراجعة قبل إعادة الإرسال.';
  }
  if (quarantined) {
    return 'نُقلت عملية الشراء إلى سجل المراجعة بسبب تعارض الاستعادة، ولن يعاد إرسالها تلقائيًا.';
  }
  if (!permitted) {
    return 'تغيّرت الجلسة أو الصلاحيات؛ لم تُرسل العملية من هذه الجلسة.';
  }
  if (state == PurchaseOutboxState.queued) {
    return 'تم حفظ طلب الشراء محليًا. سيعاد إرساله تلقائيًا عند الاتصال دون تكرار.';
  }
  return 'تعذر تأكيد حالة فاتورة الشراء الحالية؛ حدّث السجل قبل إعادة المحاولة.';
}

class PurchaseWorkspacePage extends StatefulWidget {
  const PurchaseWorkspacePage({
    required this.token,
    required this.branchIds,
    required this.tenantName,
    this.tenantId,
    required this.roleCode,
    required this.permissions,
    super.key,
  });

  final String token;
  final List<String> branchIds;
  final String tenantName;
  final String? tenantId;
  final String roleCode;
  final List<String> permissions;

  @override
  State<PurchaseWorkspacePage> createState() => _PurchaseWorkspacePageState();
}

class _PurchaseWorkspacePageState extends State<PurchaseWorkspacePage> {
  late AccountingApi _accounting;
  late CatalogSyncApi _catalog;
  late ChartAccountsApi _chart;
  List<Map<String, dynamic>> _invoices = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _products = const [];
  List<ChartAccount> _paymentAccounts = const [];
  bool _loading = true;
  bool _saving = false;
  bool _offlineSnapshot = false;
  int _loadSequence = 0;
  int _queuedCount = 0;
  int _needsReviewCount = 0;
  String? _error;
  StreamSubscription<Set<String>>? _syncSubscription;
  late final PurchaseInvoiceStore _purchaseStore = PurchaseInvoiceStore();
  Completer<_PurchaseDraft?>? _purchaseEditorResult;
  Map<String, dynamic>? _purchaseEditorInitialInvoice;

  String? get _branchId =>
      widget.branchIds.isEmpty ? null : widget.branchIds.first;
  bool get _canCreate => canSendPurchaseOutbox(
    roleCode: widget.roleCode,
    permissions: widget.permissions,
  );
  bool get _canDelete =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.delete');
  bool get _canEdit =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.update');
  BranchBusinessProfile get _profile =>
      BusinessIdentityStore.instance.profileFor(
        _branchId ?? 'MAIN',
        widget.tenantId ?? widget.tenantName,
        displayName: widget.tenantName,
      );

  @override
  void initState() {
    super.initState();
    _bindApis();
    _load();
    unawaited(_refreshPending());
    _syncSubscription = RealtimeSyncCoordinator.instance.changes.listen((
      types,
    ) {
      if (types.contains('purchase_invoice') ||
          types.contains('snapshot_restore')) {
        unawaited(_load());
        unawaited(_refreshPending());
      }
    });
  }

  @override
  void didUpdateWidget(covariant PurchaseWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) _bindApis();
  }

  void _bindApis() {
    _accounting = AccountingApi(token: widget.token);
    _catalog = CatalogSyncApi(token: widget.token);
    _chart = ChartAccountsApi(widget.token);
  }

  PurchaseDeliverySession _captureDeliverySession(String branchId) =>
      PurchaseDeliverySession(
        tenantId: widget.tenantId ?? widget.tenantName,
        token: widget.token,
        branchId: branchId,
        roleCode: widget.roleCode,
        permissions: List<String>.unmodifiable(widget.permissions),
      );

  bool _isDeliverySessionCurrent(PurchaseDeliverySession captured) =>
      mounted &&
      captured.matches(
        tenantId: widget.tenantId ?? widget.tenantName,
        token: widget.token,
        branchId: _branchId ?? '',
        roleCode: widget.roleCode,
        permissions: widget.permissions,
      );

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadReference(
    PurchaseReferenceCache cache,
    String type,
  ) async {
    try {
      final remote = await _catalog.list(type);
      try {
        await cache.write(type, remote);
      } catch (_) {
        // Remote values are still usable even if the offline cache is full.
      }
      return remote;
    } catch (_) {
      final snapshot = await cache.read(type);
      if (snapshot.isNotEmpty || type != 'products') return snapshot;
      // Older installed versions cached product catalogs in another store.
      final catalog = await ProductCatalogStore(
        widget.tenantId ?? widget.tenantName,
      ).read();
      return catalog
          .map(
            (product) => <String, dynamic>{
              'id': product.id,
              'name': product.name,
              'kind': 'stock',
              'barcode': product.barcode,
              'unit_name': product.unitName,
              'purchase_price_minor': (product.purchasePrice * 100).round(),
              'sale_price_minor': (product.salePrice * 100).round(),
            },
          )
          .toList(growable: false);
    }
  }

  Future<List<ChartAccount>> _loadPaymentAccountReferences(
    PurchaseReferenceCache cache,
    String branchId,
  ) async {
    try {
      final remote = (await _chart.list(branchId))
          .where(
            (account) =>
                account.active &&
                account.allowPosting &&
                account.isCashEquivalent,
          )
          .toList(growable: false);
      try {
        await cache.write(
          'cash_accounts',
          remote
              .map(
                (account) => <String, dynamic>{
                  'id': account.id,
                  'code': account.code,
                  'name_ar': account.nameAr,
                  'type': account.type,
                  'normal_balance': account.normalBalance,
                  'active': account.active,
                  'allow_posting': account.allowPosting,
                  'is_cash_equivalent': account.isCashEquivalent,
                },
              )
              .toList(growable: false),
        );
      } catch (_) {
        // Network success is not invalidated by an optional cache write.
      }
      return remote;
    } catch (_) {
      final local = await cache.read('cash_accounts');
      return local
          .map(ChartAccount.fromJson)
          .where(
            (account) =>
                account.active &&
                account.allowPosting &&
                account.isCashEquivalent,
          )
          .toList(growable: false);
    }
  }

  Future<bool> _load() async {
    final sequence = ++_loadSequence;
    final branchId = _branchId;
    if (branchId == null) {
      setState(() {
        _loading = false;
        _error = 'لا يوجد فرع متاح لهذا المستخدم.';
      });
      return false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final scope = widget.tenantId ?? widget.tenantName;
    final references = PurchaseReferenceCache(scope, branchId);
    Future<(bool, List<Map<String, dynamic>>)> invoices() async {
      try {
        final remote = await _accounting.listPurchases(branchId: branchId);
        try {
          await _purchaseStore.replaceRemoteSnapshot(scope, branchId, remote);
        } catch (_) {
          // Display the server answer; pending queue still owns its writes.
        }
        return (true, remote);
      } catch (_) {
        return (false, await _purchaseStore.read(scope, branchId));
      }
    }

    // These requests start together: a catalog timeout must not hide a
    // successfully retrieved invoice history or block offline data entry.
    final invoiceRequest = invoices();
    final suppliersRequest = _loadReference(references, 'suppliers');
    final productsRequest = _loadReference(references, 'products');
    final accountsRequest = _loadPaymentAccountReferences(references, branchId);
    try {
      final invoiceResult = await invoiceRequest;
      final suppliers = await suppliersRequest;
      final products = await productsRequest;
      final accounts = await accountsRequest;
      if (!mounted || sequence != _loadSequence) return false;
      setState(() {
        _invoices = invoiceResult.$2;
        _suppliers = suppliers;
        _products = products;
        _paymentAccounts = accounts;
        _offlineSnapshot = !invoiceResult.$1;
      });
      await _refreshPending();
      return invoiceResult.$1;
    } catch (_) {
      if (mounted && sequence == _loadSequence) {
        setState(
          () => _error =
              'تعذر فتح بيانات المشتريات المحلية. تحقق من مساحة التخزين أو صلاحياته.',
        );
      }
      return false;
    } finally {
      if (mounted && sequence == _loadSequence) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPending() async {
    final branch = _branchId;
    if (branch == null) return;
    try {
      final summary = await PurchaseOutbox(
        widget.tenantId ?? widget.tenantName,
        branch,
      ).summary();
      if (mounted) {
        setState(() {
          _queuedCount = summary.queued;
          _needsReviewCount = summary.needsReview;
        });
      }
    } catch (_) {
      // A damaged queue must never be overwritten or silently deleted.
    }
  }

  Future<void> _create() async {
    final branchId = _branchId;
    if (branchId == null || _saving) return;
    final deliverySession = _captureDeliverySession(branchId);
    final draft = await _openPurchaseEditor();
    if (draft == null || !mounted || _saving) return;
    if (!_isDeliverySessionCurrent(deliverySession)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تغيّرت الجلسة أو الفرع أو الصلاحيات؛ أعد فتح فاتورة الشراء.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final restoreGenerationAtSave =
        RealtimeSyncCoordinator.instance.restoreGeneration;
    final restoreEpochAtSave = RealtimeSyncCoordinator.instance.restoreEpoch;
    try {
      final request = await _accounting.preparePurchaseRequest(
        branchId: branchId,
        supplierName: draft.supplierName,
        supplierPhone: draft.supplierPhone,
        contactId: draft.contactId,
        paymentMode: draft.paymentMode,
        paymentChannel: draft.paymentChannel,
        paymentAccountCode: draft.paymentAccountCode,
        notes: draft.notes,
        restoreGeneration: restoreGenerationAtSave,
        items: draft.lines
            .map(
              (line) => <String, Object?>{
                'name': line.name,
                'kind': line.kind,
                'quantity_milli': (line.quantity * 1000).round(),
                'unit_name': line.unitName,
                'purchase_unit_name': line.purchaseUnitName,
                'units_per_package_milli': (line.unitsPerPackage * 1000)
                    .round(),
                'unit_price_minor': (line.purchasePrice * 100).round(),
                'sale_price_minor': (line.salePrice * 100).round(),
              },
            )
            .toList(),
      );
      if (!_isDeliverySessionCurrent(deliverySession) ||
          RealtimeSyncCoordinator.instance.restoreGeneration !=
              restoreGenerationAtSave ||
          RealtimeSyncCoordinator.instance.restoreEpoch != restoreEpochAtSave) {
        throw const PurchaseOutboxResponseInvalidated();
      }
      final queue = PurchaseOutbox(deliverySession.tenantId, branchId);
      // The draft becomes durable BEFORE attempting any network request.
      await queue.enqueue(
        request,
        isValid: () =>
            _isDeliverySessionCurrent(deliverySession) &&
            RealtimeSyncCoordinator.instance.restoreGeneration ==
                restoreGenerationAtSave &&
            RealtimeSyncCoordinator.instance.restoreEpoch == restoreEpochAtSave,
      );
      await _refreshPending();
      final outcome = await queue.flush(
        api: _accounting,
        currentRestoreGeneration: restoreGenerationAtSave,
        restoreEpoch: restoreEpochAtSave,
        isResponseValid: () =>
            _isDeliverySessionCurrent(deliverySession) &&
            RealtimeSyncCoordinator.instance.restoreGeneration ==
                restoreGenerationAtSave &&
            RealtimeSyncCoordinator.instance.restoreEpoch == restoreEpochAtSave,
        canSend: (_) => _isDeliverySessionCurrent(deliverySession),
      );
      await _refreshPending();
      if (!mounted) return;
      final operationId = request['local_operation_id']?.toString() ?? '';
      final currentEntry = await queue.find(operationId);
      if (!mounted) return;
      final sentCurrent = outcome.sentOperationIds.contains(operationId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            purchaseCurrentOperationMessage(
              state: currentEntry?.state,
              sent: sentCurrent,
              quarantined: outcome.quarantinedOperationIds.contains(
                operationId,
              ),
              permitted: _isDeliverySessionCurrent(deliverySession),
            ),
          ),
        ),
      );
      if (sentCurrent) await _load();
      RealtimeSyncCoordinator.instance.synchronizeNow();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ فاتورة الشراء: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pay(Map<String, dynamic> invoice) async {
    final due = ((invoice['due_minor'] as num?)?.toDouble() ?? 0) / 100;
    final amount = TextEditingController(text: due.toStringAsFixed(2));
    final reason = TextEditingController(text: 'دفعة للمورد');
    var channel = 'cash';
    var accountCode = _paymentAccounts.firstOrNull?.code ?? '';
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, update) => Scaffold(
            key: const ValueKey('purchase-supplier-payment-shell'),
            appBar: AppBar(toolbarHeight: 0),
            body: SafeArea(
              child: NineSoftResponsiveBody(
                child: ListView(
                  children: [
                    NineSoftEntryHeading(
                      title: 'سند صرف للمورد',
                      subtitle:
                          '${invoice['supplier_name'] ?? ''} • ${compactDocumentNumber(invoice['number']?.toString() ?? '')}',
                      icon: Icons.outbox_rounded,
                      status: 'صرف',
                      accent: NizamiColors.red,
                    ),
                    const SizedBox(height: 12),
                    NineSoftEntrySection(
                      title: 'بيانات السند',
                      subtitle: 'المبلغ وحساب الصرف والبيان',
                      icon: Icons.receipt_long_outlined,
                      step: '01',
                      accent: NizamiColors.blue,
                      child: Column(
                        children: [
                          TextField(
                            controller: amount,
                            textDirection: TextDirection.ltr,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            inputFormatters: const [latinDigitFormatter],
                            decoration: const InputDecoration(
                              labelText: 'المبلغ',
                              suffixText: 'YER',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SearchableChartAccountField(
                            accounts: _paymentAccounts,
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
                            controller: reason,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'البيان',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(pageContext, false),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () =>
                                Navigator.pop(pageContext, true),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('اعتماد السند'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (value <= 0 || value > due) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('مبلغ سند الصرف غير صالح.')));
      return;
    }
    try {
      final idempotencyStore = SettlementIdempotencyStore(
        tenantScope: widget.tenantId ?? widget.tenantName,
        branchId: _branchId!,
      );
      final idempotencyClaim = await idempotencyStore.claim(
        kind: SettlementOperationKind.supplierPayment,
        invoiceId: invoice['id'].toString(),
        amountMinor: (value * 100).round(),
        currency: 'YER',
        channel: channel,
        accountCode: accountCode,
        reason: reason.text,
      );
      await _accounting.storeSupplierPayment(
        invoiceId: invoice['id'].toString(),
        amount: value,
        currency: 'YER',
        idempotencyKey: idempotencyClaim.idempotencyKey,
        channel: channel,
        accountCode: accountCode,
        reason: reason.text,
      );
      if (!mounted) return;
      final refreshed = await _load();
      if (!refreshed) {
        throw StateError(
          'تم إرسال السند لكن تعذر تأكيد الرصيد المحدّث. أعد المحاولة بأمان.',
        );
      }
      await idempotencyStore.acknowledge(idempotencyClaim);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ترحيل سند الصرف وتخفيض رصيد المورد.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إصدار سند الصرف: $error')));
      }
    } finally {
      amount.dispose();
      reason.dispose();
    }
  }

  String _channelForAccount(String code) {
    final upper = code.toUpperCase();
    if (upper.contains('WALLET')) return 'wallet';
    if (upper.contains('BANK')) return 'bank';
    return 'cash';
  }

  Future<void> _void(Map<String, dynamic> invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فاتورة الشراء نهائيًا؟'),
        content: const Text(
          'سيُحذف أثر هذه الفاتورة فقط من المخزون والمورد والصندوق والقيود والتقارير والمزامنة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _accounting.voidPurchase(
        invoiceId: invoice['id'].toString(),
        reason: 'حذف فاتورة الشراء المدخلة بالخطأ من السجل',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حذف الفاتورة: $error')));
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> invoice) async {
    final branchId = _branchId;
    if (branchId == null || _saving) return;
    final draft = await _openPurchaseEditor(initialInvoice: invoice);
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final request = await _accounting.preparePurchaseRequest(
        branchId: branchId,
        supplierName: draft.supplierName,
        supplierPhone: draft.supplierPhone,
        contactId: draft.contactId,
        paymentMode: draft.paymentMode,
        paymentChannel: draft.paymentChannel,
        paymentAccountCode: draft.paymentAccountCode,
        notes: draft.notes,
        restoreGeneration: RealtimeSyncCoordinator.instance.restoreGeneration,
        items: draft.lines
            .map(
              (line) => <String, Object?>{
                'name': line.name,
                'kind': line.kind,
                'quantity_milli': (line.quantity * 1000).round(),
                'unit_name': line.unitName,
                'purchase_unit_name': line.purchaseUnitName,
                'units_per_package_milli': (line.unitsPerPackage * 1000)
                    .round(),
                'unit_price_minor': (line.purchasePrice * 100).round(),
                'sale_price_minor': (line.salePrice * 100).round(),
              },
            )
            .toList(),
      );
      await _accounting.replacePurchase(
        invoiceId: invoice['id'].toString(),
        request: request,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعديل الفاتورة واستبدال جميع آثارها المحاسبية.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تعديل الفاتورة: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_PurchaseDraft?> _openPurchaseEditor({
    Map<String, dynamic>? initialInvoice,
  }) {
    final result = Completer<_PurchaseDraft?>();
    setState(() {
      _purchaseEditorInitialInvoice = initialInvoice;
      _purchaseEditorResult = result;
    });
    return result.future;
  }

  void _closePurchaseEditor([_PurchaseDraft? draft]) {
    final result = _purchaseEditorResult;
    if (result == null || result.isCompleted) return;
    setState(() {
      _purchaseEditorResult = null;
      _purchaseEditorInitialInvoice = null;
    });
    result.complete(draft);
  }

  Future<Uint8List> _purchasePdf(Map<String, dynamic> invoice) async {
    await BusinessIdentityStore.instance.ensureLoaded();
    final arabic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latin = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final profile = _profile;
    final items = (invoice['items'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final total = ((invoice['total_minor'] as num?)?.toDouble() ?? 0) / 100;
    final paid = ((invoice['paid_minor'] as num?)?.toDouble() ?? 0) / 100;
    final due = ((invoice['due_minor'] as num?)?.toDouble() ?? 0) / 100;
    final logo = profile.logoBytes == null
        ? null
        : pw.MemoryImage(profile.logoBytes!);
    final document = pw.Document(
      title: 'Purchase ${invoice['number'] ?? ''}',
      author: profile.businessName,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(18),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: arabic,
          bold: arabic,
          fontFallback: [latin],
        ),
        header: (_) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      profile.businessName,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (profile.businessNameEn.isNotEmpty)
                      pw.Text(
                        profile.businessNameEn,
                        textDirection: pw.TextDirection.ltr,
                        style: pw.TextStyle(font: latin, fontSize: 8),
                      ),
                  ],
                ),
                if (logo != null)
                  pw.Image(logo, width: 58 * profile.logoScale, height: 42),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      profile.phone,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      profile.address,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColors.orange700),
          ],
        ),
        build: (_) => [
          pw.Text(
            'فاتورة مشتريات',
            style: pw.TextStyle(
              fontSize: 20,
              color: PdfColors.orange800,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('المورد: ${invoice['supplier_name'] ?? '-'}'),
              pw.Text('رقم الفاتورة: ${invoice['number'] ?? '-'}'),
              pw.Text(
                'التاريخ: ${(invoice['occurred_at'] ?? '').toString().split('T').first}',
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'الصنف / الخدمة',
              'الكمية',
              'السعر',
              'الإجمالي',
            ],
            data: [
              for (var index = 0; index < items.length; index++)
                [
                  '${index + 1}',
                  items[index]['product_name_snapshot']?.toString() ?? '-',
                  ((((items[index]['quantity_milli'] as num?)?.toDouble() ??
                              0) /
                          1000))
                      .toStringAsFixed(3),
                  ((((items[index]['unit_price_minor'] as num?)?.toDouble() ??
                              0) /
                          100))
                      .toStringAsFixed(2),
                  (((((items[index]['quantity_milli'] as num?)?.toDouble() ??
                                  0) /
                              1000) *
                          (((items[index]['unit_price_minor'] as num?)
                                      ?.toDouble() ??
                                  0) /
                              100)))
                      .toStringAsFixed(2),
                ],
            ],
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.orange700,
            ),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'الإجمالي ${total.toStringAsFixed(2)} YER   •   المدفوع ${paid.toStringAsFixed(2)} YER   •   المتبقي ${due.toStringAsFixed(2)} YER',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _exportPurchase(
    Map<String, dynamic> invoice, {
    bool share = false,
  }) async {
    try {
      final bytes = await _purchasePdf(invoice);
      final filename = 'purchase-${invoice['number'] ?? invoice['id']}.pdf';
      if (share) {
        await PdfExportService.share(bytes: bytes, filename: filename);
      } else {
        await PdfExportService.save(bytes: bytes, filename: filename);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تجهيز فاتورة المشتريات: $error')),
        );
      }
    }
  }

  Future<void> _printPurchase(Map<String, dynamic> invoice) async {
    final bytes = await _purchasePdf(invoice);
    await PdfExportService.print(
      bytes: bytes,
      filename: 'purchase-${invoice['number'] ?? invoice['id']}.pdf',
    );
  }

  Future<void> _view(Map<String, dynamic> invoice) async {
    final items = (invoice['items'] as List? ?? const []).whereType<Map>();
    await showDialog<void>(
      context: context,
      builder: (context) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
            unawaited(_printPurchase(invoice));
          },
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text(
              'فاتورة مشتريات ${compactDocumentNumber(invoice['number']?.toString() ?? '')}',
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('المورد: ${invoice['supplier_name'] ?? '-'}'),
                    Text('الهاتف: ${invoice['supplier_phone'] ?? '-'}'),
                    const Divider(),
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text(
                          item['product_name_snapshot']?.toString() ?? '-',
                        ),
                        trailing: Text(
                          '${(((item['quantity_milli'] as num?)?.toDouble() ?? 0) / 1000).toStringAsFixed(3)} × ${(((item['unit_price_minor'] as num?)?.toDouble() ?? 0) / 100).toStringAsFixed(2)}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontFamily: 'ArialMTBlack'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => unawaited(_printPurchase(invoice)),
                icon: const Icon(Icons.print_rounded),
                label: const Text('طباعة سريعة  Ctrl+P'),
              ),
              TextButton.icon(
                onPressed: () => _exportPurchase(invoice, share: true),
                icon: const Icon(Icons.share_outlined),
                label: const Text('مشاركة PDF'),
              ),
              FilledButton.icon(
                onPressed: () => _exportPurchase(invoice),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('حفظ PDF'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    if (_purchaseEditorResult != null) {
      return _PurchaseEditor(
        key: const ValueKey('purchase-document-editor'),
        suppliers: _suppliers,
        products: _products,
        paymentAccounts: _paymentAccounts,
        initialInvoice: _purchaseEditorInitialInvoice,
        onSaved: _closePurchaseEditor,
        onCancel: _closePurchaseEditor,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المشتريات'),
        toolbarHeight: 0,
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canCreate && !desktop
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('فاتورة شراء'),
            )
          : null,
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: Column(
            children: [
              NineSoftPageHeader(
                title: 'المشتريات',
                subtitle: purchaseQueueSubtitle(
                  offline: _offlineSnapshot,
                  queued: _queuedCount,
                  needsReview: _needsReviewCount,
                ),
                icon: Icons.shopping_basket_rounded,
                color: NizamiColors.blue,
                actions: [
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث'),
                  ),
                  if (_canCreate)
                    FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('فاتورة شراء جديدة'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _invoices.isEmpty
                    ? const NineSoftEmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: 'لا توجد فواتير شراء محفوظة',
                        message:
                            'ستظهر فواتير الشراء الحقيقية هنا بعد إضافتها.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: _invoices.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final invoice = _invoices[index];
                            final total =
                                ((invoice['total_minor'] as num?)?.toDouble() ??
                                    0) /
                                100;
                            final due =
                                ((invoice['due_minor'] as num?)?.toDouble() ??
                                    0) /
                                100;
                            final items = invoice['items'] is List
                                ? invoice['items'] as List
                                : const [];
                            return Card(
                              child: ExpansionTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.receipt_long_rounded),
                                ),
                                title: Text(
                                  invoice['supplier_name']?.toString() ??
                                      'مورد',
                                ),
                                subtitle: Text(
                                  '${compactDocumentNumber(invoice['number']?.toString() ?? '')}\nالإجمالي ${total.toStringAsFixed(2)} YER • المتبقي ${due.toStringAsFixed(2)} YER',
                                ),
                                children: [
                                  for (final raw in items.whereType<Map>())
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        raw['product_name_snapshot']
                                                ?.toString() ??
                                            '',
                                      ),
                                      trailing: Text(
                                        '${((raw['quantity_milli'] as num?)?.toDouble() ?? 0) / 1000} × ${((raw['unit_price_minor'] as num?)?.toDouble() ?? 0) / 100}',
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ),
                                  OverflowBar(
                                    alignment: MainAxisAlignment.end,
                                    spacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _view(invoice),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                        ),
                                        label: const Text('عرض / PDF'),
                                      ),
                                      if (due > 0)
                                        FilledButton.icon(
                                          onPressed: () => _pay(invoice),
                                          icon: const Icon(
                                            Icons.payments_outlined,
                                          ),
                                          label: const Text('سند صرف'),
                                        ),
                                      if (_canEdit)
                                        OutlinedButton.icon(
                                          onPressed: () => _edit(invoice),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('تعديل'),
                                        ),
                                      if (_canDelete)
                                        TextButton.icon(
                                          onPressed: () => _void(invoice),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                          label: const Text('حذف نهائي'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseEditor extends StatefulWidget {
  const _PurchaseEditor({
    required this.suppliers,
    required this.products,
    required this.paymentAccounts,
    required this.onSaved,
    required this.onCancel,
    this.initialInvoice,
    super.key,
  });

  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> products;
  final List<ChartAccount> paymentAccounts;
  final Map<String, dynamic>? initialInvoice;
  final ValueChanged<_PurchaseDraft> onSaved;
  final VoidCallback onCancel;

  @override
  State<_PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<_PurchaseEditor> {
  final _formKey = GlobalKey<FormState>();
  final _supplier = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  late final List<_LineControllers> _lines;
  String _paymentMode = 'credit';
  String _contactId = '';
  String _selectedSupplierName = '';
  String _paymentAccountCode = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInvoice;
    _supplier.text = initial?['supplier_name']?.toString() ?? '';
    _selectedSupplierName = _supplier.text;
    _phone.text = initial?['supplier_phone']?.toString() ?? '';
    _notes.text = initial?['notes']?.toString() ?? '';
    _contactId = initial?['contact_id']?.toString() ?? '';
    _paymentMode = initial?['payment_mode']?.toString() == 'cash'
        ? 'cash'
        : 'credit';
    _paymentAccountCode = initial?['payment_account_code']?.toString() ?? '';
    final items = (initial?['items'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    _lines = items.isEmpty
        ? [_LineControllers()]
        : items.map((item) => _LineControllers(initial: item)).toList();
  }

  @override
  void dispose() {
    _supplier.dispose();
    _phone.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final lines = _lines.map((line) => line.value).toList();
    widget.onSaved(
      _PurchaseDraft(
        supplierName: _supplier.text.trim(),
        contactId: _contactId,
        supplierPhone: _phone.text.trim(),
        paymentMode: _paymentMode,
        paymentAccountCode: _paymentAccountCode,
        paymentChannel: _channelForAccount(_paymentAccountCode),
        notes: _notes.text.trim(),
        lines: lines,
      ),
    );
  }

  void _appendLine() {
    if (_lines.length >= 200) return;
    final line = _LineControllers();
    setState(() => _lines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) line.nameFocus?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialInvoice == null
              ? 'فاتورة شراء جديدة'
              : 'تعديل فاتورة الشراء',
        ),
        leading: IconButton(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ وترحيل'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 16 : 40,
            vertical: 18,
          ),
          children: [
            const NineSoftEntryHeading(
              title: 'فاتورة مشتريات جديدة',
              subtitle:
                  'حدد المورد، أدخل الأصناف والتكلفة، ثم راجع الإجمالي قبل الترحيل',
              icon: Icons.shopping_cart_checkout_rounded,
              status: 'توريد / مشتريات',
              accent: NizamiColors.blue,
            ),
            const SizedBox(height: 14),
            NineSoftDocumentCommandBar(
              title: 'اختصارات فاتورة الشراء',
              actions: [
                NineSoftDocumentCommandAction(
                  key: const ValueKey('purchase-command-add-line'),
                  label: 'إضافة صنف',
                  shortcut: 'F2',
                  icon: Icons.add_box_rounded,
                  color: const Color(0xFF7552D5),
                  onPressed: _lines.length >= 200 ? null : _appendLine,
                ),
                NineSoftDocumentCommandAction(
                  key: const ValueKey('purchase-command-credit'),
                  label: 'شراء آجل',
                  shortcut: 'على المورد',
                  icon: Icons.event_note_rounded,
                  color: const Color(0xFFF0A014),
                  onPressed: () => setState(() => _paymentMode = 'credit'),
                ),
                NineSoftDocumentCommandAction(
                  key: const ValueKey('purchase-command-cash'),
                  label: 'شراء مدفوع',
                  shortcut: 'تسوية فورية',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF16A85B),
                  onPressed: () => setState(() {
                    _paymentMode = 'cash';
                    if (_paymentAccountCode.isEmpty) {
                      _paymentAccountCode =
                          widget.paymentAccounts.firstOrNull?.code ?? '';
                    }
                  }),
                ),
                NineSoftDocumentCommandAction(
                  key: const ValueKey('purchase-command-save'),
                  label: 'حفظ وترحيل',
                  shortcut: 'Ctrl+Enter',
                  icon: Icons.cloud_done_rounded,
                  color: const Color(0xFF147BE0),
                  onPressed: _save,
                ),
              ],
            ),
            const SizedBox(height: 14),
            NineSoftEntrySection(
              title: 'بيانات المورد والتسوية',
              subtitle: 'بيانات الطرف وطريقة دفع الفاتورة',
              step: '01',
              icon: Icons.local_shipping_outlined,
              accent: NizamiColors.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<Map<String, dynamic>>(
                    displayStringForOption: (item) =>
                        item['name']?.toString() ?? '',
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      return widget.suppliers.where(
                        (item) => (item['name']?.toString().toLowerCase() ?? '')
                            .contains(query),
                      );
                    },
                    onSelected: (item) {
                      _selectedSupplierName = item['name']?.toString() ?? '';
                      _contactId = item['id']?.toString() ?? '';
                      _supplier.text = _selectedSupplierName;
                      _phone.text = item['phone']?.toString() ?? '';
                    },
                    fieldViewBuilder: (context, controller, focus, submit) {
                      if (controller.text.isEmpty &&
                          _supplier.text.isNotEmpty) {
                        controller.text = _supplier.text;
                      }
                      if (_supplier.text.isEmpty &&
                          controller.text.isNotEmpty) {
                        _supplier.text = controller.text;
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focus,
                        onChanged: (value) {
                          _supplier.text = value;
                          if (value.trim() != _selectedSupplierName) {
                            _contactId = '';
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'المورد',
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'اكتب اسم المورد.'
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [latinDigitFormatter],
                    decoration: const InputDecoration(
                      labelText: 'رقم هاتف المورد',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'credit',
                        label: Text('آجل - على حساب المورد'),
                      ),
                      ButtonSegment(
                        value: 'cash',
                        label: Text('مدفوع بالكامل'),
                      ),
                    ],
                    selected: {_paymentMode},
                    onSelectionChanged: (value) => setState(() {
                      _paymentMode = value.first;
                      if (_paymentMode == 'cash' &&
                          _paymentAccountCode.isEmpty) {
                        _paymentAccountCode =
                            widget.paymentAccounts.firstOrNull?.code ?? '';
                      }
                    }),
                  ),
                  if (_paymentMode == 'cash') ...[
                    const SizedBox(height: 12),
                    SearchableChartAccountField(
                      accounts: widget.paymentAccounts,
                      value: _paymentAccountCode.isEmpty
                          ? null
                          : _paymentAccountCode,
                      label: 'حساب الدفع الفعلي',
                      hint: 'ابحث عن الصندوق أو البنك أو المحفظة',
                      helperText:
                          'الحساب الذي خرج منه مبلغ فاتورة الشراء فعليا',
                      onChanged: (value) =>
                          setState(() => _paymentAccountCode = value ?? ''),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            NineSoftEntrySection(
              title: 'بنود وتكاليف المشتريات',
              subtitle: 'الكمية ووحدات الشراء وسعر التكلفة وسعر البيع',
              step: '02',
              icon: Icons.inventory_2_outlined,
              accent: NizamiColors.amber,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'بنود الفاتورة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _lines.length >= 200 ? null : _appendLine,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة بند'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var index = 0; index < _lines.length; index++)
                    _PurchaseLineCard(
                      key: ObjectKey(_lines[index]),
                      index: index,
                      controllers: _lines[index],
                      products: widget.products,
                      onComplete: index == _lines.length - 1
                          ? _appendLine
                          : null,
                      onRemove: _lines.length == 1
                          ? null
                          : () {
                              final removed = _lines.removeAt(index);
                              removed.dispose();
                              setState(() {});
                            },
                    ),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      for (final line in _lines) line.quantity,
                      for (final line in _lines) line.purchase,
                    ]),
                    builder: (context, _) {
                      final total = _lines.fold<double>(0, (sum, line) {
                        final qty =
                            double.tryParse(line.quantity.text.trim()) ?? 0;
                        final price =
                            double.tryParse(line.purchase.text.trim()) ?? 0;
                        return sum + qty * price;
                      });
                      return NineSoftEntryTotalPreview(
                        label: 'الإجمالي التقديري للمشتريات',
                        amount: total,
                        subtitle:
                            'يتحدث أثناء الإدخال؛ اعتمد السعر الفعلي قبل الحفظ',
                        accent: NizamiColors.blue,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            NineSoftEntrySection(
              title: 'بيان إضافي',
              icon: Icons.sticky_note_2_outlined,
              step: '03',
              child: TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ),
            const SizedBox(height: 14),
            NineSoftEntryFooter(
              onSave: _save,
              label: 'حفظ وترحيل فاتورة الشراء',
              icon: Icons.save_outlined,
              note: 'تأكد من المورد والكميات وتكلفة جميع البنود',
            ),
          ],
        ),
      ),
    );
  }

  String _channelForAccount(String code) {
    final upper = code.toUpperCase();
    if (upper.contains('WALLET')) return 'wallet';
    if (upper.contains('BANK')) return 'bank';
    return 'cash';
  }
}

class _PurchaseLineCard extends StatelessWidget {
  const _PurchaseLineCard({
    required this.index,
    required this.controllers,
    required this.products,
    required this.onComplete,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _LineControllers controllers;
  final List<Map<String, dynamic>> products;
  final VoidCallback? onComplete;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: NineSoftEntrySection(
      title: 'الصنف ${index + 1}',
      icon: Icons.widgets_outlined,
      step: '${index + 1}',
      accent: NizamiColors.blue,
      action: onRemove == null
          ? null
          : IconButton(
              tooltip: 'حذف هذا البند',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: (item) => item['name']?.toString() ?? '',
            optionsBuilder: (value) {
              final query = value.text.trim().toLowerCase();
              return products.where(
                (item) =>
                    (item['name']?.toString().toLowerCase() ?? '').contains(
                      query,
                    ) ||
                    (item['sku']?.toString().toLowerCase() ?? '').contains(
                      query,
                    ) ||
                    (item['barcode']?.toString().toLowerCase() ?? '').contains(
                      query,
                    ),
              );
            },
            onSelected: (item) {
              controllers.name.text = item['name']?.toString() ?? '';
              final unit = item['unit_name']?.toString().trim() ?? '';
              controllers.unitName = unit.isEmpty ? 'حبة' : unit;
              controllers.purchaseUnit.text = controllers.unitName;
              controllers.unitsPerPackage.text = '1';
              controllers.kind = item['kind']?.toString() ?? 'stock';
              controllers.quantityFocus.requestFocus();
            },
            fieldViewBuilder: (context, controller, focus, submit) {
              controllers.nameFocus = focus;
              return TextFormField(
                controller: controller,
                focusNode: focus,
                onChanged: (value) => controllers.name.text = value,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) =>
                    controllers.quantityFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'اسم الصنف أو الخدمة',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'اكتب اسم الصنف.' : null,
              );
            },
          ),
          const SizedBox(height: 12),
          NineSoftEntryFieldGrid(
            minFieldWidth: 185,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _purchaseBaseUnits.contains(controllers.unitName)
                    ? controllers.unitName
                    : 'وحدة',
                decoration: const InputDecoration(
                  labelText: 'وحدة المخزون',
                  helperText: 'مثال: جرام أو حبة',
                ),
                items: _purchaseBaseUnits
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(growable: false),
                onChanged: (value) => controllers.unitName = value ?? 'وحدة',
              ),
              TextFormField(
                controller: controllers.purchaseUnit,
                decoration: const InputDecoration(
                  labelText: 'وحدة الشراء',
                  hintText: 'كيلو أو كرتون',
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'حدد وحدة الشراء' : null,
              ),
              _numberField(
                controllers.unitsPerPackage,
                'محتوى وحدة الشراء',
                positive: true,
              ),
              const Text(
                'مثال: إذا وحدة المخزون جرام، ووحدة الشراء كيلو، فمحتوى الوحدة 1000. '
                'إذا كانت وحدة المخزون كيلو ووحدة الشراء كيلو فمحتواها 1.',
              ),
            ],
          ),
          const SizedBox(height: 12),
          NineSoftEntryFieldGrid(
            minFieldWidth: 185,
            children: [
              _numberField(
                controllers.quantity,
                'الكمية',
                positive: true,
                focusNode: controllers.quantityFocus,
                onSubmitted: () => controllers.purchaseFocus.requestFocus(),
              ),
              _numberField(
                controllers.purchase,
                'تكلفة وحدة الشراء',
                positive: true,
                focusNode: controllers.purchaseFocus,
                onSubmitted: () => controllers.saleFocus.requestFocus(),
              ),
              _numberField(
                controllers.sale,
                'سعر البيع',
                focusNode: controllers.saleFocus,
                onSubmitted: onComplete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: Listenable.merge([
              controllers.quantity,
              controllers.purchase,
            ]),
            builder: (context, _) => NineSoftEntryTotalPreview(
              label: 'قيمة هذا البند',
              amount:
                  (double.tryParse(controllers.quantity.text.trim()) ?? 0) *
                  (double.tryParse(controllers.purchase.text.trim()) ?? 0),
              accent: NizamiColors.blue,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool positive = false,
    FocusNode? focusNode,
    VoidCallback? onSubmitted,
  }) => TextFormField(
    controller: controller,
    focusNode: focusNode,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [latinDigitFormatter],
    textDirection: TextDirection.ltr,
    textInputAction: onSubmitted == null
        ? TextInputAction.done
        : TextInputAction.next,
    onFieldSubmitted: (_) => onSubmitted?.call(),
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = double.tryParse(value?.trim() ?? '');
      if (number == null || number < 0 || (positive && number <= 0)) {
        return 'قيمة غير صالحة';
      }
      return null;
    },
  );
}

class _LineControllers {
  _LineControllers({Map<dynamic, dynamic>? initial})
    : name = TextEditingController(
        text:
            initial?['product_name_snapshot']?.toString() ??
            initial?['name']?.toString() ??
            '',
      ),
      quantity = TextEditingController(
        text: _decimalFromMilli(initial?['quantity_milli'], fallback: '1'),
      ),
      purchase = TextEditingController(
        text: _decimalFromMinor(initial?['unit_price_minor']),
      ),
      sale = TextEditingController(
        text: _decimalFromMinor(initial?['sale_price_minor']),
      ),
      purchaseUnit = TextEditingController(
        text:
            initial?['purchase_unit_name']?.toString() ??
            initial?['unit_name']?.toString() ??
            'حبة',
      ),
      unitsPerPackage = TextEditingController(
        text: _decimalFromMilli(
          initial?['units_per_package_milli'],
          fallback: '1',
        ),
      ),
      kind = initial?['kind']?.toString() ?? 'stock',
      unitName = initial?['unit_name']?.toString() ?? 'حبة';

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController purchase;
  final TextEditingController sale;
  final TextEditingController purchaseUnit;
  final TextEditingController unitsPerPackage;
  FocusNode? nameFocus;
  final quantityFocus = FocusNode();
  final purchaseFocus = FocusNode();
  final saleFocus = FocusNode();
  String kind;
  String unitName;

  static String _decimalFromMilli(dynamic raw, {String fallback = ''}) {
    final value = (raw as num?)?.toDouble();
    if (value == null) return fallback;
    final result = value / 1000;
    return result == result.roundToDouble()
        ? result.toInt().toString()
        : result.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  static String _decimalFromMinor(dynamic raw) {
    final value = (raw as num?)?.toDouble();
    if (value == null) return '';
    return (value / 100).toStringAsFixed(2);
  }

  _PurchaseLine get value => _PurchaseLine(
    name: name.text.trim(),
    quantity: double.parse(quantity.text.trim()),
    purchasePrice: double.parse(purchase.text.trim()),
    salePrice: double.tryParse(sale.text.trim()) ?? 0,
    kind: kind,
    unitName: unitName,
    purchaseUnitName: purchaseUnit.text.trim(),
    unitsPerPackage: double.parse(unitsPerPackage.text.trim()),
  );

  void dispose() {
    name.dispose();
    quantity.dispose();
    purchase.dispose();
    sale.dispose();
    purchaseUnit.dispose();
    unitsPerPackage.dispose();
    quantityFocus.dispose();
    purchaseFocus.dispose();
    saleFocus.dispose();
  }
}

class _PurchaseDraft {
  const _PurchaseDraft({
    required this.supplierName,
    required this.contactId,
    required this.supplierPhone,
    required this.paymentMode,
    required this.paymentAccountCode,
    required this.paymentChannel,
    required this.notes,
    required this.lines,
  });

  final String supplierName;
  final String contactId;
  final String supplierPhone;
  final String paymentMode;
  final String paymentAccountCode;
  final String paymentChannel;
  final String notes;
  final List<_PurchaseLine> lines;
}

class _PurchaseLine {
  const _PurchaseLine({
    required this.name,
    required this.quantity,
    required this.purchasePrice,
    required this.salePrice,
    required this.kind,
    required this.unitName,
    required this.purchaseUnitName,
    required this.unitsPerPackage,
  });

  final String name;
  final double quantity;
  final double purchasePrice;
  final double salePrice;
  final String kind;
  final String unitName;
  final String purchaseUnitName;
  final double unitsPerPackage;
}

const _purchaseBaseUnits = <String>[
  'حبة',
  'جرام',
  'كيلو',
  'مليجرام',
  'لتر',
  'مل',
  'متر',
  'سم',
  'وحدة',
];
