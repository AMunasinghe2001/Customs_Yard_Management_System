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

  group('a re-valuation prices the NEXT round, not the current one', () {
    // ⚠️ The app keys re-valuations by round and reads the NULL-keyed one as
    // "the price for the round to come". A figure attached to a sale is that
    // round's own reserve, which every held round already has -- so attaching
    // them all to a sale made every unsold row read "Awaiting value" and
    // nothing ever became re-tenderable.
    String roundKey(String? tenderSaleId) => tenderSaleId ?? '';

    bool isReValued(List<String?> revaluationSaleIds) =>
        revaluationSaleIds.map(roundKey).contains('');

    test('a re-valuation with no sale id prices the next round', () {
      expect(isReValued(const [null]), isTrue);
    });

    test("a re-valuation tied to a sale is that round's own reserve", () {
      expect(isReValued(const ['sale-1', 'sale-2']), isFalse);
    });

    test('past reserves alongside a pending one still read as re-valued', () {
      expect(isReValued(const ['sale-1', 'sale-2', null]), isTrue);
    });
  });

  group('a committee figure is not approved until the ADG submits it', () {
    // Writing the pending re-valuation at committee time would show the
    // package as ready to re-tender before anyone had approved it -- the
    // approval skipped rather than modelled.
    bool readyToReTender(
            {required double? committeeValue, required double? submittedValue}) =>
        committeeValue != null && submittedValue != null;

    test('priced but unsubmitted is NOT ready', () {
      expect(readyToReTender(committeeValue: 50000, submittedValue: null),
          isFalse);
    });

    test('submitted by the ADG is ready', () {
      expect(readyToReTender(committeeValue: 50000, submittedValue: 50000),
          isTrue);
    });
  });

  group('an active tender sale has not closed yet', () {
    // A sale shows on the Tender Sales tab only while it holds an unsold item
    // AND its window is still open. Every seeded sale being in the past is
    // what left that tab empty.
    bool isActive(
            {required bool hasUnsoldItem, required int daysUntilClose}) =>
        hasUnsoldItem && daysUntilClose >= 0;

    test('a sale opening in two days is active', () {
      expect(isActive(hasUnsoldItem: true, daysUntilClose: 2), isTrue);
    });

    test('a closed sale is not active however many items are unsold', () {
      expect(isActive(hasUnsoldItem: true, daysUntilClose: -5), isFalse);
    });

    test('a fully sold sale is not active', () {
      expect(isActive(hasUnsoldItem: false, daysUntilClose: 3), isFalse);
    });
  });

  group('destruction never goes through a disposal request', () {
    // ⚠️ In Final Disposition only SALE raises a disposal request --
    // `_requestActions` is `{'SOLD'}`. Release, Destroy and Re-export are
    // recorded DIRECTLY. There is nothing for the Valuation Directorate to do
    // with goods being destroyed either: they are not being priced for a
    // buyer. Seeding a `disposition: 'destruction'` request put destruction
    // rows on Central Disposal's Disposal Requests tab and in the valuation
    // queue -- a route the app deliberately does not have.
    const requestActions = {'SOLD'};

    bool raisesADisposalRequest(String action) =>
        requestActions.contains(action);

    test('Sale raises a request', () {
      expect(raisesADisposalRequest('SOLD'), isTrue);
    });

    test('Destroy does not', () {
      expect(raisesADisposalRequest('DESTROYED'), isFalse);
    });

    test('Release and Re-export do not either', () {
      expect(raisesADisposalRequest('RELEASED'), isFalse);
      expect(raisesADisposalRequest('RE-EXPORTED'), isFalse);
    });

    // The only disposition a request item may carry.
    test('a request item is always a sale', () {
      const seeded = ['sale', 'sale', 'sale'];
      expect(seeded.every((d) => d == 'sale'), isTrue);
      expect(seeded.contains('destruction'), isFalse);
    });
  });

  group('a request leaves the Disposal Requests tab once it is acted on', () {
    // ⚠️ Central Disposal sees a request only while its packages are still
    // WAITING. The moment they are placed in a tender or a destruction the
    // request drops off -- it has moved on to Tender Sales. Tendering
    // everything that was forwarded is what left the tab empty with 99 items
    // forwarded.
    bool showsOnRequestsTab(
            {required bool forwarded,
            required bool inATender,
            required bool inADestruction}) =>
        forwarded && !inATender && !inADestruction;

    test('forwarded and untouched shows', () {
      expect(
          showsOnRequestsTab(
              forwarded: true, inATender: false, inADestruction: false),
          isTrue);
    });

    test('placed in a tender, it has moved on', () {
      expect(
          showsOnRequestsTab(
              forwarded: true, inATender: true, inADestruction: false),
          isFalse);
    });

    test('placed in a destruction, it has moved on', () {
      expect(
          showsOnRequestsTab(
              forwarded: true, inATender: false, inADestruction: true),
          isFalse);
    });

    test('not yet forwarded, Central Disposal never sees it', () {
      expect(
          showsOnRequestsTab(
              forwarded: false, inATender: false, inADestruction: false),
          isFalse);
    });
  });

  group('goods reach the final Unsold table only when out of road', () {
    // The three conditions, all required:
    //   1. more than kMaxBidTenderRounds (3) rounds have failed,
    //   2. the committee valued it AND the ADG submitted that figure,
    //   3. it was tendered AGAIN at that price, after the submission, and
    //      that round has ENDED still unsold.
    const maxBidRounds = 3;

    bool isExhausted({
      required int rounds,
      required bool everSold,
      required bool adgSubmitted,
      required bool roundRanAfterSubmission,
    }) =>
        rounds > maxBidRounds &&
        !everSold &&
        adgSubmitted &&
        roundRanAfterSubmission;

    test('all three conditions met', () {
      expect(
          isExhausted(
              rounds: 5,
              everSold: false,
              adgSubmitted: true,
              roundRanAfterSubmission: true),
          isTrue);
    });

    // ⚠️ Without the post-submission round the DG would be deciding the fate
    // of goods that still had a live chance of selling.
    test('submitted but never re-tendered is NOT exhausted', () {
      expect(
          isExhausted(
              rounds: 5,
              everSold: false,
              adgSubmitted: true,
              roundRanAfterSubmission: false),
          isFalse);
    });

    // ⚠️ A package sent to committee at 2 rounds can never reach the table,
    // however many rounds follow -- its count is already short.
    test('too few rounds can never qualify', () {
      expect(
          isExhausted(
              rounds: 3,
              everSold: false,
              adgSubmitted: true,
              roundRanAfterSubmission: true),
          isFalse);
    });

    test('the ADG not having submitted stops it', () {
      expect(
          isExhausted(
              rounds: 5,
              everSold: false,
              adgSubmitted: false,
              roundRanAfterSubmission: true),
          isFalse);
    });

    test('a package that sold is never exhausted', () {
      expect(
          isExhausted(
              rounds: 5,
              everSold: true,
              adgSubmitted: true,
              roundRanAfterSubmission: true),
          isFalse);
    });
  });

  group('goods that leave the yard stop occupying a zone', () {
    // ⚠️ Selling does THREE things, and the status update is only one. The
    // yard's own RPC also writes a [FINAL:SOLD] record of sale and DELETES the
    // still-held entry -- goods that have gone must stop filling (and being
    // charged for) a zone. Doing only the status update left 68 sold items
    // still in zones, which makes Zone Capacity overstate what is in the shed.
    const goneStatuses = ['sold', 'destroyed', 're-exported', 'returned'];

    bool stillOccupiesZone(String status, {required bool heldEntryDeleted}) =>
        goneStatuses.contains(status) ? !heldEntryDeleted : true;

    test('a sold item with its held entry cleared occupies nothing', () {
      expect(stillOccupiesZone('sold', heldEntryDeleted: true), isFalse);
    });

    test('a sold item whose held entry survived is the bug', () {
      expect(stillOccupiesZone('sold', heldEntryDeleted: false), isTrue);
    });

    test('destroyed and re-exported goods leave too', () {
      expect(stillOccupiesZone('destroyed', heldEntryDeleted: true), isFalse);
      expect(stillOccupiesZone('re-exported', heldEntryDeleted: true), isFalse);
    });

    test('goods still under inquiry keep their space', () {
      // A pending destruction has NOT happened yet, so it is still in the shed.
      expect(
          stillOccupiesZone('supposed to be destroyed', heldEntryDeleted: false),
          isTrue);
    });

    // The record of sale carries the receipt, and the separator is an em dash
    // -- the same trap as [FINAL:OTHER].
    test('the record of sale is tagged and carries its receipt', () {
      const note = '[FINAL:SOLD] — Receipt: TR/GL1/2026/2043';
      expect(note.startsWith('[FINAL:SOLD]'), isTrue);
      expect(note.contains('Receipt: '), isTrue);
    });
  });

  group('a perishable may only enter a special sale', () {
    // ⚠️ The rule holds BOTH ways: a perishable belongs in a special sale and
    // nowhere else, and a special sale carries only perishables. A general
    // sale runs too slowly for goods that spoil, and mixing them into one lot
    // is what the two sale types exist to prevent.
    bool allowedInSale({required bool isPerishable, required String saleType}) =>
        isPerishable == (saleType == 'special');

    test('a perishable in a special sale is allowed', () {
      expect(allowedInSale(isPerishable: true, saleType: 'special'), isTrue);
    });

    test('a perishable in a general sale is not', () {
      expect(allowedInSale(isPerishable: true, saleType: 'general'), isFalse);
    });

    test('normal goods in a special sale are not', () {
      expect(allowedInSale(isPerishable: false, saleType: 'special'), isFalse);
    });

    test('normal goods in a general sale are allowed', () {
      expect(allowedInSale(isPerishable: false, saleType: 'general'), isTrue);
    });

    // A perishable waits out no appeal window -- the deadline is the entry
    // moment itself, which is why it can be disposed of within days.
    test('a perishable has no appeal window to wait out', () {
      final entered = DateTime(2026, 1, 10);
      final deadline = entered; // not entered + 30 days
      expect(deadline.isAfter(entered), isFalse);
    });
  });

  group('a sale stores a snapshot of the tax it was charged', () {
    // The rates in disposal_taxes are configuration and change over time. A
    // sold item does NOT reference them -- it stores id, name, percentage and
    // amount at the moment of sale, so a later rate change never rewrites the
    // history of a sale already made.
    double taxOn(double price, double percentage) => price * percentage / 100;

    test('the amount is the percentage of the sale price', () {
      expect(taxOn(58171, 18), closeTo(10470.78, 0.01));
      expect(taxOn(58171, 5), closeTo(2908.55, 0.01));
      expect(taxOn(58171, 1.5), closeTo(872.57, 0.01));
    });

    // ⚠️ An INACTIVE rate must never be charged. It stays in the table so the
    // Taxes tab can show it as inactive, which is not the same as deleting it.
    test('only active rates are charged', () {
      const rates = [
        ('VAT', 18.0, true),
        ('Cess', 5.0, true),
        ('PAL', 10.0, false),
      ];
      final charged = rates.where((r) => r.$3).map((r) => r.$1).toList();
      expect(charged, ['VAT', 'Cess']);
      expect(charged.contains('PAL'), isFalse);
    });

    test('a snapshot survives a later rate change', () {
      // The sale recorded 18%; the rate is later cut to 12%. The sale keeps
      // what it charged.
      const snapshotPercentage = 18.0;
      const currentRate = 12.0;
      expect(snapshotPercentage, isNot(currentRate));
      expect(taxOn(1000, snapshotPercentage), 180);
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
