import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/products/unit_conversion_math.dart';

void main() {
  test('milligrams use one final rounding', () {
    expect(
      ExactUnitPrice.grossMinor(
        quantityMilli: 250000,
        priceNumeratorMinor: 500000,
        priceDenominator: 1000000,
      ),
      125,
    );
  });

  test('non-divisible carton conserves the total', () {
    expect(
      ExactUnitPrice.grossMinor(
        quantityMilli: 24000,
        priceNumeratorMinor: 100000,
        priceDenominator: 24,
      ),
      100000,
    );
  });

  test('derived decimal is display-only exact rational text', () {
    expect(
      ExactUnitPrice.derivedDecimal(
        priceNumeratorMinor: 500000,
        priceDenominator: 1000000,
      ),
      '0.5',
    );
  });

  test('zero and negative ratios are rejected', () {
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 0,
        priceNumeratorMinor: 1,
        priceDenominator: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: -1,
        priceNumeratorMinor: 1,
        priceDenominator: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1,
        priceNumeratorMinor: 0,
        priceDenominator: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1,
        priceNumeratorMinor: -1,
        priceDenominator: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1,
        priceNumeratorMinor: 1,
        priceDenominator: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1,
        priceNumeratorMinor: 1,
        priceDenominator: -1,
      ),
      throwsArgumentError,
    );
  });

  test('gross above the invoice limit is rejected', () {
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1000000,
        priceNumeratorMinor: 1000000001,
        priceDenominator: 1,
      ),
      throwsArgumentError,
    );
  });

  test('positive ratio that rounds to zero is rejected', () {
    expect(
      () => ExactUnitPrice.grossMinor(
        quantityMilli: 1,
        priceNumeratorMinor: 1,
        priceDenominator: 3,
      ),
      throwsArgumentError,
    );
  });

  test('invoice limit boundaries are accepted', () {
    expect(
      ExactUnitPrice.grossMinor(
        quantityMilli: 1000,
        priceNumeratorMinor: 1,
        priceDenominator: 1,
      ),
      1,
    );
    expect(
      ExactUnitPrice.grossMinor(
        quantityMilli: 1000,
        priceNumeratorMinor: 1000000000000,
        priceDenominator: 1,
      ),
      1000000000000,
    );
  });
}
