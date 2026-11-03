import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../modules/catalog_sync_api.dart';

/// A tenant-and-branch scoped durable cache of server-owned sale options.
/// Exact numerator/denominator fields are the pricing authority; [price] on
/// [ProductSaleOption] remains only a legacy display value.
class ProductSaleOptionStore {
  ProductSaleOptionStore(this.tenantId, this.branchId) {
    if (tenantId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Product sale option scope must be complete');
    }
  }

  final String tenantId;
  final String branchId;

  String get _key => 'ninesoft.product_sale_options.v1.$tenantId.$branchId';

  static final Map<String, Future<void>> _writers = {};

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  Future<List<ProductSaleOption>> _readAll() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid product sale option cache');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid product sale option row');
          }
          final option = ProductSaleOption.fromJson(
            Map<String, dynamic>.from(value),
          );
          _validateScope(option);
          return option;
        })
        .toList(growable: true);
  }

  Future<void> _write(Iterable<ProductSaleOption> options) async {
    final ordered = options.toList()
      ..sort((a, b) {
        final product = a.productId.compareTo(b.productId);
        if (product != 0) return product;
        final identity = _identity(a).compareTo(_identity(b));
        if (identity != 0) return identity;
        final scope = (a.branchId ?? '').compareTo(b.branchId ?? '');
        if (scope != 0) return scope;
        return a.id.compareTo(b.id);
      });
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(ordered.map((value) => value.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Unable to persist product sale options');
    }
  }

  void _validateScope(ProductSaleOption option) {
    if (option.id.isEmpty ||
        option.productId.isEmpty ||
        option.unitCode.isEmpty ||
        option.quantity <= 0 ||
        option.priceNumeratorMinor < 0 ||
        option.priceDenominator <= 0) {
      throw const FormatException('Incomplete product sale option');
    }
    if (option.tenantId != tenantId) {
      throw StateError('Product sale option belongs to another tenant');
    }
    if (option.branchId != null && option.branchId != branchId) {
      throw StateError('Product sale option belongs to another branch');
    }
  }

  static String _identity(ProductSaleOption option) =>
      option.identityKey.isNotEmpty
      ? option.identityKey
      : '${option.unitCode}:${option.quantity.toStringAsFixed(9)}';

  static bool _prefer(ProductSaleOption candidate, ProductSaleOption current) {
    final candidateBranch = candidate.branchId == null ? 0 : 1;
    final currentBranch = current.branchId == null ? 0 : 1;
    if (candidateBranch != currentBranch) {
      return candidateBranch > currentBranch;
    }
    if (candidate.version != current.version) {
      return candidate.version > current.version;
    }
    return candidate.id.compareTo(current.id) > 0;
  }

  Future<List<ProductSaleOption>> readProduct(String productId) async {
    final resolved = <String, ProductSaleOption>{};
    for (final option in await _readAll()) {
      if (option.productId != productId) continue;
      final identity = _identity(option);
      final current = resolved[identity];
      if (current == null || _prefer(option, current)) {
        resolved[identity] = option;
      }
    }
    final values = resolved.values.toList()
      ..sort((a, b) {
        final unit = a.unitCode.compareTo(b.unitCode);
        if (unit != 0) return unit;
        final quantity = a.quantity.compareTo(b.quantity);
        if (quantity != 0) return quantity;
        return a.id.compareTo(b.id);
      });
    return values;
  }

  /// Resolves a scanner code with one cache decode, independent of the number
  /// of products in the catalogue.
  Future<ProductSaleOption?> findByUnitBarcode(String barcode) async {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return null;
    ProductSaleOption? resolved;
    for (final option in await _readAll()) {
      if (option.unitBarcode?.trim() != normalized) continue;
      if (resolved == null || _prefer(option, resolved)) resolved = option;
    }
    return resolved;
  }

  Future<bool> get isEmpty async => (await _readAll()).isEmpty;

  Future<void> replaceSnapshot(Iterable<ProductSaleOption> snapshot) =>
      _serial(() async {
        final validated = snapshot.toList(growable: false);
        for (final option in validated) {
          _validateScope(option);
        }
        await _write(validated);
      });

  Future<void> replaceProduct(
    String productId,
    Iterable<ProductSaleOption> snapshot,
  ) => _serial(() async {
    if (productId.isEmpty) {
      throw ArgumentError.value(productId, 'productId');
    }
    final validated = snapshot.toList(growable: false);
    for (final option in validated) {
      _validateScope(option);
      if (option.productId != productId) {
        throw const FormatException('Sale option belongs to another product');
      }
    }
    final options = await _readAll()
      ..removeWhere((option) => option.productId == productId);
    options.addAll(validated);
    await _write(options);
  });

  Future<void> upsertAll(
    Iterable<ProductSaleOption> incoming, {
    bool Function()? isValid,
  }) => _serial(() async {
    final validated = incoming.toList(growable: false);
    final ids = <String>{};
    for (final option in validated) {
      _validateScope(option);
      if (!ids.add(option.id)) {
        throw const FormatException('Duplicate product sale option ID');
      }
    }
    final options = await _readAll();
    if (isValid != null && !isValid()) {
      throw const ProductSaleOptionWriteInvalidated();
    }
    for (final option in validated) {
      options.removeWhere((current) => current.id == option.id);
      options.add(option);
    }
    await _write(options);
  });

  Future<void> applyRemoteChange(
    String id,
    String operation,
    Map<String, dynamic> payload,
  ) => _serial(() async {
    if (id.isEmpty || !const {'upsert', 'delete'}.contains(operation)) {
      throw const FormatException('Invalid product sale option change');
    }
    final options = await _readAll();
    if (operation == 'delete') {
      options.removeWhere((option) => option.id == id);
    } else {
      final option = ProductSaleOption.fromJson({...payload, 'id': id});
      _validateScope(option);
      options.removeWhere((current) => current.id == id);
      options.add(option);
    }
    await _write(options);
  });
}

class ProductSaleOptionWriteInvalidated implements Exception {
  const ProductSaleOptionWriteInvalidated();
}
