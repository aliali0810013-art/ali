import '../returns/return_workspace_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/pdf/pdf_export_service.dart';
import '../../core/formatters/latin_digit_formatter.dart';
import 'package:uuid/uuid.dart';

import '../accounting/accounting_api.dart';
import '../accounting/chart_accounts_api.dart';
import '../accounting/searchable_chart_account_field.dart';
import '../settings/identity_api.dart';

import '../../settings/business_identity_store.dart';
import '../customers/customer_store.dart';
import '../wasl/wasl_page.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/nizami_theme.dart';
import '../wasl/wasl_qr_scanner_page.dart';
import '../products/product_catalog_store.dart';
import '../products/product_sale_option_store.dart';
import '../sync/realtime_sync_coordinator.dart';
import '../sync/quarantined_operation_store.dart';
import '../sync/restore_submission_policy.dart';
import '../sync/sales_invoice_outbox.dart';
import '../modules/catalog_sync_api.dart';
import '../whatsapp/whatsapp_api.dart';
import 'invoice_history_store.dart';
import 'presentation/sales_invoice_adapter.dart';
import 'presentation/sales_invoice_reference_view.dart';
import 'presentation/sales_invoice_view_model.dart';
import 'invoice_pdf_service.dart';
import 'weighted_sale_math.dart';

enum _InvoiceDeliveryState {
  editingDraft,
  finalizing,
  queued,
  needsReview,
  posted,
  quarantined,
}

class InvoiceWorkspacePage extends StatefulWidget {
  const InvoiceWorkspacePage({
    required this.branchIds,
    required this.tenantName,
    this.tenantId,
    required this.employeeName,
    required this.token,
    required this.roleCode,
    required this.permissions,
    this.catalogApi,
    this.chartAccountsLoader,
    this.identityLoader,
    this.syncChanges,
    this.accountingApiFactory,
    this.salesOutboxFactory,
    this.synchronizeNow,
    this.restoreGenerationReader,
    this.restoreEpochReader,
    super.key,
  });
  final List<String> branchIds;
  final String tenantName;
  final String? tenantId;
  final String employeeName;
  final String token;
  final String roleCode;
  final List<String> permissions;
  final CatalogSyncApi? catalogApi;
  final Future<List<ChartAccount>> Function(String branchId)?
  chartAccountsLoader;
  final Future<void> Function(String branchId, String tenantScope)?
  identityLoader;
  final Stream<Set<String>>? syncChanges;
  final AccountingApi Function()? accountingApiFactory;
  final SalesInvoiceOutbox Function(String tenantId, String branchId)?
  salesOutboxFactory;
  final Future<void> Function()? synchronizeNow;
  final int Function()? restoreGenerationReader;
  final DateTime? Function()? restoreEpochReader;
  @override
  State<InvoiceWorkspacePage> createState() => _InvoiceWorkspacePageState();
}

class _InvoiceWorkspacePageState extends State<InvoiceWorkspacePage> {
  static const _walkInCustomerName = 'عميل نقدي';
  final _customer = TextEditingController(text: _walkInCustomerName);
  final _phone = TextEditingController();
  final _item = TextEditingController();
  final _barcodeInput = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _quantityFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _saleAmount = TextEditingController();
  int _pendingLineDiscountMinor = 0;
  int? _pendingWeightGramsMilli;
  int? _pendingPriceNumeratorMinor;
  int? _pendingPriceDenominator;
  bool _priceManuallyOverridden = false;
  final _notes = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _amountTendered = TextEditingController(text: '0');
  final _historyStore = InvoiceHistoryStore();
  final List<InvoiceLine> _lines = [];
  int? _editingLineIndex;
  List<CatalogProduct> _products = [];
  List<ProductSaleOption> _saleOptions = [];
  CatalogProduct? _selectedProduct;
  ProductSaleOption? _selectedSaleOption;
  List<SavedCustomer> _customers = [];
  String _selectedCustomerId = '';
  List<InvoiceDocument> _history = [];
  final ValueNotifier<List<InvoiceDocument>> _historyNotifier =
      ValueNotifier<List<InvoiceDocument>>(const []);
  late String _branchId;
  late InvoiceDocument _invoice;
  TextEditingController? _autoItemController;
  FocusNode? _autoItemFocus;
  TextEditingController? _autoCustomerController;
  bool _saving = false;
  bool _finalizing = false;
  bool _explicitDraft = false;
  _InvoiceDeliveryState _deliveryState = _InvoiceDeliveryState.editingDraft;
  Map<String, SalesInvoiceOutboxState> _outboxStates = const {};
  bool _sendingWhatsapp = false;
  final Set<String> _whatsappSentInvoices = <String>{};
  final Map<String, Future<Uint8List>> _whatsappImageCache = {};
  String _operationId = const Uuid().v4();
  String _remoteInvoiceId = '';
  String _remoteNumber = '';
  String _replacementInvoiceId = '';
  int _operationRestoreGeneration = 0;
  String _paymentMode = 'cash';
  String? _paymentChannel = 'cash';
  String _paymentAccountCode = '';
  List<ChartAccount> _paymentAccounts = const [];
  int _paymentAccountLoadGeneration = 0;
  StreamSubscription<Set<String>>? _syncSubscription;

  List<String> get _branches =>
      widget.branchIds.isEmpty ? const ['MAIN'] : widget.branchIds;
  String get _tenantScope => widget.tenantId ?? widget.tenantName;
  ProductCatalogStore get _catalog => ProductCatalogStore(_tenantScope);
  CatalogSyncApi get _catalogApi =>
      widget.catalogApi ?? CatalogSyncApi(token: widget.token);
  bool get _canEdit =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.update');
  bool get _canCreate =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.create');
  bool get _canFinalizeCurrent =>
      _replacementInvoiceId.isEmpty ? _canCreate : _canEdit;
  bool get _canDelete =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('invoices.delete');
  bool get _canManageSaleOptions =>
      widget.roleCode == 'owner' ||
      widget.permissions.contains('catalog.write');
  AccountingApi get _accountingApi =>
      widget.accountingApiFactory?.call() ?? AccountingApi(token: widget.token);
  SalesInvoiceOutbox get _salesOutbox =>
      widget.salesOutboxFactory?.call(_tenantScope, _branchId) ??
      SalesInvoiceOutbox(_tenantScope, _branchId);
  int get _currentRestoreGeneration =>
      widget.restoreGenerationReader?.call() ??
      RealtimeSyncCoordinator.instance.restoreGeneration;
  DateTime? get _currentRestoreEpoch =>
      widget.restoreEpochReader?.call() ??
      RealtimeSyncCoordinator.instance.restoreEpoch;
  bool get _documentLocked => switch (_deliveryState) {
    _InvoiceDeliveryState.queued ||
    _InvoiceDeliveryState.needsReview ||
    _InvoiceDeliveryState.posted ||
    _InvoiceDeliveryState.quarantined ||
    _InvoiceDeliveryState.finalizing => true,
    _InvoiceDeliveryState.editingDraft => false,
  };

  @override
  void initState() {
    super.initState();
    _branchId = _branches.first;
    _operationRestoreGeneration = _currentRestoreGeneration;
    _invoice = _readInvoice();
    _syncSubscription =
        (widget.syncChanges ?? RealtimeSyncCoordinator.instance.changes).listen(
          (types) {
            if (!mounted) return;
            if (types.contains('invoice') ||
                types.contains('sales_invoice_needs_review')) {
              if (!_saving && !_finalizing) {
                unawaited(_refreshHistoryAndDelivery());
              }
            }
            if (types.contains('product') || types.contains('contact')) {
              unawaited(_refreshCachedCatalog());
            }
            if (types.contains('product_sale_option')) {
              final selected = _selectedProduct;
              if (selected != null) unawaited(_loadSaleOptions(selected));
            }
          },
        );
    _load();
  }

  @override
  void didUpdateWidget(covariant InvoiceWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPermissions = oldWidget.permissions.toSet();
    final currentPermissions = widget.permissions.toSet();
    final sessionChanged =
        oldWidget.token != widget.token ||
        (oldWidget.tenantId ?? oldWidget.tenantName) != _tenantScope ||
        oldWidget.roleCode != widget.roleCode ||
        oldPermissions.length != currentPermissions.length ||
        !oldPermissions.containsAll(currentPermissions);
    if (!sessionChanged) return;
    _paymentAccountLoadGeneration++;
    _paymentAccounts = const [];
    _paymentAccountCode = '';
    _paymentChannel = 'cash';
    unawaited(_loadPaymentAccounts());
  }

  Future<void> _refreshCachedCatalog() async {
    final products = await _catalog.read();
    final customers = await CustomerStore(_tenantScope).read();
    if (mounted) {
      setState(() {
        _products = products;
        _customers = customers;
      });
    }
  }

  Future<void> _refreshHistoryOnly() => _refreshHistoryAndDelivery();

  Future<void> _refreshHistoryAndDelivery() async {
    final capturedOperation = _operationId;
    final history = await _historyStore.read(_tenantScope, _branchId);
    final entries = await _salesOutbox.list();
    final states = <String, SalesInvoiceOutboxState>{
      for (final entry in entries) entry.operationId: entry.state,
    };
    if (mounted) {
      _historyNotifier.value = List.unmodifiable(history);
      setState(() {
        _history = history;
        _outboxStates = states;
        if (_operationId != capturedOperation) return;
        InvoiceDocument? canonical;
        for (final candidate in history) {
          if (candidate.localOperationId == capturedOperation) {
            canonical = candidate;
            break;
          }
        }
        if (canonical?.isQuarantined == true) {
          _invoice = canonical!;
          _explicitDraft = false;
          _deliveryState = _InvoiceDeliveryState.quarantined;
        } else if (canonical?.postedToServer == true) {
          _invoice = canonical!;
          _remoteInvoiceId = canonical.serverInvoiceId;
          _remoteNumber = canonical.serverNumber;
          _replacementInvoiceId = '';
          _explicitDraft = false;
          _deliveryState = _InvoiceDeliveryState.posted;
        } else if (states[capturedOperation] ==
            SalesInvoiceOutboxState.needsReview) {
          _deliveryState = _InvoiceDeliveryState.needsReview;
        } else if (states[capturedOperation] ==
            SalesInvoiceOutboxState.queued) {
          _deliveryState = _InvoiceDeliveryState.queued;
        } else if (canonical?.isDraft == true) {
          _explicitDraft = true;
          _deliveryState = _InvoiceDeliveryState.editingDraft;
        }
      });
    }
  }

  Future<void> _load() async {
    await _loadPaymentAccounts();
    try {
      final identityLoader = widget.identityLoader;
      if (identityLoader != null) {
        await identityLoader(_branchId, _tenantScope);
      } else {
        final identity = await IdentityApi(
          token: widget.token,
        ).load(_branchId, _tenantScope);
        BusinessIdentityStore.instance.save(identity);
      }
    } catch (_) {
      // The locally cached branch identity remains available while offline.
    }
    var products = await _catalog.read();
    try {
      final remote = await _catalogApi.list('products');
      products = await _catalog.mergeRemote(
        remote
            .where((item) => (item['name']?.toString() ?? '').isNotEmpty)
            .map(
              (item) => CatalogProduct(
                id: item['id']?.toString() ?? '',
                sku: item['sku']?.toString() ?? '',
                name: item['name'].toString(),
                purchasePrice:
                    ((item['purchase_price_minor'] as num?)?.toDouble() ?? 0) /
                    100,
                salePrice:
                    ((item['sale_price_minor'] as num?)?.toDouble() ?? 0) / 100,
                barcode: item['barcode']?.toString() ?? '',
                category: item['category_name']?.toString() ?? '',
                subcategory: item['subcategory_name']?.toString() ?? '',
                unitName: item['unit_name']?.toString() ?? '',
                hasPurchasePrice: item['purchase_price_minor'] != null,
                hasSalePrice: item['sale_price_minor'] != null,
              ),
            ),
      );
    } catch (_) {
      // Continue with the device catalogue while offline.
    }
    final customers = await CustomerStore(_tenantScope).read();
    var history = await _historyStore.read(_tenantScope, _branchId);
    // Pending submissions and server deltas are handled only by
    // RealtimeSyncCoordinator. Opening this screen must never replay an old
    // financial operation or download the complete invoice history.
    if (mounted) {
      _historyNotifier.value = List.unmodifiable(history);
      setState(() {
        _products = products;
        _customers = customers;
        _history = history;
      });
      await _refreshHistoryAndDelivery();
    }
  }

