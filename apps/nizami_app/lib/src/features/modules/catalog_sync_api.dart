import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../auth/json_transport.dart';

class CatalogSyncApi {
  CatalogSyncApi({required this.token, JsonTransport? transport})
    : _transport = transport ?? createJsonTransport(),
      _baseUri = Uri.parse(
        '${const String.fromEnvironment('NINESOFT_API_BASE_URL', defaultValue: 'https://ninesoft.qodynex.tech/api/v1').replaceFirst(RegExp(r'/+$'), '')}/',
      );

  final String token;
  final JsonTransport _transport;
  final Uri _baseUri;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
    'Authorization': 'Bearer $token',
  };

  Future<List<Map<String, dynamic>>> list(
    String entity, {
    String? branchId,
  }) async {
    final result = <Map<String, dynamic>>[];
    String? snapshotAt;
    String? afterCreatedAt;
    String? afterId;
    for (var page = 1; page <= 1000; page++) {
      final query = <String, String>{
        'snapshot': '1',
        'per_page': '200',
        if (branchId != null && branchId.isNotEmpty) 'branch_id': branchId,
        'snapshot_at': ?snapshotAt,
        'after_created_at': ?afterCreatedAt,
        'after_id': ?afterId,
      };
      final response = await _transport.request(
        _baseUri.resolve(
          'catalog/$entity?${Uri(queryParameters: query).query}',
        ),
        method: 'GET',
        headers: _headers,
      );
      final decoded = _decode(response);
      final values = decoded['data'];
      if (values is! List) {
        throw const FormatException('Invalid catalog snapshot');
      }
      result.addAll(
        values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      snapshotAt ??= decoded['snapshot_at']?.toString();
      if (decoded['has_more'] != true) return result;
      final nextCreatedAt = decoded['next_after_created_at']?.toString() ?? '';
      final nextId = decoded['next_after_id']?.toString() ?? '';
      if (nextCreatedAt.isEmpty ||
          nextId.isEmpty ||
          (nextCreatedAt == afterCreatedAt && nextId == afterId)) {
        throw const FormatException('Catalog snapshot cursor did not advance');
      }
      afterCreatedAt = nextCreatedAt;
      afterId = nextId;
    }
    throw StateError('قائمة $entity أكبر من حد الاستعادة الآمن.');
  }

  Future<List<ProductSaleOption>> saleOptions(
    String productId, {
    required String branchId,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve(
        'catalog/products/$productId/sale-options?branch_id=${Uri.encodeQueryComponent(branchId)}',
      ),
      method: 'GET',
      headers: _headers,
    );
    final values = _decode(response)['data'];
    if (values is! List) {
      throw const FormatException('Invalid product sale option response');
    }
    final result = <ProductSaleOption>[];
    for (final value in values) {
      if (value is! Map) {
        throw const FormatException('Invalid product sale option row');
      }
      result.add(
        ProductSaleOption.fromJson(Map<String, dynamic>.from(value)),
      );
    }
    return result;
  }

  Future<List<ProductSaleOption>> productSaleOptionSnapshot({
    required String branchId,
  }) async {
    if (branchId.trim().isEmpty) {
      throw ArgumentError.value(branchId, 'branchId');
    }
    final result = <ProductSaleOption>[];
    int? expectedLastPage;
    for (var page = 1; page <= 10000; page++) {
      final response = await _transport.request(
        _baseUri.resolve(
          'catalog/product-sale-options?${Uri(queryParameters: {'branch_id': branchId, 'per_page': '100', 'page': '$page'}).query}',
        ),
        method: 'GET',
        headers: _headers,
      );
      final decoded = _decode(response);
      final values = decoded['data'];
      if (values is! List) {
        throw const FormatException('Invalid product sale option snapshot');
      }
      final parsedPage = <ProductSaleOption>[];
      for (final value in values) {
        if (value is! Map) {
          throw const FormatException(
            'Invalid product sale option snapshot row',
          );
        }
        final option = ProductSaleOption.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (option.id.isEmpty ||
            option.tenantId.isEmpty ||
            option.productId.isEmpty ||
            option.unitCode.isEmpty ||
            option.quantity <= 0) {
          throw const FormatException(
            'Incomplete product sale option snapshot row',
          );
        }
        parsedPage.add(option);
      }
      final current = _canonicalInteger(
        decoded['current_page'],
        field: 'current_page',
        minimum: 1,
        maximum: 10000,
      );
      final last = _canonicalInteger(
        decoded['last_page'],
        field: 'last_page',
        minimum: 1,
        maximum: 10000,
      );
      if (current != page || last < current) {
        throw const FormatException(
          'Product sale option snapshot cursor did not advance',
        );
      }
      if (expectedLastPage != null && expectedLastPage != last) {
        throw const FormatException(
          'Product sale option snapshot page count changed',
        );
      }
      expectedLastPage = last;
      result.addAll(parsedPage);
      if (current == last) return result;
    }
    throw StateError('Product sale option snapshot exceeded safe page limit');
  }

  Future<Map<String, dynamic>> putUnitProfileRequest({
    required String productId,
    required String requestBody,
  }) async {
    if (productId.trim().isEmpty || requestBody.isEmpty) {
      throw ArgumentError('Incomplete product unit profile request');
    }
    final response = await _transport.request(
      _baseUri.resolve(
        'catalog/products/${Uri.encodeComponent(productId)}/unit-profile',
      ),
      method: 'PUT',
      headers: _headers,
      body: requestBody,
    );
    return _decode(response);
  }

  Future<ProductSaleOption> createSaleOption(
    String productId, {
    required String branchId,
    required String unitCode,
    required double quantity,
    required double price,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/products/$productId/sale-options'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({
        'branch_id': branchId,
        'unit_code': unitCode,
        'quantity_per_option': quantity,
        'option_price_minor': (price * 100).round(),
        'client_operation_id': const Uuid().v4(),
      }),
    );
    final value = _decode(response)['sale_option'];
    return ProductSaleOption.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<ProductSaleOption> updateSaleOption(
    String productId,
    ProductSaleOption option,
    double price,
  ) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/products/$productId/sale-options/${option.id}'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode({
        'version': option.version,
        'option_price_minor': (price * 100).round(),
      }),
    );
    final value = _decode(response)['sale_option'];
    return ProductSaleOption.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<void> saveProduct({
    required String name,
    required String barcode,
    required double salePrice,
    required double purchasePrice,
    String unitName = 'حبة',
  }) => _save('products', {
    'name': name,
    'barcode': barcode,
    'kind': 'stock',
    'unit_name': unitName,
    'sale_price_minor': (salePrice * 100).round(),
    'purchase_price_minor': (purchasePrice * 100).round(),
  });

  Future<double> setProductStock({
    required String productId,
    required String branchId,
    required double expectedQuantity,
    required double targetQuantity,
    double? valuationUnitCost,
    required String operationId,
    required String reason,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/products/$productId/stock'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode({
        'branch_id': branchId,
        'operation_id': operationId,
        'expected_quantity_milli': (expectedQuantity * 1000).round(),
        'target_quantity_milli': (targetQuantity * 1000).round(),
        if (valuationUnitCost != null)
          'valuation_unit_cost_minor': (valuationUnitCost * 100).round(),
        'reason': reason,
      }),
    );
    final value = _decode(response)['stock'];
    if (value is! Map) throw const FormatException('Invalid stock response');
    return ((value['quantity_milli'] as num?)?.toDouble() ?? 0) / 1000;
  }

  Future<CatalogContact> saveCustomer({
    required String name,
    required String phone,
  }) => _saveContact(
    'customers',
    responseKey: 'customer',
    name: name,
    phone: phone,
  );

  Future<CatalogContact> saveSupplier({
    required String name,
    required String phone,
  }) => _saveContact(
    'suppliers',
    responseKey: 'supplier',
    name: name,
    phone: phone,
  );

  Future<void> updateProduct({
    required String id,
    required int expectedVersion,
    required String name,
    required String barcode,
    required double salePrice,
    required double purchasePrice,
    String unitName = 'حبة',
  }) => _update('products', id, {
    'expected_version': expectedVersion,
    'name': name,
    'barcode': barcode,
    'kind': 'stock',
    'unit_name': unitName,
    'sale_price_minor': (salePrice * 100).round(),
    'purchase_price_minor': (purchasePrice * 100).round(),
  });

  Future<void> updateContact({
    required String entity,
    required String id,
    required int expectedVersion,
    required String name,
    required String phone,
  }) => _update(entity, id, {
    'expected_version': expectedVersion,
    'name': name,
    'phone': phone,
  });

  Future<void> _update(
    String entity,
    String id,
    Map<String, Object?> body,
  ) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/$entity/$id'),
      method: 'PUT',
      headers: _headers,
      body: jsonEncode(body),
    );
    _decode(response);
  }

  Future<void> remove(String entity, {required String name}) async {
    final uri = _baseUri.resolve(
      'catalog/$entity?name=${Uri.encodeQueryComponent(name)}',
    );
    final response = await _transport.request(
      uri,
      method: 'DELETE',
      headers: _headers,
    );
    _decode(response);
  }

  Future<void> _save(String entity, Map<String, Object?> body) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/$entity'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode(body),
    );
    _decode(response);
  }

  Future<CatalogContact> _saveContact(
    String entity, {
    required String responseKey,
    required String name,
    required String phone,
  }) async {
    final response = await _transport.request(
      _baseUri.resolve('catalog/$entity'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    final decoded = _decode(response);
    final raw = decoded[responseKey];
    if (raw is! Map) {
      throw const FormatException('Invalid canonical contact response');
    }
    final contact = CatalogContact.fromJson(Map<String, dynamic>.from(raw));
    if (contact.id.isEmpty) {
      throw const FormatException('Missing canonical contact ID');
    }
    return contact;
  }

  Map<String, dynamic> _decode(JsonResponse response) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogApiException(
          'Catalog request failed with an invalid error response',
          statusCode: response.statusCode,
        );
      }
      rethrow;
    }
    final value = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CatalogApiException(
        value['message']?.toString() ?? 'تعذرت مزامنة الدليل مع الخادم.',
        statusCode: response.statusCode,
      );
    }
    return value;
  }
}

