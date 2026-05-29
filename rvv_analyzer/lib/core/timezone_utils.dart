class TimezoneUtils {
  /// Converts a [DateTime] in German local time (Europe/Berlin) to UTC.
  /// This takes into account Europe/Berlin daylight saving time rules.
  static DateTime convertGermanLocalToUtc(DateTime localTime) {
    if (localTime.isUtc) {
      return localTime;
    }

    final year = localTime.year;

    // Europe/Berlin Daylight Saving Time starts on the last Sunday of March.
    // Clocks go forward from 02:00 local time (01:00 UTC) to 03:00 local time.
    var marchLastSunday = DateTime(year, 3, 31);
    while (marchLastSunday.weekday != DateTime.sunday) {
      marchLastSunday = marchLastSunday.subtract(const Duration(days: 1));
    }
    final dstStart = DateTime(year, 3, marchLastSunday.day, 2);

    // Europe/Berlin Daylight Saving Time ends on the last Sunday of October.
    // Clocks go backward from 03:00 local time (01:00 UTC) to 02:00 local time.
    var octoberLastSunday = DateTime(year, 10, 31);
    while (octoberLastSunday.weekday != DateTime.sunday) {
      octoberLastSunday = octoberLastSunday.subtract(const Duration(days: 1));
    }
    final dstEnd = DateTime(year, 10, octoberLastSunday.day, 3);

    final isDst = localTime.isAfter(dstStart) && localTime.isBefore(dstEnd);
    final offsetHours = isDst ? 2 : 1;
    return localTime.subtract(Duration(hours: offsetHours));
  }
}
