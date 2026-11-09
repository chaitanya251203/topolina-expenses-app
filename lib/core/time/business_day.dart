/// UTC-encoded calendar labels; never depend on the phone's timezone.
/// UI convenience only: backend time independently authorizes all writes.
abstract final class BusinessDay {
  static DateTime indiaTime(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  static List<DateTime> eligibleDates(DateTime instant) {
    final india = indiaTime(instant);
    final today = DateTime.utc(india.year, india.month, india.day);
    return [today, if (india.hour < 1) today.subtract(const Duration(days: 1))];
  }

  static String label(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
