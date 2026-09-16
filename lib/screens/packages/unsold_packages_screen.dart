import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/outcome_filter.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/perishable_row.dart';
import '../executive/unsold_shared.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/date_filter_button.dart';

/// The yard's own packages that could not be sold by any means.
///
/// READ-ONLY: the Top Management Directorate decides the final outcome; this page tells the
/// yard what was decided so they can act on goods still sitting in their
/// warehouses.
///
/// One widget serves SIX pages. With [proposalFilter] null it lists every
/// unsold package (the Unsold Goods page); set to an outcome code it lists
/// only the goods decided that way — Government Use, Convert and
/// "Removed from the Premises" each get their own page that way, without
/// duplicating the header, filters, table and pager five times over.
///
/// Laid out to match the Sold Packages page exactly — same header, same search
/// + Date Range + Year + status chips card, same table shell and pager.
class UnsoldPackagesScreen extends ConsumerStatefulWidget {
  /// The route this page is mounted at, so the sidebar highlights correctly.
  final String route;

  /// Page title and the line under it.
  final String title;
  final String subtitle;

  /// The word beside the count in the header ("3 Unsold").
  final String countLabel;

  /// One of [kUnsoldProposals], or null to list every unsold package.
  ///
  /// When set, the status chips are hidden: every row already carries the same
  /// outcome, so filtering by "decided" would be meaningless.
  final String? proposalFilter;

  const UnsoldPackagesScreen({
    super.key,
    this.route = '/unsold-packages',
    this.title = 'Unsold Goods',
    this.subtitle = 'Goods that could not be sold by any means',
    this.countLabel = 'Unsold',
    this.proposalFilter,
  });

  @override
  ConsumerState<UnsoldPackagesScreen> createState() =>
      _UnsoldPackagesScreenState();
}

