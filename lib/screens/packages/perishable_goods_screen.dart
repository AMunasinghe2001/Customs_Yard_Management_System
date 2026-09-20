import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/post_status_activities.dart';
import '../../core/providers.dart';
import '../../core/db_client.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/disposal_page_header.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/outcome_filter.dart';
import '../../widgets/page_title.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/styled_dropdown.dart';
import '../forfeited_packages/disposal_request_dialog.dart';
import '../executive/unsold_shared.dart';
import '../../widgets/destruction_status_pill.dart';
import '../disposal/disposal_shared.dart';
import '../../widgets/date_filter_button.dart';
import '../../widgets/send_disposal_request_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/qty_cell.dart';

/// One perishable item, with the package it belongs to.
class PerishableRow {
  final PackageModel package;
  final PackageItem item;
  const PerishableRow({required this.package, required this.item});

  /// Perishables are sent as soon as they are registered, so what matters is
  /// how long this one has been waiting.
  int get daysWaiting =>
      DateTime.now().difference(package.entryDate ?? package.createdAt).inDays;
}

// ⚠️ `perishableRowsProvider` lived here and awaited EVERY package in the
// yard to find the 47 items registered as perishable. Both of its membership
// rules moved into the `perishable_rows` view (postgres/24) — nature is
// perishable, and a SENT item drops off UNLESS a final outcome came back for
// it.
//
// That exception is the important half. Perishable goods never reach a
// warehouse and never sit out the appeal window, so no disposition page can
// show them; this is the ONLY page they appear on. Dropping a sent-and-decided
// item would mean the yard and Central Disposal never see the decision at all.

/// "pkgId:itemId" for every perishable item already in a disposal request.
final sentPerishableKeysProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(packagesChangeTriggerProvider);
  final data = await supabase
      .from('disposal_request_items')
      .select('forfeited_packages!inner(package_id, item_id, source)')
      .eq('forfeited_packages.source', 'perishable');
  return {
    for (final row in (data as List))
      () {
        final e = (row as Map<String, dynamic>)['forfeited_packages']
            as Map<String, dynamic>;
        return '${e['package_id']}:${e['item_id']}';
      }(),
  };
});

/// The yard's Perishable Goods page.
///
/// Read-only on the Central Disposal side ([readOnly]), which watches what each
/// yard is holding but does not send the request itself.
class PerishableGoodsScreen extends ConsumerStatefulWidget {
  /// Central Disposal's copy: no Send Disposal Request, and no app shell.
  final bool readOnly;
  const PerishableGoodsScreen({super.key, this.readOnly = false});

  @override
  ConsumerState<PerishableGoodsScreen> createState() =>
      _PerishableGoodsScreenState();
}

