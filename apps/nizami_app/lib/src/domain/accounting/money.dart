class Money {
  const Money(this.minorUnits, {this.scale = 2});
  final int minorUnits;
  final int scale;

  Money operator +(Money other) {
    _sameScale(other);
    return Money(minorUnits + other.minorUnits, scale: scale);
  }

  Money operator -(Money other) {
    _sameScale(other);
    return Money(minorUnits - other.minorUnits, scale: scale);
  }

  Money multiply(int quantity) => Money(minorUnits * quantity, scale: scale);
  bool get isNegative => minorUnits < 0;

  void _sameScale(Money other) {
    if (scale != other.scale) throw ArgumentError('Money scales must match');
  }

  @override
  bool operator ==(Object other) =>
      other is Money && minorUnits == other.minorUnits && scale == other.scale;
  @override
  int get hashCode => Object.hash(minorUnits, scale);
}
