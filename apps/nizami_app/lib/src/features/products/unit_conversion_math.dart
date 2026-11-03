/// Exact rational pricing for configured product units.
///
/// Display decimals are deliberately separate from the integer gross used for
/// invoice requests and ledger arithmetic.
abstract final class ExactUnitPrice {
  static final BigInt _quantityScale = BigInt.from(1000);
  static final BigInt _maxInvoiceTotalMinor = BigInt.from(1000000000000);
  static final BigInt _displayScale = BigInt.from(1000000);

  static int grossMinor({
    required int quantityMilli,
    required int priceNumeratorMinor,
    required int priceDenominator,
  }) {
    _validate(
      quantityMilli: quantityMilli,
      priceNumeratorMinor: priceNumeratorMinor,
      priceDenominator: priceDenominator,
    );

    final denominator = BigInt.from(priceDenominator) * _quantityScale;
    final gross =
        (BigInt.from(quantityMilli) * BigInt.from(priceNumeratorMinor) +
            denominator ~/ BigInt.two) ~/
        denominator;
    if (gross < BigInt.one || gross > _maxInvoiceTotalMinor) {
      throw ArgumentError.value(gross, 'gross', 'Exceeds invoice limit');
    }

    return gross.toInt();
  }

  /// Returns a six-decimal, trimmed display of the price in minor units.
  static String derivedDecimal({
    required int priceNumeratorMinor,
    required int priceDenominator,
  }) {
    _validate(
      quantityMilli: 1,
      priceNumeratorMinor: priceNumeratorMinor,
      priceDenominator: priceDenominator,
    );

    final denominator = BigInt.from(priceDenominator);
    final scaled =
        (BigInt.from(priceNumeratorMinor) * _displayScale +
            denominator ~/ BigInt.two) ~/
        denominator;
    final whole = scaled ~/ _displayScale;
    final fractional = scaled % _displayScale;
    if (fractional == BigInt.zero) {
      return whole.toString();
    }

    return '$whole.${fractional.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }

  static void _validate({
    required int quantityMilli,
    required int priceNumeratorMinor,
    required int priceDenominator,
  }) {
    if (quantityMilli < 1 || priceNumeratorMinor < 1 || priceDenominator < 1) {
      throw ArgumentError('Invalid rational unit price');
    }
  }
}
