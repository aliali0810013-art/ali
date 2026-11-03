/// Parses user quantities exactly, including Arabic/Persian digits; never truncates extra decimals.
class ReturnQuantity {
  const ReturnQuantity._();
  static int? milli(String raw) {
    var value = raw.trim().replaceAll('٫', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 1000) return null;
    final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0'));
    final result = whole * 1000 + fraction;
    return result <= 1000000 ? result : null;
  }
}
