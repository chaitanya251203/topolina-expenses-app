import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/core/time/business_day.dart';

void main() {
  test('calendar rolls over at India midnight; yesterday is explicit in grace window', () {
    expect(BusinessDay.eligibleDates(DateTime.parse('2026-11-08T18:29:59Z')), [
      DateTime.utc(2026, 11, 8),
    ]);
    expect(BusinessDay.eligibleDates(DateTime.parse('2026-11-08T18:30:00Z')), [
      DateTime.utc(2026, 11, 9),
      DateTime.utc(2026, 11, 8),
    ]);
  });
  test('cutoff ends at exactly 01:00, including month and year boundaries', () {
    expect(
      BusinessDay.eligibleDates(DateTime.parse('2026-11-08T19:29:59Z')).length,
      2,
    );
    expect(BusinessDay.eligibleDates(DateTime.parse('2026-11-08T19:30:00Z')), [
      DateTime.utc(2026, 11, 9),
    ]);
    expect(BusinessDay.eligibleDates(DateTime.parse('2026-12-31T18:45:00Z')), [
      DateTime.utc(2027, 1, 1),
      DateTime.utc(2026, 12, 31),
    ]);
    expect(BusinessDay.eligibleDates(DateTime.parse('2026-02-28T18:45:00Z')), [
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 2, 28),
    ]);
  });
}