  Future<void> _loadPaymentAccounts() async {
    final generation = ++_paymentAccountLoadGeneration;
    final tenant = _tenantScope;
    final branch = _branchId;
    final token = widget.token;
    final roleCode = widget.roleCode;
    final permissions = List<String>.unmodifiable(widget.permissions);
    bool current() {
      if (!mounted || generation != _paymentAccountLoadGeneration) return false;
      final currentPermissions = widget.permissions.toSet();
      final capturedPermissions = permissions.toSet();
      return tenant == _tenantScope &&
          branch == _branchId &&
          token == widget.token &&
          roleCode == widget.roleCode &&
          capturedPermissions.length == currentPermissions.length &&
          capturedPermissions.containsAll(currentPermissions);
    }

    final accountCache = ChartAccountCache(
      tenant,
      branch,
      sessionToken: token,
      roleCode: roleCode,
      permissions: permissions,
    );
    final cached = await accountCache.read();
    if (!current()) return;
    _applyPaymentAccounts(cached);
    try {
      final canRead =
          roleCode == 'owner' || permissions.contains('invoices.read');
      final canCreate =
          roleCode == 'owner' || permissions.contains('invoices.create');
      if (canRead && canCreate) {
        final accounts =
            await (widget.chartAccountsLoader?.call(branch) ??
                ChartAccountsApi(token).list(branch));
        if (!current()) return;
        final paymentAccounts = accounts
            .where(
              (item) =>
                  item.active && item.allowPosting && item.isCashEquivalent,
            )
            .toList(growable: false);
        await accountCache.replace(paymentAccounts, isValid: current);
        if (!current()) return;
        _applyPaymentAccounts(paymentAccounts);
      }
    } catch (_) {
      // Cached accounts or the server's canonical cash default remain usable.
    }
  }

  void _applyPaymentAccounts(List<ChartAccount> paymentAccounts) {
    if (!mounted) return;
    setState(() {
      _paymentAccounts = paymentAccounts;
      if (!paymentAccounts.any((item) => item.code == _paymentAccountCode)) {
        _paymentAccountCode = paymentAccounts.firstOrNull?.code ?? '';
      }
      _paymentChannel = _channelForAccount(_paymentAccountCode);
    });
  }

