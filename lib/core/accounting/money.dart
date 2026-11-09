/// Exact paise arithmetic. No financial parsing passes through a double.
class Money {
  const Money(this.paise);
  final int paise;

  factory Money.parse(String input) {
    final match = RegExp(r'^([0-9]+)(?:\.([0-9]{1,2}))?$')
        .firstMatch(input.trim());
    if (match == null) {
      throw const FormatException(
        'Enter an amount with up to two decimal places.',
      );
    }
    return Money(
      _checkedInt(
        BigInt.parse(match[1]!) * BigInt.from(100) +
            BigInt.parse((match[2] ?? '').padRight(2, '0')),
      ),
    );
  }

  /// Quantity permits six fractional digits. Round once, half up, to paise.
  static Money calculate({required String quantity, required Money rate}) {
    final match = RegExp(r'^([0-9]+)(?:\.([0-9]{1,6}))?$')
        .firstMatch(quantity.trim());
    if (match == null || rate.paise <= 0) {
      throw const FormatException('Enter a positive quantity and rate.');
    }
    final scaled =
        BigInt.parse(match[1]!) * BigInt.from(1000000) +
        BigInt.parse((match[2] ?? '').padRight(6, '0'));
    if (scaled <= BigInt.zero) {
      throw const FormatException('Quantity must be positive.');
    }
    return Money(
      _checkedInt(
        (scaled * BigInt.from(rate.paise) + BigInt.from(500000)) ~/
            BigInt.from(1000000),
      ),
    );
  }

  static int _checkedInt(BigInt value) {
    if (value > BigInt.parse('9223372036854775807') || value < BigInt.zero) {
      throw const FormatException('Amount is too large.');
    }
    return value.toInt();
  }

  String get formatted {
    final absolute = BigInt.from(paise).abs();
    var head = (absolute ~/ BigInt.from(100)).toString();
    final groups = <String>[];
    if (head.length > 3) {
      groups.insert(0, head.substring(head.length - 3));
      head = head.substring(0, head.length - 3);
      while (head.length > 2) {
        groups.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
    }
    groups.insert(0, head);
    final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
    return '${paise < 0 ? '-' : ''}₹${groups.join(',')}.$fraction';
  }
}

enum BalanceStatus { balanced, short, excess }

class Reconciliation {
  const Reconciliation({
    required this.expected,
    required this.cash,
    required this.online,
    required this.other,
    required this.paid,
  });
  final Money expected, cash, online, other, paid;
  int get collectionsPaise => _checkedTotal(
    BigInt.from(cash.paise) +
        BigInt.from(online.paise) +
        BigInt.from(other.paise),
  );
  int get differencePaise => _checkedTotal(
    BigInt.from(expected.paise) -
        BigInt.from(cash.paise) -
        BigInt.from(online.paise) -
        BigInt.from(other.paise) -
        BigInt.from(paid.paise),
  );

  static int _checkedTotal(BigInt value) {
    if (value > BigInt.parse('9223372036854775807') ||
        value < BigInt.parse('-9223372036854775808')) {
      throw RangeError('Financial total exceeds supported paise range.');
    }
    return value.toInt();
  }

  BalanceStatus get status => switch (differencePaise.compareTo(0)) {
    0 => BalanceStatus.balanced,
    1 => BalanceStatus.short,
    _ => BalanceStatus.excess,
  };
}
