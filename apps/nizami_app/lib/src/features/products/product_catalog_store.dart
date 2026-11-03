import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class CatalogProduct {
  const CatalogProduct({
    this.id = '',
    this.sku = '',
    required this.name,
    required this.purchasePrice,
    required this.salePrice,
    required this.barcode,
    this.category = '',
    this.subcategory = '',
    this.unitName = '',
    this.stockQuantity,
    this.hasPurchasePrice = true,
    this.hasSalePrice = true,
    this.version = 1,
  });

  final String id;
  final String sku;
  final String name;
  final double purchasePrice;
  final double salePrice;
  final String barcode;
  final String category;
  final String subcategory;
  final String unitName;
  final double? stockQuantity;
  final bool hasPurchasePrice;
  final bool hasSalePrice;
  final int version;

  static double _number(Object? value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json['id']?.toString() ?? '',
    sku: json['sku']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    purchasePrice: _number(json['purchasePrice']),
    salePrice: _number(json['salePrice']),
    barcode: json['barcode']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    subcategory: json['subcategory']?.toString() ?? '',
    unitName: json['unitName']?.toString() ?? '',
    stockQuantity: json['stockQuantity'] == null
        ? null
        : _number(json['stockQuantity']),
    hasPurchasePrice:
        json['hasPurchasePrice'] as bool? ?? json['purchasePrice'] != null,
    hasSalePrice: json['hasSalePrice'] as bool? ?? json['salePrice'] != null,
    version: (json['version'] as num?)?.toInt() ?? 1,
  );

  factory CatalogProduct.fromServer(Map<String, dynamic> json) =>
      CatalogProduct(
        id: json['id']?.toString() ?? '',
        sku: json['sku']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        purchasePrice: _number(json['purchase_price_minor']) / 100,
        salePrice: _number(json['sale_price_minor']) / 100,
        barcode: json['barcode']?.toString() ?? '',
        category: json['category_name']?.toString() ?? '',
        subcategory: json['subcategory_name']?.toString() ?? '',
        unitName: json['unit_name']?.toString() ?? '',
        stockQuantity: json['stock_quantity_milli'] == null
            ? null
            : _number(json['stock_quantity_milli']) / 1000,
        hasPurchasePrice: json['purchase_price_minor'] != null,
        hasSalePrice: json['sale_price_minor'] != null,
        version: (json['version'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sku': sku,
    'name': name,
    'purchasePrice': purchasePrice,
    'salePrice': salePrice,
    'barcode': barcode,
    'category': category,
    'subcategory': subcategory,
    'unitName': unitName,
    'stockQuantity': stockQuantity,
    'hasPurchasePrice': hasPurchasePrice,
    'hasSalePrice': hasSalePrice,
    'version': version,
  };
}

/// Device cache, NOT the server's source of truth. Server IDs win over names,
/// and all writes to this cache are serialized across instances in an isolate.
class ProductCatalogStore {
  ProductCatalogStore(this.tenantName);

  final String tenantName;
  String get _key => 'ninesoft.products.v2.$tenantName';
  static final Map<String, Future<void>> _writers = {};

  Future<T> _serial<T>(Future<T> Function() work) async {
    final previous = _writers[_key] ?? Future<void>.value();
    final gate = Completer<void>();
    _writers[_key] = gate.future;
    await previous;
    try {
      return await work();
    } finally {
      gate.complete();
      if (identical(_writers[_key], gate.future)) _writers.remove(_key);
    }
  }

  static String _name(String value) => value.trim().toLowerCase();

  Future<List<CatalogProduct>> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (value) =>
                CatalogProduct.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((p) => p.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<CatalogProduct> products) async {
    final success = await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(products.map((p) => p.toJson()).toList()),
    );
    if (!success) throw StateError('تعذر حفظ دليل الأصناف محليًا.');
  }

  /// Upsert by canonical server ID first; legacy offline products use name.
  static List<CatalogProduct> _deduplicate(Iterable<CatalogProduct> input) {
    final byId = <String, CatalogProduct>{};
    final byName = <String, CatalogProduct>{};
    for (final p in input) {
      final name = _name(p.name);
      if (name.isEmpty) continue;
      final existing = p.id.isNotEmpty ? byId[p.id] : byName[name];
      if (existing != null) byName.remove(_name(existing.name));
      final sameName = byName[name];
      if (sameName != null && sameName.id.isNotEmpty) byId.remove(sameName.id);
      if (p.id.isNotEmpty) byId[p.id] = p;
      byName[name] = p;
    }
    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<CatalogProduct> save(CatalogProduct product) => _serial(() async {
    final products = await read();
    final index = products.indexWhere(
      (p) =>
          (product.id.isNotEmpty && p.id == product.id) ||
          _name(p.name) == _name(product.name),
    );
    var barcode = product.barcode.trim();
    if (barcode.isEmpty && index >= 0) barcode = products[index].barcode;
    // A device-scoped temporary barcode cannot collide with another
    // offline device. The server replaces LOCAL-* with its canonical PRD
    // sequence, and the realtime upsert reconciles this cached draft.
    if (barcode.isEmpty && product.id.isEmpty) {
      barcode = 'LOCAL-${const Uuid().v4()}';
    }
    if (barcode.isNotEmpty &&
        products.any(
          (p) =>
              p.barcode == barcode &&
              p.id != product.id &&
              _name(p.name) != _name(product.name),
        )) {
      throw StateError('هذا الباركود مستخدم لصنف آخر.');
    }
    final result = CatalogProduct(
      id: product.id.isNotEmpty || index < 0 ? product.id : products[index].id,
      sku: product.sku.isNotEmpty || index < 0 ? product.sku : products[index].sku,
      name: product.name,
      purchasePrice: product.purchasePrice > 0 || index < 0
          ? product.purchasePrice
          : products[index].purchasePrice,
      salePrice: product.salePrice,
      barcode: barcode,
      category: product.category.isNotEmpty || index < 0
          ? product.category
          : products[index].category,
      subcategory: product.subcategory.isNotEmpty || index < 0
          ? product.subcategory
          : products[index].subcategory,
      unitName: product.unitName.isNotEmpty || index < 0
          ? product.unitName
          : products[index].unitName,
      stockQuantity:
          product.stockQuantity ??
          (index < 0 ? null : products[index].stockQuantity),
      hasPurchasePrice: product.hasPurchasePrice,
      hasSalePrice: product.hasSalePrice,
      version: product.version,
    );
    await _write(_deduplicate([...products, result]));
    return result;
  });

  /// Legacy caller still needs a merge, which keeps unsent local items.
  Future<List<CatalogProduct>> mergeRemote(Iterable<CatalogProduct> remote) =>
      _serial(() async {
        final products = _deduplicate([...await read(), ...remote]);
        await _write(products);
        return products;
      });

  /// On a successful full refresh, remove server-owned items absent upstream.
  /// Never drop offline-only (id-less) draft products.
  Future<List<CatalogProduct>> replaceRemoteSnapshot(
    Iterable<CatalogProduct> remote,
  ) => _serial(() async {
    final offline = (await read()).where((p) => p.id.isEmpty);
    final products = _deduplicate([...offline, ...remote]);
    await _write(products);
    return products;
  });

  Future<void> applyRemoteChange(
    String id,
    String operation,
    Map<String, dynamic> payload,
  ) => _serial(() async {
    final existing = await read();
    if (operation == 'delete') {
      existing.removeWhere((p) => p.id == id);
    } else {
      final item = CatalogProduct.fromServer({...payload, 'id': id});
      existing.removeWhere(
        (p) => p.id == id || _name(p.name) == _name(item.name),
      );
      existing.add(item);
    }
    await _write(_deduplicate(existing));
  });

  Future<void> remove(String name) => _serial(() async {
    final products = await read();
    products.removeWhere((p) => _name(p.name) == _name(name));
    await _write(products);
  });
}
