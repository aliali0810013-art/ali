import 'package:flutter/services.dart';

/// Converts Arabic-Indic and Persian digits to ASCII without changing the
/// numeric value, decimal separator, sign, selection or composing range.
String normalizeDigitsToEnglish(String value) => value
    .replaceAllMapped(RegExp(r'[٠-٩۰-۹]'), (match) {
      const arabic = '٠١٢٣٤٥٦٧٨٩';
      const persian = '۰۱۲۳۴۵۶۷۸۹';
      final character = match.group(0)!;
      final arabicIndex = arabic.indexOf(character);
      return '${arabicIndex >= 0 ? arabicIndex : persian.indexOf(character)}';
    })
    .replaceAll('٫', '.')
    .replaceAll('٬', ',');

class LatinDigitTextInputFormatter extends TextInputFormatter {
  const LatinDigitTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalizeDigitsToEnglish(newValue.text);
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(text: normalized);
  }
}

const latinDigitFormatter = LatinDigitTextInputFormatter();
