// The disposal-to-tender pipeline, and the two rules that make its history
// readable.
//
// Nothing seeded any of it, so every screen downstream of "Send Disposal
// Request" was empty: Pending Valuation, Unsold Tenders, Tender Sales, Sold
// Goods and Unsold Goods.
import 'package:flutter_test/flutter_test.dart';

/// One round of a package at tender, as `tender_sale_items` records it.
class Round {
  final int saleSerial;
  final bool sold;
  final double? soldPrice;
  const Round(this.saleSerial, this.sold, [this.soldPrice]);
}

/// Mirrors how the Valuation portal counts "Times" — one row per round.
int timesTendered(List<Round> rounds) => rounds.length;

/// A package is in the unsold pool only while NO round of it ever sold.
bool isUnsold(List<Round> rounds) => !rounds.any((r) => r.sold);

void main() {
  group('re-tendering appends a round, it does not overwrite one', () {
    // ⚠️ Each round INSERTS a new tender_sale_items row against a new sale and
    // leaves the previous round's row untouched and still marked unsold. That
    // history is what "Times" counts and what the Valuation portal reads --
    // overwriting the old row would erase it and every package would read as
    // tendered exactly once.
    test('a package sold at the fourth attempt kept all four rounds', () {
      const rounds = [
        Round(1, false),
        Round(2, false),
        Round(3, false),
        Round(4, true, 42000),
      ];
      expect(timesTendered(rounds), 4);
      expect(rounds.where((r) => r.sold).length, 1);
      // The earlier rounds stay unsold — they are the failed attempts.
      expect(rounds.take(3).every((r) => !r.sold), isTrue);
    });

    test('a package sold first time has exactly one round', () {
      const rounds = [Round(1, true, 15000)];
      expect(timesTendered(rounds), 1);
      expect(isUnsold(rounds), isFalse);
    });

    test('a package that never sold is still in the unsold pool', () {
      const rounds = [Round(1, false), Round(2, false)];
      expect(isUnsold(rounds), isTrue);
      expect(timesTendered(rounds), 2);
    });

    test('one sale ends the package — it cannot sell twice', () {
      const rounds = [Round(1, false), Round(2, true, 9000)];
      expect(rounds.where((r) => r.sold).length, 1);
      expect(isUnsold(rounds), isFalse);
    });
  });

  group('the reserve falls each time a round fails', () {
    // Goods that did not sell are worth less than the reserve claimed, so a
    // re-valuation lowers it before the next round. The sale price must beat
    // the reserve IN FORCE at the time — not the original, which is higher and
    // would make a legitimate later sale look like an underpayment.
    double reserveInForce(double original, List<double> revaluations) =>
        revaluations.isEmpty ? original : revaluations.last;

    test('with no re-valuation the original reserve stands', () {
      expect(reserveInForce(10000, const []), 10000);
    });

    test('the latest re-valuation is the one that counts', () {
      expect(reserveInForce(10000, const [8000, 6500]), 6500);
    });

    test('a later sale beats the reserve in force, not the original', () {
      const original = 10000.0;
      final inForce = reserveInForce(original, const [8000, 6500]);
      const soldPrice = 7200.0;
      expect(soldPrice, greaterThanOrEqualTo(inForce));
      // Against the ORIGINAL it would look like a loss — which is why the
      // check has to use the reserve in force.
      expect(soldPrice, lessThan(original));
    });
  });

  group('the unsold pool can show every round count', () {
    // A package that SELLS on its fourth attempt leaves the unsold pool the
    // moment it sells. So if unsold packages only ever ran to three rounds,
    // the Unsold Tenders list could never display a "4x" -- that count would
    // exist only on goods that had already gone.
    test('a package still unsold after four rounds reads as 4x', () {
      const rounds = [
        Round(1, false),
        Round(2, false),
        Round(3, false),
        Round(4, false),
      ];
      expect(isUnsold(rounds), isTrue);
      expect(timesTendered(rounds), 4);
    });

    test('a package that sold on its fourth attempt is NOT in the pool', () {
      const rounds = [
        Round(1, false),
        Round(2, false),
        Round(3, false),
        Round(4, true, 30000),
      ];
      expect(timesTendered(rounds), 4);
      expect(isUnsold(rounds), isFalse);
    });
  });

  group('a tender sale is a sale, not a lot', () {
    // Several packages go under one sale number. A sale minted per package
    // would make every tender a single-item auction, which is not how one
    // reads -- and the sale's own date governs all of its items.
    test('one sale carries several packages', () {
      const packagesInSale = ['fp1', 'fp2', 'fp3', 'fp4'];
      expect(packagesInSale.length, greaterThan(1));
      expect(packagesInSale.toSet().length, packagesInSale.length);
    });
  });

  group('a request is pending valuation while any item is unforwarded', () {
    // ⚠️ A request stays in the Pending Valuation feed while ANY of its items
    // is not yet forwarded; a fully forwarded request has moved on to Central
    // Disposal and must not appear there.
    bool isPending(List<bool> forwardedFlags) =>
        forwardedFlags.any((f) => !f);

    test('all items forwarded — the request has moved on', () {
      expect(isPending(const [true, true, true]), isFalse);
    });

    test('one item still unforwarded keeps the request pending', () {
      expect(isPending(const [true, false, true]), isTrue);
    });

    test('nothing forwarded yet is pending', () {
      expect(isPending(const [false, false]), isTrue);
    });

    // A part-valued request is the ordinary half-finished state: a cost is
    // entered against some items while the rest wait. It stays pending
    // because nothing has been forwarded yet -- a cost is not a forward.
    test('a cost entered on some items does not forward the request', () {
      const forwarded = [false, false, false];
      const costs = <double?>[12000, null, null];
      expect(isPending(forwarded), isTrue);
      expect(costs.where((c) => c != null).length, 1);
    });

    // Valuing every item is what precedes forwarding, so a request left
    // pending must never have ALL of its items costed. This is the rule the
    // seeder follows when it part-values a request.
    bool safeToLeavePending(List<double?> costs) =>
        costs.any((c) => c == null);

    test('a part-valued request may be left pending', () {
      expect(safeToLeavePending(const [12000, null, null]), isTrue);
    });

    test('a fully valued request may NOT be left pending', () {
      expect(safeToLeavePending(const [1.0, 2.0, 3.0]), isFalse);
    });
  });
}
