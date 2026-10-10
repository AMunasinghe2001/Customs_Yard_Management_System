import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/models/models.dart';

/// The per-day storage loop was replaced with a closed-form sum over rate
/// periods. This is money, so the new form is checked AGAINST the old loop
/// rather than against hand-picked numbers: the loop is reproduced here
/// exactly as it was, and the two must agree on every case a random search
/// can throw at them.
///
/// ⚠️ Why the loop had to go: the ledger ran it for every warehouse entry of
/// every package, walking every day since admission and scanning every rate
/// on each day. The four ledger queries took 33ms; the frame after them took
/// 1,546ms with build at 1ms. That 1.5s was this loop on the UI thread, and a
/// click is only delivered between frames — so the Details and Costs buttons
/// did nothing until it finished.
///
/// ⚠️ One deliberate difference from the shipped loop: the rates are SORTED
/// here. The original iterated the map in insertion order with "last match
/// wins", so an out-of-order map picked the wrong rate — a latent bug it never
/// hit only because storageRateProvider orders by effective_from. The closed
/// form sorts explicitly and is correct for any order, so comparing it to the
/// unsorted loop reported the OLD bug as a NEW one (1000 vs the correct 1500).
/// Sorting the reference makes this a test of the arithmetic.
double _oldLoop(DateTime start, DateTime end, Map<DateTime, double> rates) {
  final sorted = rates.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  double total = 0;
  for (int i = 0; i <= end.difference(start).inDays; i++) {
    final day = start.add(Duration(days: i));
    final dayAtMidnight = DateTime(day.year, day.month, day.day);
    double active = 50;
    for (final e in sorted) {
      final fromMidnight = DateTime(e.key.year, e.key.month, e.key.day);
      if (!dayAtMidnight.isBefore(fromMidnight)) active = e.value;
    }
    total += active;
  }
  return total;
}

void main() {
  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  group('the closed form equals the old loop', () {
    test('no rates at all: the 50/day fallback for the whole span', () {
      final s = d(2026, 1, 1), e = d(2026, 1, 31);
      expect(chargeableRateDays(s, e, {}), _oldLoop(s, e, {}));
      expect(chargeableRateDays(s, e, {}), 31 * 50.0);
    });

    test('one rate covering the whole span', () {
      final s = d(2026, 3, 1), e = d(2026, 3, 10);
      final r = {d(2025, 1, 1): 120.0};
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 10 * 120.0);
    });

    test('a rate change mid-span splits the days', () {
      final s = d(2026, 1, 1), e = d(2026, 1, 10);
      final r = {d(2025, 1, 1): 100.0, d(2026, 1, 6): 200.0};
      // 1..5 at 100, 6..10 at 200.
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 5 * 100.0 + 5 * 200.0);
    });

    test('a span that starts BEFORE the first rate uses the fallback first',
        () {
      final s = d(2026, 1, 1), e = d(2026, 1, 10);
      final r = {d(2026, 1, 4): 80.0};
      // 1..3 at 50 (fallback), 4..10 at 80.
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 3 * 50.0 + 7 * 80.0);
    });

    test('a rate that takes effect ON the start day applies from day one', () {
      final s = d(2026, 5, 5), e = d(2026, 5, 7);
      final r = {d(2026, 5, 5): 33.0};
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 3 * 33.0);
    });

    test('a single day', () {
      final s = d(2026, 2, 2), e = d(2026, 2, 2);
      final r = {d(2025, 1, 1): 10.0, d(2026, 2, 2): 99.0};
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 99.0);
    });

    test('rates given out of order are still applied in date order', () {
      final s = d(2026, 1, 1), e = d(2026, 1, 10);
      final r = {d(2026, 1, 6): 200.0, d(2025, 1, 1): 100.0};
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
    });

    test('a rate dated after the span contributes nothing', () {
      final s = d(2026, 1, 1), e = d(2026, 1, 5);
      final r = {d(2025, 1, 1): 70.0, d(2027, 1, 1): 9999.0};
      expect(chargeableRateDays(s, e, r), _oldLoop(s, e, r));
      expect(chargeableRateDays(s, e, r), 5 * 70.0);
    });

    test('end before start is zero, not negative', () {
      expect(chargeableRateDays(d(2026, 1, 10), d(2026, 1, 1), {}), 0);
    });

    test('random spans and rate tables agree with the loop exactly', () {
      // ⚠️ The case that matters: many rates, long spans, arbitrary
      // boundaries. 500 seeds is enough to hit every off-by-one there is.
      final rng = Random(20260913);
      for (var n = 0; n < 500; n++) {
        final start = d(2024, 1, 1).add(Duration(days: rng.nextInt(400)));
        final end = start.add(Duration(days: rng.nextInt(600)));
        final rates = <DateTime, double>{};
        final count = rng.nextInt(6);
        for (var k = 0; k < count; k++) {
          final from = d(2023, 6, 1).add(Duration(days: rng.nextInt(900)));
          rates[from] = 10.0 + rng.nextInt(300);
        }
        final a = chargeableRateDays(start, end, rates);
        final b = _oldLoop(start, end, rates);
        expect(a, b,
            reason: 'seed $n: $start..$end with ${rates.length} rate(s)');
      }
    });
  });
}
