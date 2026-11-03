import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nizami/src/features/invoices/weighted_sale_math.dart';
import 'package:nizami/src/features/invoices/invoice_pdf_service.dart';
import 'package:nizami/src/features/products/product_catalog_store.dart';
import 'package:nizami/src/features/products/unit_conversion_math.dart';

void main() {
  test('500 YER cumin at 5000 per kilo is 100 grams, exactly 500 YER', () {
    final quote = WeightedSaleMath.quote(
      targetMinor: 50000,
      priceMinor: 500000,
      stockUnitName: 'كيلو',
    );
    expect(quote.quantityMilli, 100);
    expect(quote.gramsMilli, 100000);
    expect(quote.totalMinor, 50000);
    expect(quote.lineDiscountMinor, 0);
  });

  test('rounding to grams retains the requested amount without tax fraud', () {
    final quote = WeightedSaleMath.quote(
      targetMinor: 50000,
      priceMinor: 300000,
      stockUnitName: 'kilogram',
    );
    expect(quote.quantityMilli, 167);
    expect(quote.gramsMilli, 167000);
    expect(quote.grossMinor, 50100);
    expect(quote.lineDiscountMinor, 100);
    final line = InvoiceLine(
      name: 'كمون',
      quantity: quote.quantity,
      unitPrice: 3000,
      lineDiscountMinor: quote.lineDiscountMinor,
      weightGramsMilli: quote.gramsMilli,
    );
    expect(line.totalMinor, 50000);
    expect(InvoiceLine.fromJson(line.toJson()).totalMinor, 50000);
  });

  test(
    'sale options convert to grams and keep 3-decimal option quantities',
    () {
      final quote = WeightedSaleMath.quote(
        targetMinor: 10000,
        priceMinor: 20000,
        stockUnitName: 'جرام',
        optionMassGramsMillionths: 100000000, // one option = 100 g
      );
      expect(quote.quantityMilli, 500);
      expect(quote.gramsMilli, 50000);
    },
  );

  test(
    'money parsing and item shortcuts remain exact and backward compatible',
    () {
      expect(WeightedSaleMath.moneyMinor('500'), 50000);
      expect(WeightedSaleMath.moneyMinor('500.25'), 50025);
      expect(WeightedSaleMath.moneyMinor('0'), isNull);
      expect(WeightedSaleMath.moneyMinor('50.123'), isNull);
      expect(WeightedSaleMath.isMassUnit('وحدة'), false);
      expect(WeightedSaleMath.isMassUnit('كيلو'), true);
      final product = CatalogProduct.fromServer({
        'id': 'sku-1',
        'name': 'كمون',
        'sku': '123',
        'unit_name': 'كيلو',
        'sale_price_minor': 500000,
      });
      expect(product.sku, '123');
      expect(CatalogProduct.fromJson(product.toJson()).sku, '123');
    },
  );

  test('editing a cached product does not erase its SKU shortcut', () async {
    SharedPreferences.setMockInitialValues({});
    final catalog = ProductCatalogStore('stage5-sku-local-cache-test');
    await catalog.save(
      const CatalogProduct(
        id: 'product-stable-id',
        sku: '101',
        name: 'كمون',
        purchasePrice: 1000,
        salePrice: 5000,
        barcode: '123456',
        unitName: 'كيلو',
      ),
    );
    await catalog.save(
      const CatalogProduct(
        id: 'product-stable-id',
        name: 'كمون',
        purchasePrice: 1100,
        salePrice: 5100,
        barcode: '123456',
        unitName: 'كيلو',
      ),
    );
    final products = await catalog.read();
    expect(products, hasLength(1));
    expect(products.single.sku, '101');
  });

  test('zero amount and unknown stock units are rejected', () {
    expect(
      () => WeightedSaleMath.quote(
        targetMinor: 0,
        priceMinor: 10000,
        stockUnitName: 'كيلو',
      ),
      throwsArgumentError,
    );
    expect(
      () => WeightedSaleMath.quote(
        targetMinor: 10000,
        priceMinor: 10000,
        stockUnitName: 'قطعة',
      ),
      throwsArgumentError,
    );
  });

  test('sale by amount uses the rational option price, not its preview', () {
    final quote = WeightedSaleMath.quote(
      targetMinor: 125,
      priceMinor: 1,
      priceNumeratorMinor: 500000,
      priceDenominator: 1000000,
      stockUnitName: 'gram',
      optionMassGramsMillionths: 1000,
    );

    expect(quote.quantityMilli, 250000);
    expect(quote.totalMinor, 125);
    expect(quote.grossMinor, 125);
    expect(quote.lineDiscountMinor, 0);
    expect(quote.gramsMilli, 250);
  });

  test('250 milligrams at 5000 YER per kilogram round once to 1.25 YER', () {
    expect(
      ExactUnitPrice.grossMinor(
        quantityMilli: 250000,
        priceNumeratorMinor: 500000,
        priceDenominator: 1000000,
      ),
      125,
    );
    final line = InvoiceLine(
      name: 'كمون',
      quantity: 250,
      unitPrice: 0.01,
      displayUnit: 'ملليجرام',
      exactQuantityMilli: 250000,
      priceNumeratorMinor: 500000,
      priceDenominator: 1000000,
    );
    expect(line.totalMinor, 125);
    expect(line.displayQuantity, '250 ملليجرام');
  });
}