class _PerishableGoodsScreenState extends ConsumerState<PerishableGoodsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _yearFilter;

  /// ⚠️ The same two filters the yard's Other Goods page offers, because this
  /// is the same kind of page: a yard officer looking through goods it holds.
  /// It had only a search box and a year, so narrowing to "what came in last
  /// week" or "what is marked for immediate disposal" — the two questions the
  /// other held-goods pages answer — could not be asked here at all.
  DateTimeRange? _dateRange;
  String _activity = 'all';

  /// A proposal, kOutcomeSold, kOutcomeAwaiting, or null for all.
  ///
  /// ⚠️ Sold is a choice HERE and nowhere else. A perishable that sells at
  /// tender ends there and never reaches the DG, so on this page a sale is a
  /// final outcome in its own right.
  String? _outcomeFilter;

  /// Central Disposal only: which yard's goods to show. Null = every yard.
  String? _yardFilter;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestSingleDisposal(PackageModel pkg, String disposition,
      {required String itemId, WarehouseEntryModel? entry}) async {
    try {
      final key = entry != null
          ? '${pkg.id}:$itemId:${entry.id}:perishable'
          : '${pkg.id}:$itemId:perishable';
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
        requestDate: DateTime.now(),
        dispositions: {key: disposition},
      );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(livePackagesProvider);
      ref.invalidate(perishablePageProvider);
      ref.invalidate(sentPerishableKeysProvider);
      ref.invalidate(requestableForfeitedPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text('Disposal request sent for ${pkg.srNumber} '
              '(${disposition == "sale" ? "Sale" : "Destruction"}).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    }
  }

  /// The search box, built once and placed differently by each portal.
  ///
  /// ⚠️ On the YARD it overrides NOTHING and takes the app's own
  /// inputDecorationTheme: a grey outline that turns gold on focus. That is
  /// what every held-goods page beside it does — Forfeited, Other, Returned
  /// all pass a bare InputDecoration — and it is why theirs behaves the same
  /// when clicked.
  ///
  /// It used to paint a gold border and a gold fill of its own, inside the
  /// gold filter card: a gold box in a gold box, which matched nothing. The
  /// first fix went too far the other way and removed the frame altogether.
  ///
  /// Central Disposal's copy has no card around it, so there it keeps an
  /// explicit outline like every search box in that portal.
  Widget _searchBox(BuildContext context) => SizedBox(
        height: 44,
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search SR #, consignee or item...',
            hintStyle:
                TextStyle(color: context.colors.textSecondary, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded,
                size: 20,
                color: widget.readOnly
                    ? context.colors.primaryGold
                    : context.colors.textMuted),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    splashRadius: 16,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: context.colors.textMuted),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _search = '';
                      _page = 0;
                    }),
                  ),
            filled: true,
            fillColor: widget.readOnly
                ? context.colors.primaryGold.withOpacity(0.06)
                : context.colors.surfaceDark,
            // Null lets the theme's own border through, which is the grey
            // outline that turns gold on focus. Only Central Disposal's copy
            // states one.
            border: widget.readOnly ? _searchBorder(context) : null,
            enabledBorder: widget.readOnly ? _searchBorder(context) : null,
            focusedBorder:
                widget.readOnly ? _searchBorder(context, focused: true) : null,
          ),
          onChanged: (v) => setState(() {
            _search = v;
            _page = 0;
          }),
        ),
      );

  /// The view's rows, as this page's widgets already expect them.
  ///
  /// ⚠️ Replaces `_filter`, which narrowed a list of every perishable item in
  /// the yard. Which items are listed, in what order, and which page are all
  /// the view's job now — including the rule that a SENT item stays only if a
  /// final outcome came back for it, which is why this is the one page those
  /// goods can still be seen on.
  List<PerishableRow> _rowsFrom(PerishablePage result) {
    final out = <PerishableRow>[];
    for (final k in result.keys) {
      final pkg = result.packages[k.packageId];
      if (pkg == null) continue;
      final item = pkg.items.where((i) => i.id == k.itemId).firstOrNull;
      if (item == null) continue;
      out.add(PerishableRow(package: pkg, item: item));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Every filter is in the key, so the DATABASE decides which perishable
    // items are still listed (see postgres/24 for the two membership rules)
    // and which page of them to return. Awaiting every package in the yard to
    // find 47 items is what this replaces.
    final query = PerishableQuery(
      page: _page,
      search: _search,
      // The SR number's own yard segment, not the package's yard column.
      yardSrPrefix:
          (_yardFilter == null || _yardFilter == 'all') ? null : _yardFilter,
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
      activity: _activity,
      outcome: _outcomeFilter,
    );
    final async = ref.watch(perishablePageProvider(query));
    // The DG's rulings, keyed by item. Both portals read the same map, so the
    // yard and Central Disposal cannot describe one outcome differently.
    final outcomes = ref.watch(unsoldProposalsByItemProvider).valueOrNull ??
        const <String, UnsoldProposalModel>{};
    // ⚠️ ONE query for the page. A per-row provider watch meant
    // twenty round trips for one number each -- and in a widget test a
    // realtime channel that never settled, so pumpAndSettle timed out.
    final valuations = ref.watch(perishableValuationsProvider).valueOrNull ??
        const <String, double>{};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final accent = widget.readOnly
        ? context.colors.successGreen
        : context.colors.primaryGold;

    final body = Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Padding(
        // ⚠️ 24 in Central Disposal, 28 on the yard. Every tab in that
        // portal pads at 24, so 28 sat this page's title and its table
        // lower than the tab you switched from.
        padding: EdgeInsets.all(widget.readOnly ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⚠️ Central Disposal's copy is built as ITS pages are built,
            // not as a yard page with a yard picker bolted on.
            //
            // Every cross-yard tab there -- Sold Goods, Unsold Tenders,
            // Committees -- is: a plain 22pt title, then the search box and
            // the yard picker on that SAME line, then a StatChip on its own
            // line under it. This page instead used DisposalPageHeader (a
            // title with a SUBTITLE and a big trailing count box) and put its
            // controls on a third row, so beside its neighbours it read as a
            // different product: taller, with the count in the wrong place
            // and in a different shape.
            if (widget.readOnly) ...[
              Row(children: [
                PageTitle('Perishable Goods', Icons.eco_rounded,
                    subtitle:
                        'Time-sensitive perishable goods requiring expedited disposal or sale',
                    accent: context.colors.successGreen),
                const Spacer(),
                SizedBox(width: 280, child: _searchBox(context)),
                const Gap(12),
                // ⚠️ No year filter here. Not one cross-yard tab in this
                // portal carries one -- they narrow by yard and by search --
                // and it was the extra control that made this header a
                // different shape from the tab beside it. The yard's own copy
                // keeps it, where the held-goods pages all have one.
                // This page watches EVERY yard here, so without it an officer
                // cannot narrow to the one they are dealing with.
                YardAllFilter(
                  value: _yardFilter,
                  onChanged: (v) => setState(() {
                    _yardFilter = v;
                    _page = 0;
                  }),
                ),
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(12),
              // ⚠️ The SAME shape Destroyed Goods and Government Use use:
              // the count on its own line under the title, pushed to the RIGHT.
              //
              // Those pages have a segmented filter on the left of this line;
              // this one has nothing to filter by, so the left is simply
              // empty and the Spacer does the work. Matching their layout
              // matters more than saving the line -- an officer moving between
              // tabs should find the count in the same place every time.
              //
              // Absent while loading rather than showing a stale or zero
              // count.
              Row(children: [
                // ⚠️ The filter sits at the LEFT of this line, opposite the
                // count -- the shape Destroyed Goods sets and every tab in
                // this portal follows. It was up on the title row beside the
                // yard picker, which is a third layout again: an officer
                // moving between tabs should find each control in the same
                // place every time.
                OutcomeFilter(
                  value: _outcomeFilter,
                  outcomes: kUnsoldProposals,
                  includeSold: true,
                  // Central Disposal's own green -- this is its copy --
                  // and its chip shape, because it sits beside that portal's
                  // filter chips.
                  accent: context.colors.successGreen,
                  chipStyle: true,
                  onChanged: (v) => setState(() {
                    _outcomeFilter = v;
                    _page = 0;
                  }),
                ),
                const Spacer(),
                if (async.valueOrNull != null)
                  StatChip(
                    label: _outcomeFilter == kOutcomeAwaiting
                        ? 'Awaiting DG decision'
                        : (_outcomeFilter == kOutcomeSold
                            ? 'Sold goods'
                            : (_outcomeFilter != null
                                ? unsoldProposalLabel(_outcomeFilter)
                                : 'Awaiting disposal')),
                    // The DATABASE's count for this filter, so the number and
                    // the list can never disagree.
                    value: '${async.valueOrNull!.total}',
                    color: _outcomeFilter == kOutcomeAwaiting
                        ? context.colors.warningAmber
                        : (_outcomeFilter == kOutcomeSold
                            ? context.colors.successGreen
                            : context.colors.dangerRed),
                  ),
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(14),
            ] else
              DisposalPageHeader(
                title: 'Perishable Goods',
                subtitle: 'Goods that spoil — no warehouse, no appeal window. '
                    'Send them for disposal without waiting.',
                trailing: [
                  async.maybeWhen(
                    data: (rows) => _CountChip(count: rows.total),
                    orElse: () => const SizedBox(),
                  ),
                  async.maybeWhen(
                    data: (rows) => SendDisposalRequestButton(
                      actionable: rows.total,
                      onSubmitted: () {
                        ref.invalidate(livePackagesProvider);
                        ref.invalidate(perishablePageProvider);
                        ref.invalidate(sentPerishableKeysProvider);
                        ref.invalidate(requestableForfeitedPackagesProvider);
                      },
                    ),
                    orElse: () => const SizedBox(),
                  ),
                ],
              ).animate().fadeIn(),
            if (!widget.readOnly) const Gap(20),
            // ⚠️ Boxed, like Forfeited and Other beside it. Every held-goods
            // page on the yard puts its search box and its filters INSIDE one
            // gold-bordered card, so the controls read as one panel and the
            // table below it starts at a clear edge. This page left them bare
            // on the page, which is why it looked like a different screen
            // however closely the individual controls matched.
            if (!widget.readOnly)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _searchBox(context),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DateFilterButton(
                          dateRange: _dateRange,
                          year: _yearFilter,
                          // ⚠️ Its own query: one page cannot know which years
                          // the table covers.
                          years: srYears(
                              ref.watch(perishableYearsProvider).valueOrNull ??
                                  const <String>[]),
                          onChanged: (range, year) => setState(() {
                            _dateRange = range;
                            _yearFilter = year;
                            _page = 0;
                          }),
                        ),
                        const SizedBox(width: 8),
                        StyledDropdownButton<String>(
                          value: _activity == 'all' ? null : _activity,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // ⚠️ EVERY activity, unfiltered. A perishable is
                          // registered under whatever activity the officer chose,
                          // and the list is not narrowed for this page -- see the
                          // SR form, which offers them all here for the same
                          // reason.
                          options: kAllPostStatusActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _activity = v ?? 'all';
                            _page = 0;
                          }),
                        ),
                        const SizedBox(width: 8),
                        OutcomeFilter(
                          value: _outcomeFilter,
                          // Every ruling the DG can make, plus a sale -- which on
                          // this page is an ending of its own.
                          outcomes: kUnsoldProposals,
                          includeSold: true,
                          onChanged: (v) => setState(() {
                            _outcomeFilter = v;
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
            if (!widget.readOnly) const Gap(16),
            Expanded(
              child: async.when(
                loading: () => Center(
                    child: CircularProgressIndicator(
                        color: context.colors.primaryGold)),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(perishablePageProvider(query))),
                data: (result) {
                  // Filtered, sorted and paged by the database. Nothing left
                  // to narrow here.
                  final pageRows = _rowsFrom(result);
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
                              // ⚠️ A minWidth is still required —
                              // data_table_2 ASSERTS when its fixed-width
                              // columns outgrow the parent, and the
                              // failure is a red screen, not a squeeze —
                              // but 1180 was far above what this table
                              // actually needs, so it scrolled sideways on
                              // a window it would have fitted.
                              //
                              // The fixed columns come to 699 on the
                              // yard's view (HS Code 110 + Qty 70 +
                              // Entry Date 110 + Valuation 140 +
                              // Status 214 + Details 55) and 829 with
                              // Central Disposal's extra Yard column. 820 clears
                              // the larger of the two and leaves the three
                              // proportional columns — SR Number, Goods
                              // Name, Consignee — room to be readable,
                              // while letting the table fit a narrow
                              // window instead of scrolling.
                              minWidth: 820,
                              isHorizontalScrollBarVisible: false,
                              empty: const EmptyTableState(
                                icon: Icons.eco_rounded,
                                message: 'No perishable goods',
                                subtitle:
                                    'Goods registered as perishable appear '
                                    'here until they are sent for disposal.',
                              ),
                              columns: [
                                const DataColumn2(
                                    label: Text('SR Number'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('Goods Name'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('HS Code'),
                                    size: ColumnSize.S,
                                    fixedWidth: 110),
                                const DataColumn2(
                                    label: Center(child: Text('No. of Goods')),
                                    size: ColumnSize.S,
                                    fixedWidth: 100),
                                const DataColumn2(
                                    label: Text('Post Status Activity'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('Entry Date'),
                                    size: ColumnSize.S,
                                    fixedWidth: 110),
                                const DataColumn2(
                                    label: Text('Consignee'),
                                    size: ColumnSize.M),
                                if (widget.readOnly)
                                  const DataColumn2(
                                      label: Text('Yard'),
                                      size: ColumnSize.S,
                                      fixedWidth: 130),
                                const DataColumn2(
                                    label: Center(child: Text('Valuation')),
                                    size: ColumnSize.S,
                                    fixedWidth: 140),
                                const DataColumn2(
                                    label: Center(child: Text('Status')),
                                    size: ColumnSize.S,
                                    // The shared constant, so this column and
                                    // the Destroyed/Delivered ones stay in
                                    // step when the pill width changes.
                                    fixedWidth: kDestructionStatusColumnWidth),
                                const DataColumn2(
                                    label: Center(child: Text('Details')),
                                    size: ColumnSize.S,
                                    fixedWidth: 55),
                              ],
                              rows: pageRows.map((r) {
                                final hasOutcome = outcomes[r.item.id] != null;
                                final isSold =
                                    result.soldPriceByItem[r.item.id] != null;
                                final isSent =
                                    result.sentByItem[r.item.id] ?? false;
                                final isMarkedUnsold =
                                    result.markedUnsoldByItem[r.item.id] ??
                                        false;
                                final isInYard = !hasOutcome &&
                                    !isSold &&
                                    !isSent &&
                                    !isMarkedUnsold;
                                final canDispose = !widget.readOnly && isInYard;
                                final activity =
                                    (r.item.reasons?.trim().isNotEmpty ?? false)
                                        ? r.item.reasons!.trim()
                                        : (r.package.reason
                                                    ?.trim()
                                                    .isNotEmpty ??
                                                false
                                            ? r.package.reason!.trim()
                                            : '—');
                                return DataRow(cells: [
                                  DataCell(TooltipText(r.package.srNumber,
                                      style: TextStyle(
                                          color: context.colors.accentLightBlue,
                                          fontWeight: FontWeight.w600))),
                                  DataCell(TooltipText(r.item.itemName,
                                      overflow: TextOverflow.ellipsis)),
                                  DataCell(TooltipText(
                                      (r.item.hsCode?.isNotEmpty ?? false)
                                          ? r.item.hsCode!
                                          : '—',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12))),
                                  DataCell(QtyCell(item: r.item)),
                                  DataCell(
                                      _PostStatusActivityChip(label: activity)),
                                  DataCell(TooltipText(DateFormat('yyyy-MM-dd')
                                      .format(r.package.entryDate ??
                                          r.package.createdAt))),
                                  DataCell(TooltipText(r.package.consigneeName,
                                      overflow: TextOverflow.ellipsis)),
                                  if (widget.readOnly)
                                    DataCell(TooltipText(
                                        yardName(
                                            yardOfSrNumber(r.package.srNumber)),
                                        overflow: TextOverflow.ellipsis)),
                                  DataCell(Center(
                                    child: _PerishValuationCell(
                                        unitCost: valuations[r.item.id],
                                        qty: r.item.quantity),
                                  )),
                                  DataCell(Center(
                                      child: _PerishableOutcomeChip(
                                          proposal: outcomes[r.item.id],
                                          soldPrice:
                                              result.soldPriceByItem[r.item.id],
                                          sent: isSent,
                                          markedUnsold: isMarkedUnsold,
                                          status: r.item.status))),
                                  DataCell(Center(
                                    child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        final fp = ref
                                            .read(forfeitedByItemProvider(
                                                r.package.id))
                                            .valueOrNull?[r.item.id];
                                        showAppDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: r.package,
                                            storageRate: storageRate,
                                            highlightItemId: r.item.id,
                                            useLegacySummary: true,
                                            tenderHistoryFor: fp,
                                            valuationQty: r.item.quantity,
                                            forceFinalDisposition: canDispose,
                                            allowFinalDisposition: canDispose,
                                            onSaleOrDestroyRequest: canDispose
                                                ? (disposition) =>
                                                    _requestSingleDisposal(
                                                        r.package, disposition,
                                                        itemId: r.item.id)
                                                : null,
                                            headerAccentColor: widget.readOnly
                                                ? context.colors.successGreen
                                                : null,
                                            yardLabel: widget.readOnly
                                                ? yardName(yardOfSrNumber(
                                                    r.package.srNumber))
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  )),
                                ]);
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
                        accent: accent,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ],
                  )
                      // ⚠️ 300ms, not 200 — the filter bar above it already
                      // uses 200, so the two were sliding in together and the
                      // page arrived as one block instead of settling top to
                      // bottom. Every other table waits 300.
                      .animate()
                      .slideY(begin: 0.1, duration: 400.ms, delay: 300.ms)
                      .fadeIn();
                },
              ),
            ),
          ],
        ),
      ),
    );

    // Central Disposal renders this inside its own tab bar, which already has
    // a shell of its own.
    return widget.readOnly
        ? body
        : AppShell(currentRoute: '/perishable-goods', child: body);
  }
}

/// The search field's border, matching `DisposalSearch` on every other
/// Central Disposal tab (14px radius, gold at 0.4, 1.5px when focused).
OutlineInputBorder _searchBorder(BuildContext context,
        {bool focused = false}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: focused
            ? context.colors.primaryGold
            : context.colors.primaryGold.withOpacity(0.4),
        width: focused ? 1.5 : 1,
      ),
    );

class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = context.colors.dangerRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Awaiting disposal',
            style:
                TextStyle(color: context.colors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

/// The lifecycle outcome chip for perishable goods.
///
/// Distinguishes among:
/// 1. Sold at tender -> "Sold" (Green)
/// 2. DG decided outcome -> e.g. "Destroy" / "Convert" / "Government Use" (from unsoldOutcomeStyle)
/// 3. Failed Special Tender Sale and marked unsold -> "Awaiting Top Management" (Orange)
/// 4. Sent to Central Disposal in a request -> "In Tender" (Gold)
/// 5. In Yard, not yet sent -> "In Yard" (Muted)
/// What a perishable's single special tender sale was priced at.
///
/// ⚠️ Per ITEM. A package holds several, each forfeited separately with
/// its own valuation, and pricing the whole package on a row about one of
/// them would overstate it.
class _PerishValuationCell extends StatelessWidget {
  const _PerishValuationCell({required this.unitCost, this.qty});

  /// Per-unit, from the page's own map.
  final double? unitCost;
  final int? qty;

  @override
  Widget build(BuildContext context) {
    final unit = unitCost;
    if (unit == null) {
      return Text('Not set',
          style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic));
    }
    final n = qty ?? 1;
    final money = NumberFormat('#,##0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('LKR ${money.format(unit * n)}',
            style: TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        Text('@ ${money.format(unit)} × $n',
            style: TextStyle(fontSize: 10, color: context.colors.textMuted)),
      ],
    );
  }
}

class _PerishableOutcomeChip extends StatelessWidget {
  final UnsoldProposalModel? proposal;
  final double? soldPrice;
  final bool sent;
  final bool markedUnsold;

  /// The item's own [PackageItem.status] — 'Perishable' while it is still
  /// awaiting disposal, or a terminal value once a Final Disposition has been
  /// recorded directly from this page (RELEASE / DESTROY / RE-EXPORT / OTHER).
  ///
  /// ⚠️ DEFENSIVE ONLY. Migrations 039 and 040 remove a finalised item
  /// (RELEASED / DESTROYED / RE-EXPORTED / OTHER / SOLD) from this page's own
  /// query entirely — it belongs on its own outcome table now, the same as
  /// any other package's, and should never reach this widget in normal
  /// operation. This branch exists so that IF a stale cache or a future
  /// direct link ever hands the chip a finalised item anyway, it reads as
  /// what it is rather than falling through to the same "In Yard" the page
  /// shows for something nobody has touched — which is the reported bug, and
  /// the whole reason this field exists.
  final String status;

  const _PerishableOutcomeChip({
    required this.proposal,
    required this.soldPrice,
    required this.sent,
    required this.markedUnsold,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    switch (status.toLowerCase()) {
      case 'released':
        return statusPill(
          context,
          color: context.colors.successGreen,
          icon: Icons.check_circle_outline_rounded,
          label: 'Released',
          tooltip: 'Final Disposition: released to the owner',
        );
      case 'destroyed':
        return statusPill(
          context,
          color: context.colors.dangerRed,
          icon: Icons.delete_outline_rounded,
          label: 'Destroyed',
          tooltip: 'Final Disposition: destroyed',
        );
      case 're-exported':
        return statusPill(
          context,
          color: context.colors.accentLightBlue,
          icon: Icons.flight_takeoff_rounded,
          label: 'Re-exported',
          tooltip: 'Final Disposition: re-exported to origin',
        );
      case 'other':
        return statusPill(
          context,
          color: context.colors.textSecondary,
          icon: Icons.more_horiz_rounded,
          label: 'Other',
          tooltip: 'Final Disposition: recorded as a custom outcome',
        );
    }

    // ⚠️ Also defensive now, for the same reason as the switch above: 040
    // excludes SOLD from this page's own query, so a sale should already be
    // on Sold Goods by the time any row reaches this widget.
    final sold = soldPrice;
    if (sold != null) {
      return statusPill(
        context,
        color: context.colors.successGreen,
        icon: Icons.sell_rounded,
        label: 'Sold',
        tooltip: 'Sold at tender for Rs ${sold.toStringAsFixed(2)} — these '
            'goods never went to the Top Management Directorate',
      );
    }

    final p = proposal;
    if (p != null) {
      final st = unsoldOutcomeStyle(context, p.proposal);
      return statusPill(
        context,
        color: st.colour,
        icon: st.icon,
        label: p.label,
        tooltip: p.note?.trim().isNotEmpty == true
            ? p.note!.trim()
            : 'Decided ${DateFormat('yyyy-MM-dd').format(p.decidedAt)}',
      );
    }

    if (markedUnsold) {
      return statusPill(
        context,
        color: context.colors.warningAmber,
        icon: Icons.hourglass_bottom_rounded,
        label: 'Awaiting Top Management',
        tooltip: 'Failed Special Tender Sale — awaiting DG decision',
      );
    }

    if (sent) {
      return statusPill(
        context,
        color: context.colors.primaryGold,
        icon: Icons.local_shipping_rounded,
        label: 'In Tender',
        tooltip: 'Sent to Central Disposal for Special Tender Sale',
      );
    }

    return statusPill(
      context,
      color: context.colors.textMuted,
      icon: Icons.inventory_2_outlined,
      label: 'In Yard',
      tooltip: 'Held in the yard — not yet sent for disposal',
    );
  }
}

class _PostStatusActivityChip extends StatelessWidget {
  final String label;
  const _PostStatusActivityChip({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty || label.trim() == '—') {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    final color = context.colors.warningAmber;
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
