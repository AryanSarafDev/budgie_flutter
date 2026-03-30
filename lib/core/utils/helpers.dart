DateTime monthStart(DateTime value) => DateTime(value.year, value.month, 1);
DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

T? firstOrNull<T>(Iterable<T> values) {
  for (final value in values) {
    return value;
  }
  return null;
}

double toDoubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

int toIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

double round2(double value) => (value * 100).roundToDouble() / 100;