class CatalogApiException implements Exception {
  const CatalogApiException(this.message, {required this.statusCode});

  final String message;
  final int statusCode;

  bool get definitelyRejected =>
      statusCode >= 400 &&
      statusCode < 500 &&
      !const {408, 425, 429}.contains(statusCode);

  @override
  String toString() => message;
}

class CatalogContact {
  const CatalogContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    required this.version,
  });

  final String id;
  final String name;
  final String phone;
  final String type;
  final int version;

  factory CatalogContact.fromJson(Map<String, dynamic> json) => CatalogContact(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    phone: json['phone']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
  );
}

class ProductSaleOption {
  const ProductSaleOption({
    required this.id,
    required this.unitCode,
    required this.quantity,
    required this.price,
    required this.version,
    this.tenantId = '',
    this.branchId,
    this.productId = '',
    this.identityKey = '',
    this.priceNumeratorMinor = 0,
    this.priceDenominator = 1,
    this.unitBarcode,
    this.isDerived = false,
    this.normalizedMassG,
  });
  final String id;
  final String tenantId;
  final String? branchId;
  final String productId;
  final String identityKey;
  final String unitCode;
  final double quantity;
  final double price;
  final int priceNumeratorMinor;
  final int priceDenominator;
  final String? unitBarcode;
  final bool isDerived;
  final int version;
  final double? normalizedMassG;

