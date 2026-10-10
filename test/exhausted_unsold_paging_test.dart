// Unsold Goods asked a question that cost the whole tender history to answer.
//
// getExhaustedUnsoldPackages calls getUnsoldTenderSales, which calls
// getTenderSales -- every sale, every item, every join -- and only THEN
// narrows to the handful of packages that have run out of road. Eight rows,
// bought with the entire tender history of the yard.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';

void main() {
  final view =
      File('postgres/23_exhausted_unsold_view.sql').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final screen = File('lib/screens/packages/unsold_packages_screen.dart')
      .readAsStringSync();

  group('the four conditions, condition for condition', () {
    test('a sold package is finished, whatever else is true', () {
      expect(view, contains('not a.ever_sold'));
      expect(view, contains('exhausted row(s) actually sold'));
    });

    test('the Valuation Tender and Tenders 1-3 must all have failed', () {
      expect(view, contains('a.tender_count > 3'));
      expect(view, contains('have not exhausted the tender route'));
    });

    test('a committee value with no submission is not a tendered price', () {
      // ⚠️ submitted_value, never committee_value on its own -- the figure has
      // to have been SUBMITTED by the ADG to count.
      expect(view, contains('tc.submitted_value is not null'));
      expect(view, contains('tc.submitted_at is not null'));
    });

    test('a round must have RUN after the submission and still not sold', () {
      // ⚠️ Without this the package reached the DG the moment the ADG
      // submitted -- so the DG decided the final outcome of goods that still
      // had a live chance of selling.
      expect(view, contains('r.sale_moment > tc.submitted_at'));
      expect(view, contains('r.end_moment < now()'));
      expect(view, contains('reached the DG before their committee round ran'));
    });
  });

  group('the moment, not the row', () {
    test('rounds are judged by their SCHEDULED time', () {
      // ⚠️ A live bug this codebase already hit: Central Disposal schedules a
      // round before the ADG submits, and two packages can share one sale row.
      // Keying on created_at stranded Toilet Seat Covers on 5 rounds forever
      // while Wash Basins in the SAME row moved on.
      expect(view, contains('ts.sale_date::date'));
      expect(view, contains("coalesce(ts.sale_time, '00:00')::time"));
      // ⚠️ The ROUNDS cte is what condition 4 tests against, and it must
      // derive both moments from the schedule alone. (created_at appears
      // elsewhere in the view, ordering the item-name fallback, which is a
      // different question entirely.)
      final rounds = view.substring(
          view.indexOf('with rounds as'), view.indexOf('), agg as ('));
      expect(rounds, isNot(contains('created_at')));
      expect(rounds, contains('as sale_moment'));
    });

    test('a round that has not ended yet cannot have failed', () {
      expect(view, contains('as end_moment'));
      expect(view, contains("coalesce(ts.sale_end_time, ts.sale_time, '00:00')"));
    });
  });

  group('the page costs the page', () {
    test('the query asks for ids, then rounds for those ids only', () {
      final m = services.substring(services.indexOf('getExhaustedUnsoldPaged'));
      expect(m, contains(".select('forfeited_package_id')"));
      expect(m, contains('.range(offset, offset + limit - 1)'));
      expect(m, contains('_reTenderInfoForIds(ids)'));
    });

    test('one filter closure serves the rows and the count', () {
      final m = services.substring(services.indexOf('getExhaustedUnsoldPaged'));
      expect(m, contains('PgQuery narrow(PgQuery q)'));
      // ⚠️ The view NAME is a variable now -- the same method serves the
      // Unsold Goods list and the Unsold Perishables one, which differ only
      // in which view decides membership. What this test is about is
      // unchanged: ONE closure narrows both the rows and the count, or the
      // pager's total disagrees with the rows under it.
      expect(m, contains('narrow(supabase.from(view)).count()'));
      expect(m, contains("? 'unsold_perishables'"));
      expect(m, contains("'exhausted_unsold'"));
    });

    test("the database's order is kept, not re-sorted in Dart", () {
      // ⚠️ Re-sorting after the fact would quietly disagree with the page
      // boundaries the query used.
      final m = services.substring(services.indexOf('getExhaustedUnsoldPaged'));
      expect(m, contains('for (final id in ids) if (byId[id] != null)'));
    });

    test('an empty page asks for no rounds at all', () {
      final m = services.substring(services.indexOf('getExhaustedUnsoldPaged'));
      expect(m, contains('if (ids.isEmpty)'));
    });
  });

  group('every filter reaches SQL', () {
    test('including the item name, which needed a column of its own', () {
      // Forfeiture is per item, so the view resolves the name the way
      // unsoldItemName() does: the forfeited row's own item, then the
      // package's first.
      expect(view, contains('as item_name'));
      expect(view, contains('have no item name to search on'));
      expect(services, contains("item_name.ilike.%\$s%"));
    });

    test('the yard scope and the outcome page are columns, not helpers', () {
      // ⚠️ _yardRows and _visibleRows are gone: the header count and the table
      // now read the same narrowed set by construction, rather than by both
      // remembering to call one helper.
      expect(screen, isNot(contains('List<ReTenderSaleInfo> _yardRows(')));
      expect(screen, isNot(contains('List<ReTenderSaleInfo> _visibleRows(')));
      expect(screen, contains('yard: myYardForQuery,'));
      expect(screen, contains('proposal: widget.proposalFilter,'));
    });

    test('the outcome filter reaches SQL, awaiting included', () {
      // ⚠️ There is no "decided" test any more -- it lumped all six
      // outcomes into one bucket, which is not a question an officer asks.
      // Awaiting is still the null test it always was; the rest are equality
      // on the outcome itself.
      final m = services.substring(services.indexOf('getExhaustedUnsoldPaged'));
      expect(m, contains("q.isNull('proposal')"));
      expect(m, contains("q = q.eq('proposal', outcome)"));
      expect(m.contains("q.not('proposal', 'is', null)"), isFalse,
          reason: 'the decided/awaiting flag is back');
    });
  });

  group('the query key', () {
    test('two identical queries are the same key', () {
      const a = ExhaustedUnsoldQuery(page: 1, search: 'tyre');
      const b = ExhaustedUnsoldQuery(page: 1, search: 'tyre');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every filter takes part in it', () {
      const base = ExhaustedUnsoldQuery();
      expect(base, isNot(const ExhaustedUnsoldQuery(page: 1)));
      expect(base, isNot(const ExhaustedUnsoldQuery(search: 'x')));
      expect(base, isNot(const ExhaustedUnsoldQuery(yard: 'GL1')));
      expect(base, isNot(const ExhaustedUnsoldQuery(year: '2026')));
      expect(base, isNot(const ExhaustedUnsoldQuery(outcome: 'auction')));
      expect(base, isNot(const ExhaustedUnsoldQuery(proposal: 'auction')));
    });

    test('the outcome filter and the PAGE are different things', () {
      // ⚠️ `proposal` says which page this is; `outcome` narrows within
      // it. Government Use passes proposal='government_use' and every row on
      // it already is that -- confusing the two would make the page filter
      // itself down to nothing.
      const page = ExhaustedUnsoldQuery(proposal: 'auction');
      const filter = ExhaustedUnsoldQuery(outcome: 'auction');
      expect(page == filter, isFalse);
    });

    test('All is a third answer, and so is Awaiting', () {
      const all = ExhaustedUnsoldQuery();
      const auction = ExhaustedUnsoldQuery(outcome: 'auction');
      const awaiting = ExhaustedUnsoldQuery(outcome: kOutcomeAwaiting);
      expect({all, auction, awaiting}.length, 3);
    });
  });

  group('the screen reads it', () {
    test('the paged provider, and the count from the server', () {
      expect(screen, contains('exhaustedUnsoldPageProvider(query)'));
      expect(screen, contains('total: result.total,'));
      expect(screen, isNot(contains('total: rows.length')));
    });

    test('the year filter runs its own query', () {
      expect(screen, contains('exhaustedUnsoldYearsProvider'));
    });
  });

  group("Central Disposal's five outcome tabs share this view", () {
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();

    test('the outcome is part of the query key, not a Dart filter', () {
      // ⚠️ Government Use, Auction, Converted and Removed each ask for their
      // own outcome; Unsold Goods (null) asks for all of them. Filtering in
      // Dart would mean every tab fetched every outcome.
      expect(dash, contains('proposal: proposalFilter,'));
      expect(dash, contains('exhaustedUnsoldPageProvider(query)'));
      // ⚠️ Scoped to THIS widget. `exhaustedUnsoldProvider` is still read
      // elsewhere in the file as an EXCLUSION set -- the Unsold Tenders tab
      // uses it to drop packages that have run out of rounds from its
      // re-tender pool, which is a different question and rightly still asks
      // for all of them.
      final tab = dash.substring(dash.indexOf('class UnsoldProposalsTab'),
          dash.indexOf('class _SoldPackagesTab'));
      expect(tab, isNot(contains('ref.watch(exhaustedUnsoldProvider)')));
    });

    test('the page index is keyed by tab', () {
      // ⚠️ The five tabs share one widget, so a single provider would carry
      // one tab's page number into the next.
      expect(dash, contains('_unsoldPageProvider(tabKey)'));
      expect(dash, contains('page: ref.watch(_unsoldPageProvider(tabKey)),'));
    });

    test('the count pill and the pager both read the server total', () {
      // `rows.length` is one page: the pill would read 20 whatever the
      // twenty-eight yards hold.
      expect(dash, contains("value: '\$total',"));
      expect(dash, contains('if (total > 0)'));
      expect(dash, contains('pageSize: kDispositionPageSize,'));
    });

    test('nothing is narrowed in Dart afterwards', () {
      expect(dash,
          contains('// Already filtered and paged by the database'));
    });

    test('the case number is searchable, which needed a column', () {
      // ⚠️ Central Disposal's copy searches it and the yard's does not.
      // Leaving it out would have kept the whole list in Dart for that one
      // term -- exactly the cost this view removes.
      expect(view, contains('p.case_number'));
      expect(view, contains('case_number is missing from the view'));
      expect(services, contains(r'case_number.ilike.%$s%'));
    });
  });

  group('Unsold Tenders: three whole-table passes become one query', () {
    final pool =
        File('postgres/29_unsold_retender_pool_view.sql').readAsStringSync();
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();

    test('nothing sold is offered again', () {
      expect(pool, contains('not a.ever_sold'));
      expect(pool, contains('sold package(s) are in the re-tender pool'));
    });

    test('a PERISHABLE never joins the pool', () {
      // ⚠️ Goods that spoil get no second round: one failed Special Tender
      // Sale and they go straight to Top Management. Offering them again would
      // offer goods that will not last the wait, and would hide them from the
      // only person who can act.
      expect(pool, contains("coalesce(fp.source, '') <> 'perishable'"));
      expect(pool, contains('perishable package(s) are in the re-tender pool'));
    });

    test('a package cannot be in the pool AND exhausted', () {
      // ⚠️ It would be offered for re-tender and decided on at the same time.
      expect(pool, contains('from public.exhausted_unsold e'));
      expect(pool,
          contains('exhausted package(s) are also in the re-tender pool'));
    });

    test('the current round is the newest by created_at', () {
      expect(pool, contains('distinct on (r.fp_id)'));
      expect(pool, contains('order by r.fp_id, r.round_created desc'));
      expect(pool, contains('a pool row has no current round to judge'));
    });

    test('the deadline half stays in Dart, and the view says why', () {
      // Same split as Tender Sales: workingDeadline needs the holiday calendar
      // the app fetches at runtime.
      expect(pool, contains('as round_moment_passed'));
      expect(pool, contains('no holiday table here'));
      // ⚠️ And there is no `unsold` COLUMN to read either -- the model has the
      // field and it is always false.
      expect(pool, contains('There is also no "unsold" COLUMN'));
    });

    test('the tab reads one provider where it read three', () {
      expect(dash, contains('unsoldRetenderPageProvider(query)'));
      final tab = dash.substring(dash.indexOf('class _UnsoldReTenderTabState'),
          dash.indexOf('class _TenderSalesTab'));
      expect(tab, isNot(contains('ref.watch(unsoldTenderSalesProvider)')));
      expect(tab, isNot(contains('ref.watch(exhaustedUnsoldProvider)')));
    });

    test('it finally has a pager, on the server total', () {
      final tab = dash.substring(dash.indexOf('class _UnsoldReTenderTabState'),
          dash.indexOf('class _TenderSalesTab'));
      expect(tab, contains('TablePager('));
      expect(tab, contains('total: total,'));
      expect(tab, contains('pageSize: kDispositionPageSize,'));
    });

    test('the count pill needs no subtraction of its own', () {
      // ⚠️ It used to count `list.where(not exhausted)`. The view excludes
      // them, so the pill and the table now agree by construction.
      final tab = dash.substring(dash.indexOf('class _UnsoldReTenderTabState'),
          dash.indexOf('class _TenderSalesTab'));
      // ⚠️ Asserted on `.total` -- the DATABASE's count -- not on the name
      // of the variable holding it. The pill moved onto the control line and
      // now reads the async value directly, which is the same number by a
      // different name; pinning the old name failed on a move that changed
      // nothing about what is counted.
      expect(tab, contains('.total}'));
      expect(tab, isNot(contains('rows.length')));
      expect(tab, isNot(contains('!exhausted.contains')));
    });
  });

  group('Committees is the same pool, narrowed twice', () {
    final pool =
        File('postgres/29_unsold_retender_pool_view.sql').readAsStringSync();
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();
    final method = services.substring(services.indexOf('getCommitteesPaged'));

    test('the fourth round and the committee are both SQL', () {
      // ⚠️ The round rule moved INTO a view of its own. The Committees tab
      // used to narrow unsold_retender_pool -- but postgres/38 now holds
      // packages past four rounds OUT of that pool (they need a committee
      // before they can be offered again), so the tab that appoints their
      // committee could no longer see them. committee_pool (postgres/39)
      // carries the >= 4 rule itself.
      //
      // Still both in SQL, which is what this test is about.
      final cpool =
          File('postgres/39_committee_pool_view.sql').readAsStringSync();
      expect(cpool, contains('a.round_count >= 4'));
      expect(method, contains("q.eq('has_committee', true)"));
      expect(cpool, contains('as has_committee'));
    });

    test('the flag agrees with the table it comes from', () {
      // ⚠️ Otherwise the tab shows a card it cannot render.
      expect(pool, contains('row(s) disagree about having a committee'));
    });

    test("the 'moved on' set is gone, because the view excludes it", () {
      // ⚠️ A card leaves this tab exactly when the committee-priced tender
      // also fails -- which is when the package becomes exhausted. The pool
      // already excludes those, so no second set is needed.
      final tab = dash.substring(dash.indexOf('class _CommitteesTabState'),
          dash.indexOf('class _CommitteeCard'));
      // ⚠️ The comments still NAME the old providers, explaining what they
      // did and why they are gone — that is the record, not a leftover. What
      // must not survive is a read of them.
      expect(tab, isNot(contains('ref.watch(exhaustedUnsoldProvider)')));
      expect(tab, isNot(contains('ref.watch(committeeEligibleProvider)')));
      expect(tab, isNot(contains('ref.refresh(committeeEligibleProvider)')));
      expect(tab, isNot(contains('movedOn.contains')));
    });

    test('it reads one provider, and has a pager', () {
      final tab = dash.substring(dash.indexOf('class _CommitteesTabState'),
          dash.indexOf('class _CommitteeCard'));
      expect(tab, contains('committeesPageProvider(query)'));
      expect(tab, contains('TablePager('));
      expect(tab, contains('total: total,'));
    });

    test('a card whose committee has not loaded is skipped, not crashed', () {
      // ⚠️ The view says a committee exists; the map is a separate fetch that
      // may not have landed. A `!` there would crash the tab on a slow frame.
      final tab = dash.substring(dash.indexOf('class _CommitteesTabState'),
          dash.indexOf('class _CommitteeCard'));
      expect(tab, contains('if (c == null) return const SizedBox.shrink();'));
      expect(tab, isNot(contains('committees[rows[i].forfeited.id]!')));
    });
  });
}
