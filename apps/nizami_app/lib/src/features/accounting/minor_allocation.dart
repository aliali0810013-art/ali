/// All arguments and results are minor units. No floating-point multiplication.
abstract final class MinorAllocation {
  static int lineGross(int quantityMilli, int unitPriceMinor) {
    if (quantityMilli < 1 || unitPriceMinor < 0) {
      throw ArgumentError('Invalid invoice line');
    }
    return ((BigInt.from(quantityMilli) * BigInt.from(unitPriceMinor) + BigInt.from(500)) ~/ BigInt.from(1000)).toInt();
  }

  /// Cumulative proportional allocation preserves the exact invoice discount.
  static List<int> discount(List<int> gross, int amount) {
    if (amount < 0 || gross.any((value) => value < 0)) throw ArgumentError('Invalid discount');
    final total = gross.fold<BigInt>(BigInt.zero, (sum, value) => sum + BigInt.from(value));
    if (BigInt.from(amount) > total) throw ArgumentError('Discount exceeds invoice value');
    if (total == BigInt.zero) return List<int>.filled(gross.length, 0);
    var cumulative = BigInt.zero;
    var allocated = BigInt.zero;
    return gross.map((value) {
      cumulative += BigInt.from(value);
      final target = BigInt.from(amount) * cumulative ~/ total;
      final part = target - allocated;
      allocated = target;
      return part.toInt();
    }).toList(growable: false);
  }
}