  factory ProductSaleOption.fromJson(Map<String, dynamic> json) {
    final previewMinor = _displayInt(json['option_price_minor']) ?? 0;
    final numerator = json.containsKey('price_numerator_minor')
        ? _requiredCanonicalInt(
            json['price_numerator_minor'],
            'price_numerator_minor',
            minimum: 0,
          )
        : previewMinor;
    final denominator = json.containsKey('price_denominator')
        ? _requiredCanonicalInt(
            json['price_denominator'],
            'price_denominator',
            minimum: 1,
          )
        : 1;
    if (numerator < 0 || denominator <= 0) {
      throw const FormatException('Invalid exact product sale option price');
    }
    final barcode = _optionalText(json['unit_barcode'], 'unit_barcode');
    return ProductSaleOption(
      id: _optionalText(json['id'], 'id') ?? '',
      tenantId: _optionalText(json['tenant_id'], 'tenant_id') ?? '',
      branchId: _optionalText(json['branch_id'], 'branch_id'),
      productId: _optionalText(json['product_id'], 'product_id') ?? '',
      identityKey: _optionalText(json['identity_key'], 'identity_key') ?? '',
      unitCode: _optionalText(json['unit_code'], 'unit_code') ?? '',
      quantity:
          double.tryParse(json['quantity_per_option']?.toString() ?? '') ?? 0,
      price: previewMinor / 100,
      priceNumeratorMinor: numerator,
      priceDenominator: denominator,
      unitBarcode: barcode == null || barcode.isEmpty ? null : barcode,
      isDerived: json['is_derived'] == true || json['is_derived'] == 1,
      version: json.containsKey('version')
          ? _requiredCanonicalInt(json['version'], 'version', minimum: 1)
          : 1,
      normalizedMassG: double.tryParse(
        json['normalized_mass_g']?.toString() ?? '',
      ),
    );
  }

  static int? _displayInt(Object? value) {
    if (value is int) return value;
    if (value is num) {
      if (!value.isFinite) return null;
      final integer = value.toInt();
      return value == integer ? integer : null;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static int _requiredCanonicalInt(
    Object? value,
    String field, {
    required int minimum,
  }) => _canonicalInteger(value, field: field, minimum: minimum);

  static String? _optionalText(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field must be a string identifier');
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'product_id': productId,
    'identity_key': identityKey,
    'unit_code': unitCode,
    'quantity_per_option': quantity,
    'option_price_minor': (price * 100).round(),
    'price_numerator_minor': priceNumeratorMinor,
    'price_denominator': priceDenominator,
    'unit_barcode': unitBarcode,
    'is_derived': isDerived,
    'version': version,
    'normalized_mass_g': normalizedMassG,
  };

  String get arabicUnit =>
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
      }[unitCode] ??
      unitCode;
  String get label =>
      '${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 3)} $arabicUnit — ${price.toStringAsFixed(2)} YER';
}

const int _maximumCanonicalInteger = 9007199254740991;

int _canonicalInteger(
  Object? value, {
  required String field,
  int minimum = -_maximumCanonicalInteger,
  int maximum = _maximumCanonicalInteger,
}) {
  int parsed;
  if (value is int) {
    parsed = value;
  } else if (value is String &&
      RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(value)) {
    final asBigInt = BigInt.tryParse(value);
    if (asBigInt == null ||
        asBigInt < BigInt.from(minimum) ||
        asBigInt > BigInt.from(maximum)) {
      throw FormatException('$field is outside the supported integer range');
    }
    parsed = asBigInt.toInt();
  } else {
    throw FormatException('$field must be a canonical integer');
  }
  if (parsed < minimum || parsed > maximum) {
    throw FormatException('$field is outside the supported integer range');
  }
  return parsed;
}
