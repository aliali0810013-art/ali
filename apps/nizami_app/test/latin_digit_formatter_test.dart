import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/core/formatters/latin_digit_formatter.dart';

void main() {
  test('normalizes Arabic and Persian digits without changing value', () {
    expect(normalizeDigitsToEnglish('١٢٣٤٥٦٧٨٩٠'), '1234567890');
    expect(normalizeDigitsToEnglish('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    expect(normalizeDigitsToEnglish('-١٢٬٣٤٥٫٦٧'), '-12,345.67');
  });

  test('formatter keeps cursor and composing range', () {
    const formatter = LatinDigitTextInputFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '١٢.٥٠',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(value.text, '12.50');
    expect(value.selection.baseOffset, 5);
  });
}