  // Kept as the canonical server-delta mapper used by the sync integration.
  // ignore: unused_element
  InvoiceDocument _remoteDocument(Map<String, dynamic> value) {
    final items = (value['items'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => InvoiceLine(
            name: item['product_name_snapshot']?.toString() ?? '',
            quantity:
                ((item['quantity_milli'] as num?)?.toInt() ?? 1000) / 1000,
            unitPrice:
                ((item['unit_price_minor'] as num?)?.toDouble() ?? 0) / 100,
            productId: item['product_id']?.toString() ?? '',
            saleOptionId: item['sale_option_id']?.toString() ?? '',
            optionUnitCode: item['option_unit_code_snapshot']?.toString() ?? '',
            optionQuantity: double.tryParse(
              item['option_quantity_snapshot']?.toString() ?? '',
            ),
            optionMassG: double.tryParse(
              item['option_mass_g_snapshot']?.toString() ?? '',
            ),
            displayUnit:
                item['display_unit_snapshot']?.toString() ??
                item['option_unit_code_snapshot']?.toString() ??
                '',
            exactQuantityMilli: (item['quantity_milli'] as num?)?.toInt(),
            priceNumeratorMinor:
                (item['price_numerator_minor_snapshot'] as num?)?.toInt(),
            priceDenominator: (item['price_denominator_snapshot'] as num?)
                ?.toInt(),
            priceOverridden: item['price_overridden'] == true,
            lineDiscountMinor: (item['discount_minor'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
    return InvoiceDocument(
      number: value['number']?.toString() ?? '',
      customerName: value['customer_name']?.toString().trim().isNotEmpty == true
          ? value['customer_name'].toString()
          : 'عميل نقدي',
      customerPhone: value['customer_phone']?.toString() ?? '',
      customerId: value['contact_id']?.toString() ?? '',
      lines: items,
      currency: 'YER',
      employeeName:
          value['creator_display_name']?.toString() ?? widget.employeeName,
      branchLabel: 'الفرع ${_branches.indexOf(_branchId) + 1}',
      createdAt:
          DateTime.tryParse(value['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      paymentMode:
          value['payment_mode_at_issue']?.toString() ??
          (((value['initial_paid_minor'] as num?)?.toInt() ?? 0) >=
                  ((value['total_minor'] as num?)?.toInt() ?? 0)
              ? 'cash'
              : 'credit'),
      paidAmount:
          ((value['initial_paid_minor'] as num?)?.toDouble() ??
              (value['paid_minor'] as num?)?.toDouble() ??
              0) /
          100,
      discountAmount: items.isEmpty
          ? ((value['discount_minor'] as num?)?.toDouble() ?? 0) / 100
          : 0,
      amountTendered:
          ((value['amount_tendered_minor'] as num?)?.toDouble() ??
              (value['paid_minor'] as num?)?.toDouble() ??
              0) /
          100,
      paymentChannel: value['payment_channel']?.toString() ?? '',
      paymentAccountCode: value['payment_account_code']?.toString() ?? '',
      notes: value['notes']?.toString() ?? '',
      localOperationId: value['local_operation_id']?.toString() ?? '',
      serverInvoiceId: value['id']?.toString() ?? '',
      serverNumber: value['number']?.toString() ?? '',
    );
  }

  InvoiceDocument _readInvoice({
    String? number,
    DateTime? createdAt,
    bool? isDraft,
  }) {
    final gross = _lines.fold<double>(0, (sum, line) => sum + line.total);
    final discount = double.tryParse(_discount.text) ?? 0;
    final net = (gross - discount).clamp(0, double.infinity).toDouble();
    final enteredTendered = double.tryParse(_amountTendered.text) ?? 0;
    final effectiveTendered = _paymentMode == 'cash' && enteredTendered == 0
        ? net
        : enteredTendered;
    final viewModel = SalesInvoiceViewModel(
      number: number ?? 'INV-${DateTime.now().microsecondsSinceEpoch}',
      customerName: _customer.text.trim().isEmpty
          ? 'عميل نقدي'
          : _customer.text.trim(),
      customerPhone: _phone.text.trim(),
      customerId: _selectedCustomerId,
      lines: _lines
          .map(SalesInvoicePresentationAdapter.fromDomainLine)
          .toList(growable: false),
      currency: 'YER',
      employeeName: widget.employeeName,
      branchLabel: 'الفرع ${_branches.indexOf(_branchId) + 1}',
      createdAt: createdAt ?? DateTime.now(),
      paymentMode: _paymentMode,
      paidAmount: _paymentMode == 'credit'
          ? enteredTendered.clamp(0, net).toDouble()
          : net,
      discountAmount: discount,
      amountTendered: effectiveTendered,
      paymentChannel: _paymentChannel ?? '',
      paymentAccountCode: _paymentAccountCode,
      notes: _notes.text.trim(),
      localOperationId: _operationId,
      serverInvoiceId: _remoteInvoiceId,
      serverNumber: _remoteNumber,
      replacementInvoiceId: _replacementInvoiceId,
      restoreGenerationAtCreation: _operationRestoreGeneration,
      serverTotalMinor: null,
      currentPaidMinor: null,
      currentDueMinor: null,
      returnedMinor: 0,
      isDraft: isDraft ?? _explicitDraft,
      quarantineReason: '',
    );
    return SalesInvoicePresentationAdapter.toDomain(viewModel);
  }

  void _pickProduct(CatalogProduct product) {
    _applyPickedProduct(product);
    unawaited(_loadSaleOptions(product));
  }

  void _applyPickedProduct(CatalogProduct product) {
    setState(() {
      _pendingLineDiscountMinor = 0;
      _pendingWeightGramsMilli = null;
      _saleAmount.clear();
      _selectedProduct = product;
      _selectedSaleOption = null;
      _pendingPriceNumeratorMinor = null;
      _pendingPriceDenominator = null;
      _priceManuallyOverridden = false;
      _saleOptions = [];
      _item.text = product.name;
      _autoItemController?.text = product.name;
      _price.text = product.salePrice > 0
          ? product.salePrice.toStringAsFixed(2)
          : '';
    });
  }

  Future<void> _loadSaleOptions(
    CatalogProduct product, {
    String? selectedOptionId,
  }) async {
    if (product.id.isEmpty) return;
    final store = ProductSaleOptionStore(_tenantScope, _branchId);
    final cached = await store.readProduct(product.id);
    if (!mounted || _selectedProduct?.id != product.id) return;
    _replaceSaleOptions(cached, selectedOptionId: selectedOptionId);
    try {
      final values = await _catalogApi.saleOptions(
        product.id,
        branchId: _branchId,
      );
      if (!mounted || _selectedProduct?.id != product.id) return;
      await store.replaceProduct(product.id, values);
      if (!mounted || _selectedProduct?.id != product.id) return;
      _replaceSaleOptions(values, selectedOptionId: selectedOptionId);
    } catch (_) {
      // Sale options are an optional enhancement. When offline and no option
      // snapshot exists, keep the base product price usable without covering
      // the invoice actions with a transient error surface.
    }
  }

  void _replaceSaleOptions(
    List<ProductSaleOption> values, {
    String? selectedOptionId,
  }) {
    final targetId = selectedOptionId ?? _selectedSaleOption?.id;
    ProductSaleOption? selected;
    if (targetId != null) {
      for (final option in values) {
        if (option.id == targetId) {
          selected = option;
          break;
        }
      }
    }
    setState(() {
      _saleOptions = values;
      _selectedSaleOption = selected;
      if (!_priceManuallyOverridden) {
        _pendingPriceNumeratorMinor = selected?.priceNumeratorMinor;
        _pendingPriceDenominator = selected?.priceDenominator;
        if (selected != null) _price.text = _optionExactPriceText(selected);
      }
    });
  }

  void _selectSaleOption(ProductSaleOption? option) {
    setState(() {
      _selectedSaleOption = option;
      _pendingPriceNumeratorMinor = option?.priceNumeratorMinor;
      _pendingPriceDenominator = option?.priceDenominator;
      _priceManuallyOverridden = false;
      if (option != null) _price.text = _optionExactPriceText(option);
    });
  }

  void _selectSaleOptionId(String? id) {
    ProductSaleOption? selected;
    for (final option in _saleOptions) {
      if (option.id == id) {
        selected = option;
        break;
      }
    }
    _selectSaleOption(selected);
  }

  String _optionExactPriceText(ProductSaleOption option) {
    final exact = InvoiceLine(
      name: '',
      quantity: 1,
      unitPrice: option.price,
      priceNumeratorMinor: option.priceNumeratorMinor,
      priceDenominator: option.priceDenominator,
    ).displayUnitPrice;
    return exact.contains('/') ? option.price.toStringAsFixed(2) : exact;
  }

  bool get _hasCanonicalPendingPrice =>
      !_priceManuallyOverridden &&
      (_pendingPriceNumeratorMinor ?? 0) > 0 &&
      (_pendingPriceDenominator ?? 0) > 0;

  void _markPriceManuallyOverridden() {
    if (_selectedSaleOption == null && _pendingPriceNumeratorMinor == null) {
      return;
    }
    _priceManuallyOverridden = true;
    _pendingPriceNumeratorMinor = null;
    _pendingPriceDenominator = null;
  }

  Future<void> _scanProductBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const WaslQrScannerPage(
          title: 'مسح باركود الصنف',
          instruction: 'وجّه الكاميرا نحو باركود الصنف لإضافته إلى الفاتورة.',
        ),
      ),
    );
    if (code != null && mounted) await _acceptBarcode(code);
  }

  /// Works with a USB scanner (keyboard + Enter) and the camera scanner.
  Future<void> _acceptBarcode(String raw) async {
    final code = raw.trim();
    _barcodeInput.clear();
    if (code.isEmpty || _saving) return;
    CatalogProduct? match;
    final optionStore = ProductSaleOptionStore(_tenantScope, _branchId);
    final unitMatch = await optionStore.findByUnitBarcode(code);
    if (unitMatch != null) {
      for (final product in _products) {
        if (product.id == unitMatch.productId) {
          match = product;
          break;
        }
      }
    }
    for (final p in _products) {
      if (match != null) break;
      if (p.barcode.trim() == code || p.sku.trim() == code) {
        match = p;
        break;
      }
    }
    if (match == null) {
      _message('باركود غير معروف. سجّل الصنف أولاً ثم أعد المسح.');
      return;
    }
    _applyPickedProduct(match);
    if (unitMatch != null) {
      setState(() {
        _saleOptions = [unitMatch];
        _selectedSaleOption = unitMatch;
        _pendingPriceNumeratorMinor = unitMatch.priceNumeratorMinor;
        _pendingPriceDenominator = unitMatch.priceDenominator;
        _priceManuallyOverridden = false;
        _price.text = _optionExactPriceText(unitMatch);
        _quantity.text = '1';
      });
      await _loadSaleOptions(match, selectedOptionId: unitMatch.id);
      if (!mounted || _selectedProduct?.id != match.id) return;
      _quantityFocus.requestFocus();
      return;
    }
    unawaited(_loadSaleOptions(match));
    if (!match.hasSalePrice || match.salePrice <= 0) {
      _message('تم اختيار الصنف. حدد سعر البيع قبل إضافته.');
      return;
    }
    _quantity.text = '1';
    await _addLine();
    if (mounted && _barcodeFocus.canRequestFocus) _barcodeFocus.requestFocus();
  }

  /// Cashier enters the customer's total, not the physical weight.
  /// Product stock and price remain measured in the SKU's configured base unit.
  Future<void> _addWeightedAmountLine() async {
    final product = _selectedProduct;
    if (product == null || product.id.isEmpty) {
      _message('اختر صنفًا مسجلًا بالاسم أو الاختصار قبل البيع بالمبلغ.');
      return;
    }
    final option = _selectedSaleOption;
    if (!WeightedSaleMath.isMassUnit(product.unitName)) {
      _message('حدد وحدة مخزون الصنف كيلو أو جرام في بيانات الأصناف أولًا.');
      return;
    }
    if (option != null && (option.normalizedMassG ?? 0) <= 0) {
      _message(
        'البيع بالمبلغ يتطلب خيار وزن بالجرام أو الكيلو، لا كرتونًا أو قطعة.',
      );
      return;
    }
    final amountMinor = WeightedSaleMath.moneyMinor(_saleAmount.text);
    final exactNumerator = _pendingPriceNumeratorMinor;
    final exactDenominator = _pendingPriceDenominator;
    final parsedPriceMinor = WeightedSaleMath.moneyMinor(_price.text);
    final hasExactPrice = _hasCanonicalPendingPrice;
    if (amountMinor == null || (!hasExactPrice && parsedPriceMinor == null)) {
      _message('أدخل المبلغ المطلوب وسعر الكيلو أو الجرام بصورة صحيحة.');
      return;
    }
    try {
      final quote = WeightedSaleMath.quote(
        targetMinor: amountMinor,
        priceMinor:
            parsedPriceMinor ??
            (option == null ? 0 : (option.price * 100).round()),
        priceNumeratorMinor: hasExactPrice ? exactNumerator : null,
        priceDenominator: hasExactPrice ? exactDenominator : null,
        stockUnitName: product.unitName,
        optionMassGramsMillionths: option?.normalizedMassG == null
            ? null
            : (option!.normalizedMassG! * 1000000).round(),
      );
      if (!mounted) return;
      _quantity.text = quote.quantity.toStringAsFixed(3);
      _pendingLineDiscountMinor = quote.lineDiscountMinor;
      _pendingWeightGramsMilli = quote.gramsMilli;
      await _addLine();
      if (mounted && _item.text.trim().isEmpty) {
        _message(
          'تمت إضافة ${quote.grams.toStringAsFixed(3)} جرام '
          'بقيمة ${(amountMinor / 100).toStringAsFixed(2)} ريال.',
        );
      }
    } on ArgumentError catch (error) {
      _message(error.message?.toString() ?? 'الوزن أو المبلغ غير صالح.');
    } on StateError catch (error) {
      _message(error.message);
    }
  }

  Future<void> _addLine() async {
    final name = _item.text.trim();
    final quantity =
        double.tryParse(_quantity.text.trim().replaceAll(',', '.')) ?? 0;
    final quantityMilli = (quantity * 1000).round();
    final normalizedQuantity = quantityMilli / 1000;
    final price =
        double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? -1;
    final option = _selectedSaleOption;
    final hasExactPrice = _hasCanonicalPendingPrice;
    final hasManualOptionPrice = option != null && _priceManuallyOverridden;
    final manualPriceMinor = (price * 100).round();
    if (name.isEmpty ||
        quantityMilli < 1 ||
        !quantity.isFinite ||
        !price.isFinite ||
        (price <= 0 && !hasExactPrice)) {
      _message('أدخل الصنف والكمية وسعر البيع بصورة صحيحة.');
      return;
    }
    if (option != null && !hasExactPrice && !_canEdit) {
      _message('تعديل سعر خيار البيع يتطلب صلاحية تعديل الفواتير.');
      return;
    }
    var known = _selectedProduct;
    if (known == null) {
      for (final product in _products) {
        if (product.name.toLowerCase() == name.toLowerCase()) {
          known = product;
          break;
        }
      }
    }
    var lineProduct = known;
    lineProduct ??= await _catalog.save(
      CatalogProduct(
        name: name,
        purchasePrice: 0,
        salePrice: price,
        barcode: '',
        hasPurchasePrice: false,
      ),
    );
    final resolvedProduct = lineProduct;
    setState(() {
      final editedIndex = _editingLineIndex;
      final editedLine = InvoiceLine(
        name: name,
        quantity: normalizedQuantity,
        unitPrice: price,
        productId: resolvedProduct.id,
        saleOptionId: option?.id ?? '',
        optionUnitCode: option?.unitCode ?? '',
        optionQuantity: option?.quantity,
        optionMassG: option?.normalizedMassG,
        displayUnit: _displayUnitLabel(
          option?.unitCode ?? resolvedProduct.unitName,
        ),
        exactQuantityMilli: quantityMilli,
        priceNumeratorMinor: hasManualOptionPrice
            ? manualPriceMinor
            : (hasExactPrice ? _pendingPriceNumeratorMinor : null),
        priceDenominator: hasManualOptionPrice
            ? 1
            : (hasExactPrice ? _pendingPriceDenominator : null),
        priceOverridden: hasManualOptionPrice,
        lineDiscountMinor: _pendingLineDiscountMinor,
        weightGramsMilli: _pendingWeightGramsMilli,
        pendingCatalogSync: resolvedProduct.id.isEmpty,
      );
      if (editedIndex != null && editedIndex < _lines.length) {
        _lines[editedIndex] = editedLine;
      } else {
        final matchIndex = _lines.indexWhere(
          (line) =>
              line.name.trim().toLowerCase() == name.toLowerCase() &&
              line.productId == resolvedProduct.id &&
              line.saleOptionId == (option?.id ?? '') &&
              line.unitPrice == price &&
              line.priceNumeratorMinor ==
                  (hasManualOptionPrice
                      ? manualPriceMinor
                      : (hasExactPrice ? _pendingPriceNumeratorMinor : null)) &&
              line.priceDenominator ==
                  (hasManualOptionPrice
                      ? 1
                      : (hasExactPrice ? _pendingPriceDenominator : null)) &&
              line.priceOverridden == hasManualOptionPrice &&
              line.lineDiscountMinor == _pendingLineDiscountMinor,
        );
        if (matchIndex >= 0) {
          final old = _lines[matchIndex];
          _lines[matchIndex] = InvoiceLine(
            name: old.name,
            quantity:
                ((old.quantity + normalizedQuantity) * 1000).round() / 1000,
            unitPrice: old.unitPrice,
            productId: old.productId,
            saleOptionId: old.saleOptionId,
            optionUnitCode: old.optionUnitCode,
            optionQuantity: old.optionQuantity,
            optionMassG: old.optionMassG,
            displayUnit: old.displayUnit,
            exactQuantityMilli:
                (old.exactQuantityMilli ?? (old.quantity * 1000).round()) +
                quantityMilli,
            priceNumeratorMinor: old.priceNumeratorMinor,
            priceDenominator: old.priceDenominator,
            priceOverridden: old.priceOverridden,
            lineDiscountMinor:
                old.lineDiscountMinor + _pendingLineDiscountMinor,
            weightGramsMilli:
                (old.weightGramsMilli ?? 0) + (_pendingWeightGramsMilli ?? 0),
            pendingCatalogSync:
                old.pendingCatalogSync || resolvedProduct.id.isEmpty,
          );
        } else {
          _lines.add(editedLine);
        }
      }
      _editingLineIndex = null;
      _item.clear();
      _autoItemController?.clear();
      _quantity.text = '1';
      _price.clear();
      _saleAmount.clear();
      _pendingLineDiscountMinor = 0;
      _pendingWeightGramsMilli = null;
      _selectedProduct = null;
      _selectedSaleOption = null;
      _pendingPriceNumeratorMinor = null;
      _pendingPriceDenominator = null;
      _priceManuallyOverridden = false;
      _saleOptions = [];
      _invoice = _readInvoice(
        number: _invoice.number,
        createdAt: _invoice.createdAt,
      );
    });
    await _refreshCachedCatalog();
  }

  String _displayUnitLabel(String unit) =>
      const <String, String>{
        'gram': 'جرام',
        'kilogram': 'كيلو',
        'milligram': 'ملليجرام',
        'piece': 'قطعة',
        'item': 'حبة',
        'carton': 'كرتون',
        'box': 'صندوق',
        'pack': 'باكت',
        'liter': 'لتر',
        'milliliter': 'ملليلتر',
      }[unit.trim().toLowerCase()] ??
      unit;

  void _editLine(int index) {
    final line = _lines[index];
    CatalogProduct? product;
    for (final candidate in _products) {
      if (candidate.id == line.productId || candidate.name == line.name) {
        product = candidate;
        break;
      }
    }
    setState(() {
      _editingLineIndex = index;
      _selectedProduct = product;
      _selectedSaleOption = null;
      _pendingPriceNumeratorMinor = line.priceNumeratorMinor;
      _pendingPriceDenominator = line.priceDenominator;
      _priceManuallyOverridden = line.priceOverridden;
      _item.text = line.name;
      _autoItemController?.text = line.name;
      _quantity.text = line.quantity.toString();
      _price.text = line.unitPrice.toStringAsFixed(2);
      _pendingLineDiscountMinor = line.lineDiscountMinor;
      _pendingWeightGramsMilli = line.weightGramsMilli;
      _saleAmount.text = line.lineDiscountMinor > 0
          ? line.total.toStringAsFixed(2)
          : '';
    });
    if (product != null) {
      unawaited(_loadSaleOptions(product, selectedOptionId: line.saleOptionId));
    }
    _quantityFocus.requestFocus();
  }

  Future<void> _addLineFromKeyboard() async {
    final previousCount = _lines.length;
    await _addLine();
    if (!mounted) return;
    if (_lines.length >= previousCount && _item.text.trim().isEmpty) {
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _editSaleOption({ProductSaleOption? existing}) async {
    final product = _selectedProduct;
    if (product == null || product.id.isEmpty) {
      _message('اختر صنفًا محفوظًا أولًا.');
      return;
    }
    var unit = existing?.unitCode ?? 'gram';
    final amount = TextEditingController(
      text: existing?.quantity.toString() ?? '100',
    );
    final price = TextEditingController(
      text: existing?.price.toStringAsFixed(2) ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'إضافة وزن أو وحدة بيع' : 'تعديل سعر خيار البيع',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'الوحدة'),
                items:
                    const {
                          'gram': 'جرام',
                          'kilogram': 'كيلو',
                          'piece': 'قطعة',
                          'item': 'حبة',
                          'bundle': 'شدة',
                          'box': 'صندوق',
                          'carton': 'كرتون',
                          'bag': 'كيس',
                          'pack': 'باكت',
                          'liter': 'لتر',
                          'milliliter': 'ملليلتر',
                          'dozen': 'درزن',
                        }.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                onChanged: existing == null
                    ? (value) => setDialogState(() => unit = value ?? unit)
                    : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                enabled: existing == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [latinDigitFormatter],
                decoration: const InputDecoration(labelText: 'الوزن أو العدد'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [latinDigitFormatter],
                decoration: const InputDecoration(
                  labelText: 'سعر البيع بالريال اليمني',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final amountValue = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    final priceValue = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    if (amountValue <= 0 || priceValue <= 0) {
      _message('أدخل وزنًا أو عددًا وسعرًا أكبر من صفر.');
      return;
    }
    try {
      final api = CatalogSyncApi(token: widget.token);
      if (existing == null) {
        await api.createSaleOption(
          product.id,
          branchId: _branchId,
          unitCode: unit,
          quantity: amountValue,
          price: priceValue,
        );
      } else {
        await api.updateSaleOption(product.id, existing, priceValue);
      }
      await _loadSaleOptions(product);
      _message('تم حفظ خيار البيع ومزامنته.');
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> _saveDraft({bool notify = true}) async {
    if (_documentLocked || _saving || _finalizing) return false;
    if (_lines.isEmpty) {
      _message('أضف صنفاً واحداً على الأقل.');
      return false;
    }
    setState(() => _saving = true);
    try {
      final draft = _readInvoice(
        number: _invoice.number,
        createdAt: _invoice.createdAt,
        isDraft: true,
      );
      await _historyStore.save(_tenantScope, _branchId, draft);
      await _persistCustomer();
      final savedHistory = await _historyStore.read(_tenantScope, _branchId);
      if (mounted) {
        _historyNotifier.value = List.unmodifiable(savedHistory);
        setState(() {
          _invoice = draft;
          _explicitDraft = true;
          _deliveryState = _InvoiceDeliveryState.editingDraft;
          _history = savedHistory;
        });
      }
      unawaited(_prepareWhatsappImage(draft));
      if (notify) _message('تم حفظ المسودة على هذا الجهاز.');
      return true;
    } catch (_) {
      _message(
        'تعذر حفظ الفاتورة محليًا؛ لا تغلق النموذج قبل المحاولة مجددًا.',
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validateFinalInvoice(InvoiceDocument candidate) {
    if (candidate.lines.isEmpty) {
      _message('أضف صنفاً واحداً على الأقل.');
      return false;
    }
    if (candidate.lines.any((line) => line.pendingCatalogSync)) {
      _message(
        'يوجد صنف مخزني بانتظار المزامنة. يمكن حفظه كمسودة فقط حتى يحصل على معرف الخادم.',
      );
      return false;
    }
    if (_paymentMode == 'credit' &&
        (_customer.text.trim().isEmpty ||
            (_customer.text.trim() == _walkInCustomerName &&
                _selectedCustomerId.isEmpty))) {
      _message(
        'الفاتورة الآجلة تتطلب اختيار عميل مسجل أو كتابة اسم عميل جديد.',
      );
      return false;
    }
    if (_paymentMode == 'cash' &&
        _paymentAccountCode.isEmpty &&
        _paymentChannel != 'cash') {
      _message('اختر الصندوق أو البنك أو المحفظة التي استلمت المبلغ.');
      return false;
    }
    if (candidate.discountAmount < 0 ||
        candidate.discountAmount > candidate.subtotal) {
      _message('الخصم يجب أن يكون بين صفر وإجمالي الأصناف.');
      return false;
    }
    if (_paymentMode == 'cash' &&
        candidate.amountTendered > 0 &&
        candidate.amountTendered < candidate.total) {
      _message('المبلغ المستلم لا يمكن أن يقل عن صافي الفاتورة النقدية.');
      return false;
    }
    return true;
  }

  Future<void> _finalizeInvoice() async {
    if (_finalizing || _saving || _documentLocked) return;
    if (!_canFinalizeCurrent) {
      _message('لا تملك صلاحية حفظ أو تعديل فاتورة نهائية.');
      return;
    }
    _finalizing = true;
    if (mounted) {
      setState(() => _deliveryState = _InvoiceDeliveryState.finalizing);
    }
    var enqueued = false;
    final capturedTenant = _tenantScope;
    final capturedBranch = _branchId;
    final capturedOperation = _operationId;
    final capturedGeneration = _currentRestoreGeneration;
    try {
      var finalInvoice = _readInvoice(
        number: _invoice.number,
        createdAt: _invoice.createdAt,
        isDraft: false,
      );
      if (!_validateFinalInvoice(finalInvoice)) {
        if (mounted) {
          setState(() => _deliveryState = _InvoiceDeliveryState.editingDraft);
        }
        return;
      }
      final restoreEpoch = _currentRestoreEpoch;
      if (finalInvoice.restoreGenerationAtCreation != capturedGeneration &&
          restoreEpoch != null &&
          finalInvoice.createdAt.toUtc().isAfter(restoreEpoch.toUtc())) {
        finalInvoice = finalInvoice.rebasedToRestoreGeneration(
          capturedGeneration,
        );
      }
      final restoreDecision = await RestoreSubmissionPolicy.guardInvoice(
        tenantId: capturedTenant,
        invoice: finalInvoice,
        currentGeneration: capturedGeneration,
        restoreEpoch: _currentRestoreEpoch,
      );
      if (!restoreDecision.allowed) {
        final quarantined = finalInvoice.quarantined(restoreDecision.reason);
        await _historyStore.save(capturedTenant, capturedBranch, quarantined);
        if (mounted && _operationId == capturedOperation) {
          setState(() {
            _invoice = quarantined;
            _explicitDraft = false;
            _deliveryState = _InvoiceDeliveryState.quarantined;
          });
        }
        _message('حُجزت الفاتورة للمراجعة بسبب استعادة أحدث للبيانات.');
        return;
      }

      final api = _accountingApi;
      final request = await api.prepareInvoiceRequest(
        branchId: capturedBranch,
        invoice: finalInvoice,
        restoreGeneration: finalInvoice.restoreGenerationAtCreation,
      );
      final outbox = _salesOutbox;
      await outbox.enqueue(request, snapshot: finalInvoice);
      enqueued = true;
      await _historyStore.save(capturedTenant, capturedBranch, finalInvoice);
      await _persistCustomer();
      if (mounted && _operationId == capturedOperation) {
        setState(() {
          _invoice = finalInvoice;
          _explicitDraft = false;
          _deliveryState = _InvoiceDeliveryState.queued;
        });
      }

      SalesInvoiceFlushResult? flushResult;
      if (AccountingApi.enabled) {
        flushResult = await outbox.flush(
          api: api,
          currentRestoreGeneration: capturedGeneration,
          restoreEpoch: _currentRestoreEpoch,
          isResponseValid: () =>
              mounted &&
              _tenantScope == capturedTenant &&
              _branchId == capturedBranch &&
              _operationId == capturedOperation &&
              _currentRestoreGeneration == capturedGeneration,
          canSend: (entry) => canSendSalesInvoiceEntry(
            entry: entry,
            roleCode: widget.roleCode,
            permissions: widget.permissions,
          ),
        );
      }
      await (widget.synchronizeNow?.call() ??
          RealtimeSyncCoordinator.instance.synchronizeNow());
      await _refreshHistoryAndDelivery();
      if (!mounted || _operationId != capturedOperation) return;
      if (flushResult?.quarantined != 0 &&
          _deliveryState != _InvoiceDeliveryState.posted) {
        setState(() => _deliveryState = _InvoiceDeliveryState.quarantined);
      }
      switch (_deliveryState) {
        case _InvoiceDeliveryState.posted:
          _message('تم حفظ الفاتورة وترحيلها محاسبيًا بنجاح.');
        case _InvoiceDeliveryState.needsReview:
          _message('تم حفظ الفاتورة لكنها تحتاج مراجعة قبل اعتمادها.');
        case _InvoiceDeliveryState.queued:
          _message(
            'تم حفظ الفاتورة بأمان في قائمة المزامنة وستُرسل تلقائيًا عند توفر الاتصال.',
          );
        case _InvoiceDeliveryState.quarantined:
          _message('حُجزت الفاتورة للمراجعة ولم تُرسل.');
        case _InvoiceDeliveryState.editingDraft:
        case _InvoiceDeliveryState.finalizing:
          break;
      }
    } catch (error) {
      if (mounted && _operationId == capturedOperation) {
        setState(
          () => _deliveryState = enqueued
              ? _InvoiceDeliveryState.queued
              : _InvoiceDeliveryState.editingDraft,
        );
      }
      _message(
        enqueued
            ? 'تم حفظ الفاتورة بأمان في قائمة المزامنة وستُرسل تلقائيًا عند توفر الاتصال.'
            : error.toString().replaceFirst('AccountingApiError: ', ''),
      );
    } finally {
      _finalizing = false;
      if (mounted && _deliveryState == _InvoiceDeliveryState.finalizing) {
        setState(() => _deliveryState = _InvoiceDeliveryState.editingDraft);
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _persistCustomer() async {
    if (_paymentMode == 'credit' || _selectedCustomerId.isNotEmpty) {
      await CustomerStore(_tenantScope).save(_customer.text, _phone.text);
    }
  }

  void _openSaved(InvoiceDocument value) {
    _operationId = value.localOperationId.isEmpty
        ? const Uuid().v4()
        : value.localOperationId;
    _remoteInvoiceId = value.serverInvoiceId;
    _remoteNumber = value.serverNumber;
    _replacementInvoiceId = value.replacementInvoiceId;
    _operationRestoreGeneration = value.restoreGenerationAtCreation;
    _customer.text = value.customerName;
    _autoCustomerController?.text = value.customerName;
    _phone.text = value.customerPhone;
    _selectedCustomerId = value.customerId;
    _notes.text = value.notes;
    _discount.text = value.discountAmount.toStringAsFixed(2);
    _amountTendered.text = value.amountTendered.toStringAsFixed(2);
    _paymentChannel = value.paymentChannel.isEmpty
        ? null
        : value.paymentChannel;
    _paymentAccountCode = value.paymentAccountCode;
    final queuedState = _outboxStates[value.localOperationId];
    setState(() {
      _explicitDraft = value.isDraft;
      _deliveryState = value.isQuarantined
          ? _InvoiceDeliveryState.quarantined
          : value.postedToServer
          ? _InvoiceDeliveryState.posted
          : queuedState == SalesInvoiceOutboxState.needsReview
          ? _InvoiceDeliveryState.needsReview
          : queuedState == SalesInvoiceOutboxState.queued
          ? _InvoiceDeliveryState.queued
          : _InvoiceDeliveryState.editingDraft;
      _paymentMode = value.paymentMode;
      _lines
        ..clear()
        ..addAll(value.lines);
      _invoice = value;
    });
  }

  Future<bool> _confirmManage(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editSaved(InvoiceDocument value) async {
    if (value.isQuarantined) {
      await _salesOutbox.discardLocal(value.localOperationId);
      await QuarantinedOperationStore(
        _tenantScope,
      ).remove(value.localOperationId);
    }
    if (!value.postedToServer &&
        !value.isDraft &&
        await _salesOutbox.contains(value.localOperationId)) {
      _message(
        'الفاتورة النهائية غير قابلة للتعديل أثناء المزامنة أو المراجعة.',
      );
      return;
    }
    if (value.postedToServer) {
      if (!_canEdit) {
        _message('تعديل الفاتورة المرحّلة متاح للمسؤول فقط.');
        return;
      }
      if (!await _confirmManage(
        'تعديل فاتورة مرحّلة',
        'سيُلغي النظام القيد القديم محاسبيًا، ثم يحفظ التعديل كفاتورة جديدة عند الضغط على حفظ.',
      )) {
        return;
      }
      // Keep the original posted invoice intact while the user edits. The
      // server replaces it atomically only after the new invoice posts.
      _replacementInvoiceId = value.serverInvoiceId;
    } else {
      _replacementInvoiceId = value.replacementInvoiceId;
    }
    _customer.text = value.customerName == 'عميل نقدي'
        ? ''
        : value.customerName;
    _autoCustomerController?.text = _customer.text;
    _phone.text = value.customerPhone;
    _selectedCustomerId = value.customerId;
    _notes.text = value.notes;
    _discount.text = value.discountAmount.toStringAsFixed(2);
    _amountTendered.text = value.amountTendered.toStringAsFixed(2);
    _paymentChannel = value.paymentChannel.isEmpty
        ? (value.paymentMode == 'cash' ? 'cash' : null)
        : value.paymentChannel;
    _paymentAccountCode = value.paymentAccountCode;
    setState(() {
      _paymentMode = value.paymentMode;
      _operationId = value.postedToServer || value.localOperationId.isEmpty
          ? const Uuid().v4()
          : value.localOperationId;
      _operationRestoreGeneration = _currentRestoreGeneration;
      _remoteInvoiceId = '';
      _explicitDraft = false;
      _deliveryState = _InvoiceDeliveryState.editingDraft;
      _remoteNumber = '';
      _lines
        ..clear()
        ..addAll(value.lines);
      _invoice = _readInvoice(
        number: value.postedToServer ? null : value.number,
        createdAt: value.postedToServer ? null : value.createdAt,
      );
    });
    await _refreshHistoryOnly();
    _message('تم فتح الفاتورة للتعديل. اضغط حفظ بعد الانتهاء.');
  }

  Future<void> _deleteSaved(InvoiceDocument value) async {
    if (!value.postedToServer &&
        !value.isDraft &&
        await _salesOutbox.contains(value.localOperationId)) {
      _message('لا يمكن حذف فاتورة نهائية ما زالت في المزامنة أو المراجعة.');
      return;
    }
    if (!_canDelete) {
      _message('حذف الفواتير متاح للمسؤول فقط.');
      return;
    }
    if (!await _confirmManage(
      'حذف الفاتورة',
      value.postedToServer
          ? 'سيتم حذف الفاتورة وقيدها وحركة المخزون المرتبطة بها، مع بقاء سجل التدقيق فقط.'
          : 'سيتم حذف الفاتورة المحفوظة من هذا الجهاز.',
    )) {
      return;
    }
    try {
      if (value.postedToServer) {
        final accountingApi = AccountingApi(token: widget.token);
        await accountingApi.voidInvoice(
          invoiceId: value.serverInvoiceId,
          reason: 'حذف الفاتورة بواسطة المسؤول',
        );
      } else if (value.isQuarantined) {
        await _salesOutbox.discardLocal(value.localOperationId);
        await QuarantinedOperationStore(
          _tenantScope,
        ).remove(value.localOperationId);
      }
      await _historyStore.remove(_tenantScope, _branchId, value.number);
      if (_invoice.number == value.number) _startNewInvoice();
      await _refreshHistoryOnly();
      _message('تم حذف الفاتورة وكل آثارها المرتبطة.');
    } catch (error) {
      _message(error.toString());
    }
  }

  void _showHistory() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .82,
        child: ValueListenableBuilder<List<InvoiceDocument>>(
          valueListenable: _historyNotifier,
          builder: (context, documents, child) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: _historySection(
              sheetContext: sheetContext,
              documents: documents,
            ),
          ),
        ),
      ),
    ),
  );

  Future<Uint8List> _pdfFor(InvoiceDocument invoice) => buildInvoicePdf(
    invoice: invoice,
    profile: BusinessIdentityStore.instance.profileFor(
      _branchId,
      _tenantScope,
      displayName: widget.tenantName,
    ),
  );

  Future<Uint8List> _pdf() => _pdfFor(_invoice);

  Future<Uint8List> _thermalPdfFor(InvoiceDocument invoice) =>
      buildThermalInvoicePdf(
        invoice: invoice,
        profile: BusinessIdentityStore.instance.profileFor(
          _branchId,
          _tenantScope,
          displayName: widget.tenantName,
        ),
      );

  Future<Uint8List> _thermalPdf() => _thermalPdfFor(_invoice);

  Future<void> _previewThermal(InvoiceDocument invoice) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'فاتورة مبسطة ${compactDocumentNumber(invoice.displayNumber)}',
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              tooltip: 'رجوع',
              icon: const Icon(Icons.close),
            ),
          ),
          body: PdfPreview(
            build: (_) => _thermalPdfFor(invoice),
            allowPrinting: true,
            allowSharing: true,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _whatsappImageFor(InvoiceDocument invoice) async {
    final pages = await Printing.raster(
      await _pdfFor(invoice),
      pages: const [0],
      dpi: 180,
    ).toList();
    if (pages.isEmpty) {
      throw StateError('تعذر إنشاء صورة الفاتورة.');
    }
    return pages.first.toPng();
  }

  String _invoiceCacheKey(InvoiceDocument invoice) =>
      invoice.localOperationId.isEmpty
      ? invoice.number.toString()
      : invoice.localOperationId;

  Future<Uint8List> _prepareWhatsappImage(InvoiceDocument invoice) =>
      _whatsappImageCache.putIfAbsent(
        _invoiceCacheKey(invoice),
        () => _whatsappImageFor(invoice),
      );

  Future<void> _printThermal() async {
    await PdfExportService.print(
      bytes: await _thermalPdf(),
      filename: 'receipt-${_invoice.displayNumber}.pdf',
    );
  }

  Future<void> _share() async {
    if (!_documentLocked && !await _saveDraft(notify: false)) return;
    await PdfExportService.save(
      bytes: await _pdf(),
      filename: 'invoice-${_invoice.displayNumber}.pdf',
    );
  }

  // The invoice editor remains clean. No PDF is rendered until requested.
  Future<void> _previewInvoice() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'معاينة الفاتورة ${compactDocumentNumber(_invoice.displayNumber)}',
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(dialogContext),
              tooltip: 'رجوع',
              icon: const Icon(Icons.close),
            ),
          ),
          body: PdfPreview(
            build: (_) => _pdf(),
            allowPrinting: true,
            allowSharing: true,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  void _startNewInvoice() {
    if (_finalizing || _saving) return;
    _saleAmount.clear();
    _pendingLineDiscountMinor = 0;
    _pendingWeightGramsMilli = null;
    setState(() {
      _operationId = const Uuid().v4();
      _operationRestoreGeneration = _currentRestoreGeneration;
      _remoteInvoiceId = '';
      _explicitDraft = false;
      _deliveryState = _InvoiceDeliveryState.editingDraft;
      _whatsappImageCache.clear();
      _remoteNumber = '';
      _replacementInvoiceId = '';
      _lines.clear();
      _editingLineIndex = null;
      _customer.text = _walkInCustomerName;
      _selectedCustomerId = '';
      _autoCustomerController?.text = _walkInCustomerName;
      _phone.clear();
      _paymentMode = 'cash';
      _notes.clear();
      _discount.text = '0';
      _amountTendered.text = '0';
      _paymentChannel = 'cash';
      _paymentAccountCode = _paymentAccounts.firstOrNull?.code ?? '';
      _item.clear();
      _autoItemController?.clear();
      _quantity.text = '1';
      _price.clear();
      _selectedProduct = null;
      _selectedSaleOption = null;
      _pendingPriceNumeratorMinor = null;
      _pendingPriceDenominator = null;
      _priceManuallyOverridden = false;
      _saleOptions = [];
      _invoice = _readInvoice();
    });
  }

  Future<void> _sendInvoiceWhatsapp(InvoiceDocument invoice) async {
    final invoiceKey = invoice.localOperationId.isEmpty
        ? invoice.number.toString()
        : invoice.localOperationId;
    if (_sendingWhatsapp ||
        _whatsappSentInvoices.contains(invoiceKey) ||
        invoice.lines.isEmpty) {
      return;
    }
    var number = invoice.customerPhone.replaceAll(RegExp('[^0-9]'), '');
    if (number.startsWith('967')) number = number.substring(3);
    if (number.startsWith('0')) number = number.substring(1);
    if (!RegExp(r'^(70|71|73|77|78)[0-9]{7}$').hasMatch(number)) {
      _message('أدخل رقم جوال يمني صحيحاً.');
      return;
    }
    try {
      setState(() => _sendingWhatsapp = true);
      final result = await WhatsappApi(token: widget.token).sendInvoice(
        branchId: _branchId,
        localNumber: number,
        caption:
            'فاتورتكم رقم ${invoice.displayNumber} - الإجمالي ${invoice.total.toStringAsFixed(2)} YER',
        filename: 'invoice-${invoice.displayNumber}.png',
        image: await _prepareWhatsappImage(invoice),
        idempotencyKey: invoiceKey,
      );
      final status = result['status']?.toString();
      final messageId = result['message_id']?.toString() ?? '';
      if (status == 'sent' && messageId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _whatsappSentInvoices.add(invoiceKey);
          });
        }
        _message(
          'أكد الخادم إرسال الفاتورة عبر واتساب. رقم الرسالة: $messageId',
        );
      } else if (status == 'queued') {
        _message('استلم الخادم الفاتورة وهي الآن في طابور إرسال واتساب.');
      } else {
        throw Exception('لم يؤكد خادم واتساب إرسال الفاتورة.');
      }
    } catch (e) {
      _message(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sendingWhatsapp = false);
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _historyNotifier.dispose();
    for (final c in [
      _customer,
      _phone,
      _item,
      _quantity,
      _price,
      _saleAmount,
      _discount,
      _amountTendered,
      _notes,
      _barcodeInput,
    ]) {
      c.dispose();
    }
    _barcodeFocus.dispose();
    _quantityFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  void _showReturns() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReturnWorkspacePage(
          token: widget.token,
          tenantId: widget.tenantId ?? widget.tenantName,
          branchIds: widget.branchIds,
          roleCode: widget.roleCode,
          permissions: widget.permissions,
          purchase: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!_documentLocked) unawaited(_saveDraft());
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (!_documentLocked && _canFinalizeCurrent) {
            unawaited(_finalizeInvoice());
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          if (_invoice.lines.isNotEmpty) unawaited(_printThermal());
        },
        const SingleActivator(LogicalKeyboardKey.f2): _handleF2,
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (!_documentLocked) _barcodeFocus.requestFocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المبيعات'),
            toolbarHeight: 0,
            actions: [
              IconButton(
                onPressed: _showReturns,
                tooltip: 'مرتجعات المبيعات',
                icon: const Icon(Icons.keyboard_return),
              ),
              IconButton(
                onPressed: _finalizing ? null : _startNewInvoice,
                tooltip: 'فاتورة جديدة',
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                key: const Key('invoice-history-open'),
                onPressed: _showHistory,
                tooltip: 'الفواتير السابقة',
                icon: const Icon(Icons.history),
              ),
            ],
          ),
          body: SafeArea(
            child: NineSoftResponsiveBody(
              child: ListView(
                key: const ValueKey('invoice-document-editor'),
                children: [_editor()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleF2() {
    if (_documentLocked) return;
    if (_item.text.trim().isEmpty) {
      _autoItemFocus?.requestFocus();
      return;
    }
    unawaited(_addLineFromKeyboard());
  }

  // Kept as the full-document action surface used by the forthcoming
  // read-only invoice route; the entry page now uses the compact summary.
  // ignore: unused_element
  Widget _postedSummary() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF25886E),
            size: 58,
          ),
          const SizedBox(height: 12),
          Text(
            'فاتورة مرحّلة ${compactDocumentNumber(_invoice.displayNumber)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'هذه الفاتورة أصبحت مُرحلة للخادم. التعديلات المالية اللاحقة تحتاج مستند تصحيح أو عكس محاسبي، وليس تعديل السجل المحلي.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _previewInvoice,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('عرض وطباعة الفاتورة'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _printThermal,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('طباعة فاتورة مبسطة'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('مشاركة PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WaslPage(
                  token: widget.token,
                  tenantName: widget.tenantName,
                  branchIds: [_branchId],
                  invoiceNumber: _invoice.displayNumber,
                ),
              ),
            ),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('مطابقة بتحويل بنكي'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _startNewInvoice,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('فاتورة جديدة'),
          ),
          if (_canEdit || _canDelete) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editSaved(_invoice),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteSaved(_invoice),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  _InvoiceDeliveryState _historyDelivery(InvoiceDocument invoice) {
    if (invoice.isQuarantined) return _InvoiceDeliveryState.quarantined;
    if (invoice.postedToServer) return _InvoiceDeliveryState.posted;
    if (invoice.isDraft) return _InvoiceDeliveryState.editingDraft;
    return _outboxStates[invoice.localOperationId] ==
            SalesInvoiceOutboxState.needsReview
        ? _InvoiceDeliveryState.needsReview
        : _InvoiceDeliveryState.queued;
  }

  String _historyStatus(InvoiceDocument invoice) =>
      switch (_historyDelivery(invoice)) {
        _InvoiceDeliveryState.editingDraft => 'مسودة',
        _InvoiceDeliveryState.queued => 'بانتظار المزامنة',
        _InvoiceDeliveryState.needsReview => 'تحتاج مراجعة',
        _InvoiceDeliveryState.posted => 'متزامنة',
        _InvoiceDeliveryState.quarantined =>
          'متوقفة مؤقتًا — يمكن تعديلها أو حذفها',
        _InvoiceDeliveryState.finalizing => 'جارٍ الحفظ',
      };

  Widget _historySection({
    BuildContext? sheetContext,
    List<InvoiceDocument>? documents,
  }) {
    final visibleHistory = documents ?? _history;
    return Card(
      key: sheetContext == null
          ? null
          : const Key('invoice-history-modal-content'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF25886E)),
                const SizedBox(width: 8),
                Text(
                  'الفواتير السابقة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: _load,
                  tooltip: 'تحديث ومزامنة',
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            const Text(
              'تظهر هنا الفواتير المحفوظة على جميع الأجهزة بعد مزامنتها مع الخادم.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if (visibleHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('لا توجد فواتير محفوظة بعد.')),
              )
            else
              for (final invoice in visibleHistory)
                Container(
                  key: Key(
                    'invoice-history-row-${invoice.localOperationId.isEmpty ? invoice.number : invoice.localOperationId}',
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAF9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDCE9E4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            switch (_historyDelivery(invoice)) {
                              _InvoiceDeliveryState.editingDraft =>
                                Icons.edit_note_rounded,
                              _InvoiceDeliveryState.queued =>
                                Icons.cloud_upload_outlined,
                              _InvoiceDeliveryState.needsReview =>
                                Icons.warning_amber_rounded,
                              _ => Icons.cloud_done_outlined,
                            },
                            color:
                                _historyDelivery(invoice) ==
                                    _InvoiceDeliveryState.posted
                                ? const Color(0xFF25886E)
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${compactDocumentNumber(invoice.displayNumber)} • ${invoice.customerName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(invoice.currentPaymentLabel),
                            avatar: Icon(
                              invoice.currentDueAmount > 0
                                  ? Icons.schedule_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${invoice.total.toStringAsFixed(2)} YER',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${invoice.createdAt.toLocal().toString().split(' ').first} • ${invoice.lines.length} أصناف • مدفوع ${invoice.currentPaidAmount.toStringAsFixed(2)} • متبقٍ ${invoice.currentDueAmount.toStringAsFixed(2)} • مرتجع ${invoice.returnedAmount.toStringAsFixed(2)} • ${_historyStatus(invoice)}',
                        key: Key(
                          'invoice-history-status-${invoice.localOperationId.isEmpty ? invoice.number : invoice.localOperationId}',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              if (sheetContext != null) {
                                Navigator.pop(sheetContext);
                              }
                              _openSaved(invoice);
                            },
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('عرض'),
                          ),
                          TextButton.icon(
                            onPressed: () => _previewThermal(invoice),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('فاتورة مبسطة'),
                          ),
                          TextButton.icon(
                            onPressed:
                                _sendingWhatsapp ||
                                    _whatsappSentInvoices.contains(
                                      invoice.localOperationId.isEmpty
                                          ? invoice.number.toString()
                                          : invoice.localOperationId,
                                    )
                                ? null
                                : () => _sendInvoiceWhatsapp(invoice),
                            icon: const Icon(Icons.chat_outlined),
                            label: Text(
                              _whatsappSentInvoices.contains(
                                    invoice.localOperationId.isEmpty
                                        ? invoice.number.toString()
                                        : invoice.localOperationId,
                                  )
                                  ? 'تم الإرسال'
                                  : 'إرسال واتساب',
                            ),
                          ),
                          if (_canEdit &&
                              (invoice.postedToServer ||
                                  invoice.isDraft ||
                                  invoice.isQuarantined))
                            TextButton.icon(
                              onPressed: () => _editSaved(invoice),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('تعديل'),
                            ),
                          if (_canDelete &&
                              (invoice.postedToServer ||
                                  invoice.isDraft ||
                                  invoice.isQuarantined))
                            TextButton.icon(
                              onPressed: () => _deleteSaved(invoice),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _paymentSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('الدفع', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey(_paymentMode),
        initialValue: _paymentMode,
        decoration: const InputDecoration(
          labelText: 'طريقة الدفع — نقدًا افتراضيًا',
          prefixIcon: Icon(Icons.payments_outlined),
        ),
        items: const [
          DropdownMenuItem(value: 'cash', child: Text('نقدًا')),
          DropdownMenuItem(value: 'credit', child: Text('آجل')),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _paymentMode = value;
              _paymentChannel = value == 'cash' ? 'cash' : null;
              if (value == 'cash' && _paymentAccountCode.isEmpty) {
                _paymentAccountCode = _paymentAccounts.firstOrNull?.code ?? '';
              }
            });
          }
        },
      ),
      const SizedBox(height: 8),
      if (_paymentMode == 'credit')
        const Card(
          color: Color(0xFFFFF6E8),
          child: ListTile(
            leading: Icon(Icons.schedule_rounded, color: Color(0xFFB46A00)),
            title: Text('عملية بيع آجل'),
            subtitle: Text('اختر عميلًا مسجلًا أو اكتب اسم عميل جديد.'),
          ),
        ),
      Autocomplete<SavedCustomer>(
        initialValue: TextEditingValue(text: _customer.text),
        displayStringForOption: (customer) => customer.name,
        optionsBuilder: (value) {
          final query = value.text.trim().toLowerCase();
          if (query.isEmpty) return _customers;
          return _customers.where(
            (c) =>
                c.name.toLowerCase().contains(query) || c.phone.contains(query),
          );
        },
        onSelected: (customer) {
          _customer.text = customer.name;
          _phone.text = customer.phone;
          _selectedCustomerId = customer.id;
        },
        fieldViewBuilder: (_, controller, focus, submit) {
          _autoCustomerController = controller;
          return TextField(
            controller: controller,
            focusNode: focus,
            onChanged: (value) {
              _customer.text = value;
              final normalized = value.trim().toLowerCase();
              final exact = _customers.where(
                (customer) => customer.name.trim().toLowerCase() == normalized,
              );
              _selectedCustomerId = exact.isEmpty ? '' : exact.first.id;
            },
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              labelText: 'اسم العميل (اختياري للنقدي وإلزامي للآجل)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: const [latinDigitFormatter],
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: const TextStyle(
          fontFamily: 'ArialMTBlack',
          fontWeight: FontWeight.w900,
        ),
        decoration: const InputDecoration(
          labelText: 'رقم العميل',
          prefix: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '+967  ',
              style: TextStyle(
                fontFamily: 'ArialMTBlack',
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          prefixIcon: Icon(Icons.phone_outlined),
        ),
      ),
      const SizedBox(height: 10),
      if (_paymentMode == 'cash') const SizedBox(height: 10),
      if (_paymentMode == 'cash')
        SearchableChartAccountField(
          accounts: _paymentAccounts,
          value:
              _paymentAccounts.any((item) => item.code == _paymentAccountCode)
              ? _paymentAccountCode
              : null,
          label: 'حساب التحصيل الفعلي',
          hint: 'ابحث عن الصندوق أو البنك أو المحفظة',
          helperText: 'الحساب الذي استلم مبلغ الفاتورة فعليا',
          onChanged: (value) => setState(() {
            _paymentAccountCode = value ?? '';
            _paymentChannel = _channelForAccount(_paymentAccountCode);
          }),
        ),
    ],
  );

  String _channelForAccount(String code) {
    for (final account in _paymentAccounts) {
      if (account.code == code && account.settlementChannel.isNotEmpty) {
        return account.settlementChannel;
      }
    }
    final upper = code.toUpperCase();
    if (upper.contains('WALLET')) return 'wallet';
    if (upper.contains('BANK')) return 'bank';
    return 'cash';
  }

  Widget _deliveryBanner() {
    final (key, icon, color, text) = switch (_deliveryState) {
      _InvoiceDeliveryState.editingDraft => (
        'invoice-delivery-draft',
        Icons.edit_note_rounded,
        const Color(0xFF4C7893),
        _explicitDraft
            ? 'مسودة محفوظة وقابلة للتعديل.'
            : 'فاتورة جديدة قابلة للتعديل.',
      ),
      _InvoiceDeliveryState.finalizing => (
        'invoice-delivery-finalizing',
        Icons.sync_rounded,
        const Color(0xFF009B83),
        'جارٍ حفظ الفاتورة وترحيلها تلقائيًا...',
      ),
      _InvoiceDeliveryState.queued => (
        'invoice-delivery-queued',
        Icons.cloud_upload_outlined,
        Colors.orange.shade800,
        'الفاتورة محفوظة بأمان وستُزامن تلقائيًا عند توفر الاتصال.',
      ),
      _InvoiceDeliveryState.needsReview => (
        'invoice-delivery-needs-review',
        Icons.warning_amber_rounded,
        Colors.deepOrange.shade700,
        'الفاتورة تحتاج مراجعة؛ بقي الطلب الأصلي محفوظًا دون تغيير.',
      ),
      _InvoiceDeliveryState.posted => (
        'invoice-delivery-posted',
        Icons.cloud_done_outlined,
        const Color(0xFF009B83),
        'تم ترحيل الفاتورة محاسبيًا برقم ${compactDocumentNumber(_invoice.displayNumber)}.',
      ),
      _InvoiceDeliveryState.quarantined => (
        'invoice-delivery-quarantined',
        Icons.gpp_maybe_outlined,
        Colors.red.shade700,
        'لم تُرسل الفاتورة بعد. يمكنك تعديلها أو حذفها مباشرة، وسيحاول النظام مزامنتها تلقائيًا.',
      ),
    };
    return Container(
      key: Key(key),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _referenceSummary(InvoiceDocument preview) {
    final busy = _saving || _finalizing;
    final controls = _documentLocked
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _previewInvoice,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('عرض'),
              ),
              OutlinedButton.icon(
                onPressed: () => _previewThermal(_invoice),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('فاتورة مبسطة'),
              ),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _sendingWhatsapp
                    ? null
                    : () => _sendInvoiceWhatsapp(_invoice),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('إرسال واتساب'),
              ),
              if (_canEdit &&
                  (_invoice.postedToServer ||
                      _invoice.isDraft ||
                      _invoice.isQuarantined))
                OutlinedButton.icon(
                  onPressed: () => _editSaved(_invoice),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل'),
                ),
              if (_canDelete &&
                  (_invoice.postedToServer ||
                      _invoice.isDraft ||
                      _invoice.isQuarantined))
                OutlinedButton.icon(
                  onPressed: () => _deleteSaved(_invoice),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                ),
              OutlinedButton.icon(
                onPressed: _startNewInvoice,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('فاتورة جديدة'),
              ),
            ],
          )
        : NineSoftEntryFieldGrid(
            maxColumns: 2,
            children: [
              TextField(
                key: const Key('invoice-discount-input'),
                controller: _discount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الخصم'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const Key('invoice-tendered-input'),
                controller: _amountTendered,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'المدفوع'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          );
    return NineSoftEntrySummary(
      rows: [
        NineSoftEntrySummaryRow(
          id: 'subtotal',
          label: 'إجمالي الأصناف',
          value: '${preview.subtotal.toStringAsFixed(2)} YER',
        ),
        NineSoftEntrySummaryRow(
          id: 'discount',
          label: 'الخصم',
          value: '${preview.discountAmount.toStringAsFixed(2)} YER',
        ),
        NineSoftEntrySummaryRow(
          id: 'total',
          label: 'الصافي',
          value: '${preview.total.toStringAsFixed(2)} YER',
          emphasized: true,
        ),
      ],
      controls: controls,
      primaryLabel: _finalizing ? 'جارٍ الحفظ...' : 'حفظ الفاتورة',
      onPrimary: _documentLocked || !_canFinalizeCurrent
          ? null
          : () => unawaited(_finalizeInvoice()),
      secondaryLabel: _documentLocked ? null : 'حفظ كمسودة',
      onSecondary: _documentLocked ? null : () => unawaited(_saveDraft()),
      helpText:
          'Ctrl+Enter للحفظ النهائي • Ctrl+S للمسودة • F2 لإضافة سطر • F4 للباركود',
      busy: busy,
    );
  }

  Widget _referenceLines() => NineSoftEntryLineTable(
    forceTableOnMobile: true,
    showDiscount: true,
    denseReference: true,
    lines: [
      for (var index = 0; index < _lines.length; index++)
        NineSoftEntryLineCells(
          product: InkWell(
            onTap: _documentLocked ? null : () => _editLine(index),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsetsDirectional.only(end: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6FD),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFDCE6F2)),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 17,
                    color: Color(0xFF147BE0),
                  ),
                ),
                Expanded(
                  child: Text(
                    _lines[index].name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_lines[index].pendingCatalogSync)
                  Icon(
                    Icons.sync_problem_rounded,
                    key: Key('invoice-line-pending-catalog-$index'),
                    color: Colors.orange,
                    size: 16,
                  ),
              ],
            ),
          ),
          unit: Text(
            _lines[index].resolvedDisplayUnit.isEmpty
                ? 'وحدة'
                : _lines[index].resolvedDisplayUnit,
          ),
          quantity: Text(
            _lines[index].displayQuantity.replaceFirst(RegExp(r'\s+\S+$'), ''),
            textDirection: TextDirection.ltr,
          ),
          price: Text(
            _lines[index].displayUnitPrice,
            textDirection: TextDirection.ltr,
          ),
          discount: Text(
            _lines[index].lineDiscountMinor == 0 ? '0%' : 'خصم',
            textDirection: TextDirection.ltr,
          ),
          total: Text(
            _lines[index].total.toStringAsFixed(2),
            textDirection: TextDirection.ltr,
          ),
          onDelete: _documentLocked
              ? null
              : () => setState(() {
                  _lines.removeAt(index);
                  _invoice = _readInvoice(
                    number: _invoice.number,
                    createdAt: _invoice.createdAt,
                  );
                }),
          semanticsLabel: 'حذف ${_lines[index].name}',
        ),
    ],
  );

  // ignore: unused_element
  Widget _invoiceShortcutStrip() => NineSoftDocumentCommandBar(
    key: const Key('invoice-shortcut-strip'),
    title: 'اختصارات تحرير الفاتورة',
    actions: [
      NineSoftDocumentCommandAction(
        key: const Key('invoice-shortcut-f2'),
        label: 'إضافة صنف',
        shortcut: 'F2',
        icon: Icons.playlist_add_rounded,
        color: const Color(0xFF7652D6),
        onPressed: _documentLocked ? null : _handleF2,
      ),
      NineSoftDocumentCommandAction(
        key: const Key('invoice-shortcut-f3'),
        label: 'بحث عن صنف',
        shortcut: 'F3',
        icon: Icons.manage_search_rounded,
        color: const Color(0xFF1689F8),
        onPressed: _documentLocked
            ? null
            : () => _autoItemFocus?.requestFocus(),
      ),
      NineSoftDocumentCommandAction(
        key: const Key('invoice-shortcut-f4'),
        label: 'مسح باركود',
        shortcut: 'F4',
        icon: Icons.qr_code_scanner_rounded,
        color: const Color(0xFFF09A20),
        onPressed: _documentLocked ? null : () => _barcodeFocus.requestFocus(),
      ),
      NineSoftDocumentCommandAction(
        key: const Key('invoice-shortcut-history'),
        label: 'الفواتير السابقة',
        shortcut: 'عرض',
        icon: Icons.history_rounded,
        color: const Color(0xFF0B9CAD),
        onPressed: _showHistory,
      ),
      NineSoftDocumentCommandAction(
        key: const Key('invoice-shortcut-new'),
        label: 'فاتورة جديدة',
        shortcut: 'جديد',
        icon: Icons.note_add_rounded,
        color: const Color(0xFF147BE0),
        onPressed: _finalizing ? null : _startNewInvoice,
      ),
    ],
  );

  Widget _editor() {
    final preview = _readInvoice(
      number: _invoice.number,
      createdAt: _invoice.createdAt,
    );
    final document = SalesInvoicePresentationAdapter.fromDomain(preview);

    Widget customerField() => Autocomplete<SavedCustomer>(
      initialValue: TextEditingValue(text: _customer.text),
      displayStringForOption: (customer) => customer.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return _customers;
        return _customers.where(
          (customer) =>
              customer.name.toLowerCase().contains(query) ||
              customer.phone.contains(query),
        );
      },
      onSelected: (customer) {
        setState(() {
          _customer.text = customer.name;
          _phone.text = customer.phone;
          _selectedCustomerId = customer.id;
        });
      },
      fieldViewBuilder: (_, controller, focus, submit) {
        _autoCustomerController = controller;
        return TextField(
          key: const Key('invoice-reference-customer'),
          controller: controller,
          focusNode: focus,
          onChanged: (value) {
            _customer.text = value;
            final normalized = value.trim().toLowerCase();
            final exact = _customers.where(
              (customer) =>
                  customer.name.trim().toLowerCase() == normalized,
            );
            _selectedCustomerId = exact.isEmpty ? '' : exact.first.id;
            setState(() {});
          },
          onSubmitted: (_) => submit(),
          decoration: const InputDecoration(
            labelText: 'العميل *',
            prefixIcon: Icon(Icons.people_alt_outlined),
          ),
        );
      },
    );

    Widget readOnlyField({
      required String label,
      required String value,
      required IconData icon,
      TextDirection? direction,
    }) =>
        TextFormField(
          initialValue: value,
          readOnly: true,
          textDirection: direction,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
          ),
        );

    final productSearchField = Autocomplete<CatalogProduct>(
      displayStringForOption: (product) => product.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return query.isEmpty
            ? _products
            : _products.where(
                (product) =>
                    product.name.toLowerCase().contains(query) ||
                    product.barcode.toLowerCase().contains(query) ||
                    product.sku.toLowerCase().contains(query),
              );
      },
      onSelected: _pickProduct,
      fieldViewBuilder: (_, controller, focus, onSubmit) {
        _autoItemController = controller;
        _autoItemFocus = focus;
        return TextField(
          key: const Key('invoice-product-input'),
          controller: controller,
          focusNode: focus,
          onChanged: (value) {
            _item.text = value;
            if (mounted) setState(() {});
          },
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            onSubmit();
            _quantityFocus.requestFocus();
          },
          decoration: const InputDecoration(
            hintText: 'بحث عن صنف (الاسم أو الباركود أو الكود)...',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        );
      },
    );

    final barcodeField = TextField(
      key: const Key('invoice-barcode-input'),
      controller: _barcodeInput,
      focusNode: _barcodeFocus,
      autofocus: kIsWeb || defaultTargetPlatform == TargetPlatform.windows,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        hintText: 'الباركود',
        prefixIcon: Icon(Icons.qr_code_rounded),
      ),
      onSubmitted: (code) => unawaited(_acceptBarcode(code)),
    );

    final paymentModeField = DropdownButtonFormField<String>(
      key: ValueKey('reference-payment-$_paymentMode'),
      initialValue: _paymentMode,
      decoration: const InputDecoration(
        labelText: 'طريقة الدفع',
        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 'cash', child: Text('نقدي')),
        DropdownMenuItem(value: 'credit', child: Text('آجل')),
      ],
      onChanged: _documentLocked
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _paymentMode = value;
                _paymentChannel = value == 'cash' ? 'cash' : null;
                if (value == 'cash' && _paymentAccountCode.isEmpty) {
                  _paymentAccountCode =
                      _paymentAccounts.firstOrNull?.code ?? '';
                }
              });
            },
    );

    final lineEntryControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedProduct != null && _saleOptions.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(_selectedSaleOption?.id ?? 'empty-option'),
            initialValue: _saleOptions.any(
              (option) => option.id == _selectedSaleOption?.id,
            )
                ? _selectedSaleOption?.id
                : null,
            decoration: const InputDecoration(
              labelText: 'وحدة / وزن البيع',
              prefixIcon: Icon(Icons.scale_outlined),
            ),
            hint: const Text('اختر وحدة البيع'),
            items: _saleOptions
                .map(
                  (option) => DropdownMenuItem(
                    key: Key(
                      'invoice-sale-option-${option.id}-v${option.version}',
                    ),
                    value: option.id,
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _documentLocked ? null : _selectSaleOptionId,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('invoice-quantity-input'),
                controller: _quantity,
                focusNode: _quantityFocus,
                enabled: !_documentLocked,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'الكمية *',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                onChanged: (_) {
                  _pendingLineDiscountMinor = 0;
                  _pendingWeightGramsMilli = null;
                },
                onSubmitted: (_) => _priceFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('invoice-price-input'),
                controller: _price,
                focusNode: _priceFocus,
                enabled: !_documentLocked,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'سعر البيع *',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                onChanged: (_) {
                  _pendingLineDiscountMinor = 0;
                  _pendingWeightGramsMilli = null;
                  _markPriceManuallyOverridden();
                },
                onSubmitted: (_) => unawaited(_addLineFromKeyboard()),
              ),
            ),
          ],
        ),
        if (_selectedProduct != null && _canManageSaleOptions) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _documentLocked
                  ? null
                  : () => _editSaleOption(existing: _selectedSaleOption),
              icon: Icon(
                _selectedSaleOption == null
                    ? Icons.add_circle_outline_rounded
                    : Icons.edit_outlined,
              ),
              label: Text(
                _selectedSaleOption == null
                    ? 'إضافة وحدة / وزن بيع'
                    : 'تعديل وحدة البيع المحددة',
              ),
            ),
          ),
        ],
        if (_selectedProduct != null &&
            WeightedSaleMath.isMassUnit(_selectedProduct!.unitName)) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('invoice-sale-amount-input'),
                  controller: _saleAmount,
                  enabled: !_documentLocked,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [latinDigitFormatter],
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'بيع بالمبلغ للصنف الموزون',
                    prefixIcon: Icon(Icons.scale_rounded),
                  ),
                  onSubmitted: (_) => unawaited(_addWeightedAmountLine()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const Key('invoice-sale-amount-add'),
                onPressed: _documentLocked || _saving
                    ? null
                    : () => unawaited(_addWeightedAmountLine()),
                icon: const Icon(Icons.calculate_rounded),
                label: const Text('إضافة بالمبلغ'),
              ),
            ],
          ),
        ],
      ],
    );

    final settlementField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _discount,
                enabled: !_documentLocked,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'الخصم',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountTendered,
                enabled: !_documentLocked,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [latinDigitFormatter],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText:
                      _paymentMode == 'cash' ? 'المبلغ المستلم' : 'المدفوع',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (_paymentMode == 'cash' && _paymentAccounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          SearchableChartAccountField(
            accounts: _paymentAccounts,
            value: _paymentAccounts.any(
              (item) => item.code == _paymentAccountCode,
            )
                ? _paymentAccountCode
                : null,
            label: 'حساب التحصيل',
            hint: 'الصندوق أو البنك أو المحفظة',
            onChanged: _documentLocked
                ? null
                : (value) => setState(() {
                      _paymentAccountCode = value ?? '';
                      _paymentChannel =
                          _channelForAccount(_paymentAccountCode);
                    }),
          ),
        ],
        if (_paymentMode == 'credit') ...[
          const SizedBox(height: 8),
          const Text(
            'البيع الآجل يتطلب عميلاً مسجلاً أو اسم عميل جديد.',
            style: TextStyle(
              color: Color(0xFFA55300),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    Future<void> printCurrent() async {
      if (!_documentLocked && !await _saveDraft(notify: false)) return;
      await _printThermal();
    }

    Future<void> whatsappCurrent() async {
      if (!_documentLocked && !await _saveDraft(notify: false)) return;
      await _sendInvoiceWhatsapp(_invoice);
    }

    final lockedControls = !_documentLocked
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _previewInvoice,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('عرض'),
              ),
              OutlinedButton.icon(
                onPressed: () => _previewThermal(_invoice),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('فاتورة مبسطة'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_share()),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _sendingWhatsapp
                    ? null
                    : () => unawaited(_sendInvoiceWhatsapp(_invoice)),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('إرسال واتساب'),
              ),
              if (_canEdit &&
                  (_invoice.postedToServer ||
                      _invoice.isDraft ||
                      _invoice.isQuarantined))
                OutlinedButton.icon(
                  onPressed: () => _editSaved(_invoice),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل'),
                ),
              if (_canDelete &&
                  (_invoice.postedToServer ||
                      _invoice.isDraft ||
                      _invoice.isQuarantined))
                OutlinedButton.icon(
                  onPressed: () => _deleteSaved(_invoice),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                ),
            ],
          );

    return SalesInvoiceReferenceView(
      key: const ValueKey('sales-invoice-reference-view'),
      document: document,
      customerField: customerField(),
      invoiceNumberField: readOnlyField(
        label: 'رقم الفاتورة *',
        value: compactDocumentNumber(preview.displayNumber),
        icon: Icons.description_outlined,
        direction: TextDirection.ltr,
      ),
      branchField: readOnlyField(
        label: 'المخزن / الفرع *',
        value: preview.branchLabel,
        icon: Icons.warehouse_outlined,
      ),
      dateField: readOnlyField(
        label: 'التاريخ *',
        value:
            '${preview.createdAt.year.toString().padLeft(4, '0')}/${preview.createdAt.month.toString().padLeft(2, '0')}/${preview.createdAt.day.toString().padLeft(2, '0')}',
        icon: Icons.calendar_month_outlined,
        direction: TextDirection.ltr,
      ),
      employeeField: readOnlyField(
        label: 'مندوب المبيعات',
        value: preview.employeeName,
        icon: Icons.person_outline_rounded,
      ),
      paymentModeField: paymentModeField,
      productSearchField: productSearchField,
      barcodeField: barcodeField,
      lineEntryControls:
          (_selectedProduct == null && _item.text.trim().isEmpty)
              ? null
              : lineEntryControls,
      linesTable:
          _lines.isEmpty ? const _EmptyInvoiceLines() : _referenceLines(),
      notesField: TextField(
        key: const Key('invoice-notes-input'),
        controller: _notes,
        enabled: !_documentLocked,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'أضف ملاحظات على الفاتورة...',
        ),
      ),
      settlementField: settlementField,
      deliveryBanner:
          _deliveryState == _InvoiceDeliveryState.editingDraft && !_explicitDraft
              ? const SizedBox.shrink()
              : _deliveryBanner(),
      lockedControls: lockedControls,
      onAddLine: _handleF2,
      onScanBarcode: _scanProductBarcode,
      onSave: _canFinalizeCurrent
          ? () => unawaited(_finalizeInvoice())
          : null,
      onPrint: preview.lines.isEmpty ? null : () => unawaited(printCurrent()),
      onPdf: preview.lines.isEmpty ? null : () => unawaited(_share()),
      onWhatsapp:
          preview.lines.isEmpty ? null : () => unawaited(whatsappCurrent()),
      onNewInvoice: _finalizing ? null : _startNewInvoice,
      onHistory: _showHistory,
      busy: _saving || _finalizing,
      locked: _documentLocked,
    );
  }
}

