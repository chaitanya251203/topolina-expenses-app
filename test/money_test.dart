import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/core/accounting/money.dart';

void main() {
  test(
    'aggregations reject overflow instead of wrapping a financial total',
    () {
      const value = Reconciliation(
        expected: Money(0),
        cash: Money(9223372036854775807),
        online: Money(1),
        other: Money(0),
        paid: Money(0),
      );
      expect(() => value.collectionsPaise, throwsRangeError);
    },
  );
  test(
    'amount parsing preserves paise exactly and rejects invalid precision',
    () {
      expect(Money.parse('100.50').paise, 10050);
      expect(Money.parse('0.1').paise, 10);
      expect(Money.parse(' 15000 ').formatted, '₹15,000.00');
      expect(Money(123456789).formatted, '₹12,34,567.89');
      expect(const Money(-501).formatted, '-₹5.01');
      for (final input in [
        '1.001',
        '-1',
        'NaN',
        '1e3',
        '1,000',
        '',
        '92233720368547758.08',
      ]) {
        expect(() => Money.parse(input), throwsFormatException);
      }
      expect(Money.parse('92233720368547758.07').paise, 9223372036854775807);
    },
  );
  test(
    'fractional quantities round once, half up, without binary arithmetic',
    () {
      expect(
        Money.calculate(quantity: '2.5', rate: Money.parse('80.50')).paise,
        20125,
      );
      expect(
        Money.calculate(quantity: '1.005', rate: Money.parse('1')).paise,
        101,
      );
      expect(
        Money.calculate(quantity: '0.333333', rate: Money.parse('3')).paise,
        100,
      );
      for (final quantity in ['0', '-1', '1.0000001', 'NaN']) {
        expect(
          () => Money.calculate(quantity: quantity, rate: const Money(100)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'reconciliation uses entered net collections and actual paid expenses',
    () {
      const balanced = Reconciliation(
        expected: Money(1000000),
        cash: Money(500000),
        online: Money(350000),
        other: Money(50000),
        paid: Money(100000),
      );
      expect(balanced.differencePaise, 0);
      expect(balanced.status, BalanceStatus.balanced);
      const short = Reconciliation(
        expected: Money(10000),
        cash: Money(9000),
        online: Money(0),
        other: Money(0),
        paid: Money(500),
      );
      expect(short.differencePaise, 500);
      expect(short.status, BalanceStatus.short);
      const excess = Reconciliation(
        expected: Money(10000),
        cash: Money(9000),
        online: Money(0),
        other: Money(0),
        paid: Money(1500),
      );
      expect(excess.status, BalanceStatus.excess);
    },
  );
}
