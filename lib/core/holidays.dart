/// Working-day / holiday calendar for tender-sale & destruction deadlines.
///
/// The "Sell within" / "Destroy within" window ends on the day AFTER the sale
/// date — BUT if that day (or any day up to it) is a weekend or a public
/// holiday, the office is closed and the officer cannot mark the item. So the
/// deadline is pushed forward to the END of the next actual WORKING day, so the
/// countdown always lands on a day the officer is in office.
///
/// Weekend = Saturday + Sunday (Sri Lanka Customs works Mon–Fri).
///
/// Public holidays: the app is online, so on startup they are fetched from the
/// free Nager.Date public-holiday API for Sri Lanka (`LK`) — no key needed —
/// and merged into [_runtimeHolidays]. The static [kHolidays] list is the
/// offline fallback (and covers poya/gazetted days the API may miss); edit it
/// yearly as a safety net.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Holidays fetched from the API at runtime (merged with [kHolidays]).
final Set<String> _runtimeHolidays = {};

/// Sri Lanka public / bank / mercantile holidays, as `yyyy-MM-dd`.
/// Offline fallback — also add any poya/gazetted days the API misses.
const Set<String> kHolidays = {
  // ── 2026 (fixed-date safety net; the API adds/overrides poya & gazetted) ──
  '2026-01-03', // Duruthu Full Moon Poya
  '2026-02-01', // Nawam Full Moon Poya
  '2026-02-04', // National Day
  '2026-03-03', // Medin Full Moon Poya
  '2026-04-01', // Bak Full Moon Poya
  '2026-04-13', // Day before Sinhala & Tamil New Year
  '2026-04-14', // Sinhala & Tamil New Year
  '2026-05-01', // May Day
  '2026-05-02', // Day after Vesak
  '2026-05-30', // Poson Full Moon Poya
  '2026-06-29', // Esala Full Moon Poya
  '2026-07-28', // Nikini Full Moon Poya
  '2026-08-26', // Binara Full Moon Poya
  '2026-09-24', // Vap Full Moon Poya
  '2026-10-23', // Il Full Moon Poya
  '2026-11-24', // Undurwap Full Moon Poya
  '2026-12-25', // Christmas Day
  // ── Add 2027+ here each year ─────────────────────────────────────────────
};

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// True when [d] is a non-working day (Saturday, Sunday, or a public holiday —
/// from the API-fetched set or the static fallback).
bool isNonWorkingDay(DateTime d) {
  if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    return true;
  }
  final k = _key(d);
  return _runtimeHolidays.contains(k) || kHolidays.contains(k);
}

/// Fetch Sri Lanka public holidays for the current & next few years from the
/// free Nager.Date API and merge them into the runtime set. Call once at
/// startup. Silently no-ops on any failure (the static [kHolidays] fallback and
/// weekend rule still apply), so it never blocks the app.
Future<void> loadPublicHolidays() async {
  final year = DateTime.now().year;
  for (final y in [year, year + 1]) {
    try {
      final res = await http
          .get(Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$y/LK'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) continue;
      final data = jsonDecode(res.body);
      if (data is List) {
        for (final e in data) {
          final d = (e is Map) ? e['date'] as String? : null;
          if (d != null && d.length >= 10) _runtimeHolidays.add(d.substring(0, 10));
        }
      }
    } catch (_) {
      // Offline / API down / timeout — keep the static fallback.
    }
  }
}

/// The next actual WORKING day on or after [from] (date-only).
DateTime nextWorkingDay(DateTime from) {
  var d = DateTime(from.year, from.month, from.day);
  while (isNonWorkingDay(d)) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// The unsold/undestroyed deadline for a sale placed on [saleDate]:
/// the END (23:59:59.999) of the next working day AFTER the sale date.
/// Weekends and public holidays after the sale are skipped, so the deadline
/// always lands on a day the office is open.
DateTime workingDeadline(DateTime saleDate) {
  // Start from the day after the sale (the current "+1 day" base window) …
  final base = DateTime(saleDate.year, saleDate.month, saleDate.day + 1);
  // … then roll forward to the next working day if that lands on a closed day.
  final day = nextWorkingDay(base);
  return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}