class _EmptyInvoiceLines extends StatelessWidget {
  const _EmptyInvoiceLines();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAF9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE9E4)),
    ),
    child: const Row(
      children: [
        Icon(Icons.playlist_add_rounded, color: Color(0xFF25886E)),
        SizedBox(width: 10),
        Expanded(child: Text('أضف أول صنف لتكوين الفاتورة.')),
      ],
    ),
  );
}

// Kept for the forthcoming full-document read-only route.
// ignore: unused_element
class _InvoiceLinesTable extends StatelessWidget {
  const _InvoiceLinesTable({
    required this.lines,
    required this.onEdit,
    required this.onDelete,
  });

  final List<InvoiceLine> lines;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  String _number(double value, [int decimals = 3]) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(decimals).replaceFirst(RegExp(r'0+$'), '');
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 720),
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            NizamiColors.blue.withValues(alpha: .075),
          ),
          columnSpacing: 24,
          horizontalMargin: 14,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('الصنف / الخدمة')),
            DataColumn(numeric: true, label: Text('الكمية')),
            DataColumn(label: Text('الوحدة')),
            DataColumn(numeric: true, label: Text('السعر')),
            DataColumn(numeric: true, label: Text('الإجمالي')),
            DataColumn(label: Text('إجراء')),
          ],
          rows: [
            for (var index = 0; index < lines.length; index++)
              DataRow(
                onSelectChanged: (_) => onEdit(index),
                cells: [
                  DataCell(
                    Text(
                      '${index + 1}',
                      style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 190),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            lines[index].name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (lines[index].pendingCatalogSync)
                            Text(
                              'بانتظار مزامنة الصنف',
                              key: Key('invoice-line-pending-catalog-$index'),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _number(lines[index].quantity),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    ),
                  ),
                  DataCell(
                    Text(
                      lines[index].weightGramsMilli != null
                          ? '${(lines[index].weightGramsMilli! / 1000).toStringAsFixed(3)} جرام'
                          : lines[index].optionLabel.isEmpty
                          ? 'وحدة'
                          : lines[index].optionLabel,
                    ),
                  ),
                  DataCell(
                    Text(
                      lines[index].displayUnitPrice,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'ArialMTBlack'),
                    ),
                  ),
                  DataCell(
                    Text(
                      lines[index].total.toStringAsFixed(2),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: 'ArialMTBlack',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'تعديل البند',
                          onPressed: () => onEdit(index),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'حذف البند',
                          onPressed: () => onDelete(index),
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

// Kept for the forthcoming full-document read-only route.
// ignore: unused_element
class _InvoiceLineCard extends StatelessWidget {
  const _InvoiceLineCard({
    required this.index,
    required this.line,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final InvoiceLine line;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    color: const Color(0xFFF9FBFA),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onEdit,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE7F5EF),
              foregroundColor: const Color(0xFF25886E),
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontFamily: 'ArialMTBlack'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (line.pendingCatalogSync)
                    Text(
                      'بانتظار مزامنة الصنف',
                      key: Key('invoice-line-pending-catalog-$index'),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (line.weightGramsMilli != null)
                    Text(
                      'الوزن: ${(line.weightGramsMilli! / 1000).toStringAsFixed(3)} جرام',
                      style: const TextStyle(
                        color: Color(0xFF25886E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${line.quantity} × ${line.displayUnitPrice} YER',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'ArialMTBlack',
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${line.total.toStringAsFixed(2)} YER',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontFamily: 'ArialMTBlack',
                fontWeight: FontWeight.w900,
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: 'تعديل الصنف',
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'حذف الصنف',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}

// Kept for the forthcoming full-document read-only route.
// ignore: unused_element
class _InvoiceTotalCard extends StatelessWidget {
  const _InvoiceTotalCard({required this.invoice});
  final InvoiceDocument invoice;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFE7F5EF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        _amountRow('الإجمالي', invoice.subtotal, context),
        _amountRow('الخصم', invoice.discountAmount, context),
        const Divider(),
        _amountRow('الصافي', invoice.total, context, emphasized: true),
        _amountRow('المدفوع', invoice.amountTendered, context),
        _amountRow('المتبقي', invoice.dueAmount, context),
        _amountRow('المرتجع', invoice.returnAmount, context),
      ],
    ),
  );

  Widget _amountRow(
    String label,
    double value,
    BuildContext context, {
    bool emphasized = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)} ${invoice.currency}',
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFamily: 'ArialMTBlack',
            color: const Color(0xFF17664F),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}