class _UnsoldPackagesScreenState extends ConsumerState<UnsoldPackagesScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTimeRange? _dateRange;
  String? _yearFilter;

  /// One of kUnsoldProposals, kOutcomeAwaiting, or null for all.
  ///
  /// ⚠️ Replaces a decided/awaiting flag. "Decided" put all six outcomes in
  /// one bucket, which is not what an officer is looking for -- they want the
  /// goods going to auction, or back out of the country.
  String? _outcomeFilter;

  /// Perishable-only narrowing. Null is "all goods" — false would hide every
  /// perishable row rather than showing them all.
  bool? _perishableOnly;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Status chip, styled exactly like the Sold page's delivery filter.

  // ⚠️ `_yardRows` and `_visibleRows` moved into the query. The yard scope and
  // the outcome filter are both columns on the `exhausted_unsold` view now
  // (postgres/23), so the header count and the table read the SAME narrowed
  // set by construction rather than by both remembering to call one helper.

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final myYardForQuery = ref.watch(currentProfileProvider)?.yard;
    // ⚠️ Everything this page narrows on is in the key, so the DATABASE
    // decides which packages have run out of tenders (see postgres/23) and
    // which page of them to return. Loading every tender sale in the yard to
    // find eight packages is what this replaces.
    final query = ExhaustedUnsoldQuery(
      page: _page,
      search: _search,
      yard: myYardForQuery,
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
      outcome: _outcomeFilter,
      proposal: widget.proposalFilter,
      // ⚠️ Both unsold routes. A perishable reaches this list after ONE
      // failed Special Tender Sale, with no committee — conditions
      // `exhausted_unsold` can never satisfy, so without this the page that
      // lists unsold goods silently omitted every perishable, decided ones
      // included. See migration 017.
      includeAllRoutes: true,
      perishableOnly: _perishableOnly,
    );
    final async = ref.watch(exhaustedUnsoldPageProvider(query));
    final proposals =
        ref.watch(unsoldProposalsProvider).valueOrNull ?? const {};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    // The Top Management tender committees, keyed by forfeited_package_id.
    // Their valuation supersedes the original for an unsold package.
    final committees = ref.watch(tenderCommitteesProvider).valueOrNull ??
        const <String, TenderCommitteeModel>{};

    return AppShell(
      currentRoute: widget.route,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(widget.subtitle,
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    // The database's count for this filter.
                    async.when(
                      data: (p) => Text(
                          '${p.total} ${widget.countLabel}',
                          style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // ── Search + filters ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search SR #, consignee or item...',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: context.colors.textMuted),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: context.colors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _search = '';
                                    _page = 0;
                                  });
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 0;
                      }),
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateFilterButton(
                          dateRange: _dateRange,
                          year: _yearFilter,
                          years: srYears(
                              ref.watch(exhaustedUnsoldYearsProvider)
                                      .valueOrNull ??
                                  const <String>[]),
                          onChanged: (range, year) => setState(() {
                            _dateRange = range;
                            _yearFilter = year;
                            _page = 0;
                          }),
                        ),

                        // ⚠️ Hidden on an outcome page: every row there is
                        // already that outcome, so the filter could only ever
                        // return all of them or none.
                        if (widget.proposalFilter == null)
                          OutcomeFilter(
                            value: _outcomeFilter,
                            // Every outcome the DG can rule, plus awaiting.
                            outcomes: kUnsoldProposals,
                            onChanged: (v) => setState(() {
                              _outcomeFilter = v;
                              _page = 0;
                            }),
                          ),
                        // ⚠️ Perishables reach this table by a different
                        // route entirely — one special tender sale, no
                        // re-valuation, no committee — and nothing else on
                        // the row says so.
                        // ⚠️ Only where this page HAS perishables. Each
                        // Final Outcome page is its own population —
                        // Converted has one, Auction has none — so the
                        // chip follows the data rather than the page name.
                        if (ref
                                .watch(unsoldHasPerishablesProvider((
                                  yard: myYardForQuery,
                                  proposal: widget.proposalFilter,
                                )))
                                .valueOrNull ==
                            true)
                          PerishableFilterChip(
                            selected: _perishableOnly == true,
                            onChanged: (v) => setState(() {
                              _perishableOnly = v ? true : null;
                              _page = 0;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),

              const Gap(16),
              Expanded(
                child: async.when(
                  skipLoadingOnReload: true,
                  loading: () =>
                      Center(child: CircularProgressIndicator(color: gold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.refresh(exhaustedUnsoldPageProvider(query))),
                  data: (result) {
                    // Which packages have run out of tenders, which of them
                    // match the filters, and which page of them — all decided
                    // by the database. Nothing left to narrow here.
                    final pageRows = result.rows;
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    final page = _page.clamp(0, maxPage);
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: context.colors.cardDark,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: context.colors.borderColor),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DataTable2(
                                columnSpacing: 12,
                                horizontalMargin: 16,
                                fixedTopRows: 1,
                                // Wider than the viewport on purpose: the
                                // table scrolls sideways so no column is
                                // squeezed out.
                                minWidth: kUnsoldTableMinWidth,
                                empty: const EmptyTableState(
                                    message: 'No unsold packages in this yard'),
                                headingRowColor: WidgetStateProperty.all(
                                    context.colors.surfaceDark),
                                // An outcome page already filters to one
                                // outcome, so a Final Outcome column would
                                // repeat the page title on every row; it shows
                                // the decision DATE instead.
                                columns: widget.proposalFilter == null
                                    ? kUnsoldColumns
                                    : kUnsoldDecidedColumns,
                                rows: pageRows.map((info) {
                                  final f = info.forfeited;
                                  final pkg = f.packageDetails;
                                  final qty = unsoldQty(f);
                                  // Marks WHAT the goods are, at a tenth of
                                  // the tender card's amber: findable at a
                                  // glance, ignorable at a distance.
                                  final isPerishable =
                                      isPerishableGoods(forfeited: f);
                                  return DataRow(
                                    color: WidgetStateProperty.resolveWith(
                                        (_) => perishableRowColor(
                                            context, isPerishable)),
                                    cells: unsoldCells(
                                      context,
                                      info: info,
                                      srColor: gold,
                                      // The Top Management committee's figure,
                                      // when one exists — it supersedes the
                                      // original valuation for these packages.
                                      // The SUBMITTED figure: what the
                                      // package was actually tendered at.
                                      committeeUnitValue:
                                          committees[info.forfeited.id]
                                              ?.submittedValue,
                                      // Plain text on the yard table — the
                                      // green highlight is for the portals
                                      // that act on the money.
                                      valuationColor:
                                          context.colors.textPrimary,
                                      // READ-ONLY: the DG decides, the yard
                                      // acts on what was decided.
                                      outcome: widget.proposalFilter == null
                                          ? Center(
                                              child: UnsoldOutcomeChip(
                                                  proposal: proposals[f.id]),
                                            )
                                          : unsoldDecidedOnCell(
                                              context, proposals[f.id]),
                                      // Only the decided tables carry the
                                      // column, so only they may pass a cell
                                      // — the undecided table has nothing to
                                      // hand over yet.
                                      delivery: widget.proposalFilter == null
                                          ? null
                                          : UnsoldDeliveryCell(
                                              proposal: proposals[f.id]),
                                      onDetails: pkg == null
                                          ? null
                                          : () => showAppDialog(
                                                context: context,
                                                builder: (_) =>
                                                    PackageDetailsDialog(
                                                  package: pkg,
                                                  storageRate: storageRate,
                                                  // No headerAccentColor: the
                                                  // yard's other pages (Sold,
                                                  // Abandoned, ...) use the
                                                  // default blue header, and
                                                  // this popup must match.
                                                  useLegacySummary: true,
                                                  highlightItemId: f.itemId,
                                                  valuationUnitCost:
                                                      f.valuationCost,
                                                  valuationTotalCost:
                                                      f.valuationCost != null
                                                          ? f.valuationCost! *
                                                              qty
                                                          : null,
                                                  valuationQty: qty,
                                                  tenderHistoryFor: f,
                                                  // Sealed while the newest
                                                  // round is still open.
                                                  valuationSealedUntilSale: info
                                                          .latestSale
                                                          ?.saleEnded ==
                                                      false,
                                                ),
                                              ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        TablePager(
                          // The database's count for this filter.
                          total: result.total,
                          page: page,
                          pageSize: kDispositionPageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 300.ms)
                        .fadeIn();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
