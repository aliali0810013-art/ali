import '../products/unit_conversion_math.dart';

/// Exact monetary sale-by-amount: no binary floating point for money or stock.
/// The persisted invoice quantity is in 1/1000 of the SKU's own base unit.
/// Product unit_name must be known: a historical 1 kg purchase stays 1 kg.
abstract final class WeightedSaleMath {
  static int? moneyMinor(String raw) {
    final s = raw.trim().replaceAll('٫', '.').replaceAll(',', '.');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (match == null) {
      return null;
    }
    final a = BigInt.parse(match.group(1)!);
    final cents = (match.group(2) ?? '').padRight(2, '0');
    final result =
        a * BigInt.from(100) + BigInt.parse(cents.isEmpty ? '0' : cents);
    if (result <= BigInt.zero || result > BigInt.from(100000000000000)) {
      return null;
    }
    return result.toInt();
  }

  static bool isMassUnit(String value) => isKilogram(value) || isGram(value);
  static bool isKilogram(String value) => const {
    'كيلو',
    'كيلوجرام',
    'كيلوغرام',
    'كيلوجرامات',
    'كجم',
    'kg',
    'kilogram',
    'kilograms',
    'kilo',
  }.contains(value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ''));
  static bool isGram(String value) => const {
    'جرام',
    'جرامات',
    'غرام',
    'غرامات',
    'غم',
    'غ',
    'g',
    'gram',
    'grams',
  }.contains(value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ''));

  /// [optionMassGramsMillionths] is six-decimal fixed-point grams/option.
  /// [quantityMilli] is options * 1000 or product base units * 1000.
  static WeightedSaleQuote quote({
    required int targetMinor,
    required int priceMinor,
    required String stockUnitName,
    int? priceNumeratorMinor,
    int? priceDenominator,
    int? optionMassGramsMillionths,
  }) {
    final hasExactPrice =
        priceNumeratorMinor != null && priceDenominator != null;
    if ((priceNumeratorMinor == null) != (priceDenominator == null) ||
        (hasExactPrice && (priceNumeratorMinor < 1 || priceDenominator < 1))) {
      throw ArgumentError('Incomplete exact unit price');
    }
    if (targetMinor < 1 ||
        targetMinor > 1000000000000 ||
        (!hasExactPrice && priceMinor < 1) ||
        priceMinor > 1000000000 ||
        !isMassUnit(stockUnitName)) {
      throw ArgumentError(
        'يجب تحديد صنف موزون بوحدة كيلو أو جرام وسعر ومبلغ صالحين.',
      );
    }
    if (optionMassGramsMillionths != null && optionMassGramsMillionths < 1) {
      throw ArgumentError('وزن خيار البيع غير صالح.');
    }
    final target = BigInt.from(targetMinor);
    final price = BigInt.from(priceMinor);
    final qty = hasExactPrice
        ? (target * BigInt.from(priceDenominator) * BigInt.from(1000) +
                  BigInt.from(priceNumeratorMinor) -
                  BigInt.one) ~/
              BigInt.from(priceNumeratorMinor)
        : (target * BigInt.from(1000) + price - BigInt.one) ~/ price;
    if (qty < BigInt.one || qty > BigInt.from(1000000)) {
      throw ArgumentError('الكمية أكبر من الحد المسموح.');
    }
    final gross = hasExactPrice
        ? BigInt.from(
            ExactUnitPrice.grossMinor(
              quantityMilli: qty.toInt(),
              priceNumeratorMinor: priceNumeratorMinor,
              priceDenominator: priceDenominator,
            ),
          )
        : (qty * price + BigInt.from(500)) ~/ BigInt.from(1000);
    final adjustment = gross - target;
    if (adjustment < BigInt.zero || adjustment > gross) {
      throw StateError('تعذر حساب سعر ووزن متوافقين.');
    }
    // unit=kg: a milli-kg equals one gram; unit=g: one milli-g.
    final gramsMilli = optionMassGramsMillionths != null
        ? (BigInt.from(optionMassGramsMillionths) * qty +
                  BigInt.from(500000)) ~/
              BigInt.from(1000000)
        : (isKilogram(stockUnitName) ? qty * BigInt.from(1000) : qty);
    if (gramsMilli < BigInt.one || gramsMilli > BigInt.from(1000000000000000)) {
      throw ArgumentError('الوزن الناتج خارج حدود النظام.');
    }
    return WeightedSaleQuote(
      quantityMilli: qty.toInt(),
      grossMinor: gross.toInt(),
      lineDiscountMinor: adjustment.toInt(),
      totalMinor: targetMinor,
      gramsMilli: gramsMilli.toInt(),
    );
  }
}

class WeightedSaleQuote {
  const WeightedSaleQuote({
    required this.quantityMilli,
    required this.grossMinor,
    required this.lineDiscountMinor,
    required this.totalMinor,
    required this.gramsMilli,
  });
  final int quantityMilli;
  final int grossMinor;
  final int lineDiscountMinor;
  final int totalMinor;
  final int gramsMilli;
  double get quantity => quantityMilli / 1000;
  double get grams => gramsMilli / 1000;
}
