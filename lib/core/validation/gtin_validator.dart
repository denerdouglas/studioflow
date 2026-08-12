class GtinValidator {
  const GtinValidator._();

  static String normalize(String input) => input.replaceAll(RegExp(r'\D'), '');

  static bool isValid(String input) {
    final value = normalize(input);
    if (!const {8, 12, 13, 14}.contains(value.length)) return false;
    final digits = value.codeUnits.map((unit) => unit - 48).toList();
    if (digits.any((digit) => digit < 0 || digit > 9)) return false;
    final checkDigit = digits.removeLast();
    var sum = 0;
    for (
      var index = digits.length - 1, position = 0;
      index >= 0;
      index--, position++
    ) {
      sum += digits[index] * (position.isEven ? 3 : 1);
    }
    return (10 - sum % 10) % 10 == checkDigit;
  }

  static bool isExactMatch(String requested, String returned) {
    final expected = normalize(requested);
    final actual = normalize(returned);
    return isValid(expected) && isValid(actual) && expected == actual;
  }
}
