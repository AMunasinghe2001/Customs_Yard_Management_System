import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/providers.dart';
import '../../core/post_status_activities.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/disposal_page_header.dart';
import '../../widgets/appeal_state_chip.dart';
import 'disposal_request_dialog.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/date_filter_button.dart';
import '../../widgets/send_disposal_request_button.dart';

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class ForfeitedPackagesScreen extends ConsumerStatefulWidget {
  const ForfeitedPackagesScreen({super.key});

  @override
  ConsumerState<ForfeitedPackagesScreen> createState() =>
      _ForfeitedPackagesScreenState();
}

// ⚠️ `_ForfeitRow` lived here, holding a forfeited record, an item and
// a warehouse entry per line -- so a table of 48 rows kept all 42 records in
// memory. `ForfeitRowData` replaces it: flat, one row of what the table
// shows, with the records fetched for the page that needs them.
//
// Its `reason` getter is now the view's `reason` column, with the same
// fallback chain: the entry's hold reason, then the item's, then the
// forfeited record's -- spelled exactly as kDisposalActivities does, or the
// filter cannot match it.

class _ForfeitedPackagesScreenState
    extends ConsumerState<ForfeitedPackagesScreen> {
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  String? _yearFilter;

  /// Post Status Activity filter — 'all', or one of [kDisposalActivities].
  String _activityFilter = 'all';

  /// ⚠️ The page. This table had no pager at all -- every forfeited row
  /// in the yard rendered at once, and the count grows with the yard.
  int _page = 0;

  /// Submits a single-package disposal request (Sale / Destruction) to the
  /// Central Disposal Directorate — used by the details popup's Final
  /// Disposition Sale/Destroy buttons. The package then leaves the Forfeited
  /// list (it is now "requested") and surfaces in the directorate's queue.
  Future<void> _requestSingleDisposal(
      ForfeitedPackageModel fp, String disposition,
      {PackageItem? item, WarehouseEntryModel? entry}) async {
    try {
      // When this row represents a specific item + partial forfeit warehouse
      // event, send a 4-part synthetic key so createDisposalRequest creates a
      // per-item FP row carrying that entry's qty as entry_qty — Valuation /
      // Central Disposal then price the partial forfeit qty (e.g. 2) instead of
      // the full registered item quantity (e.g. 48). Otherwise fall back to the
      // plain FP id (full-package forfeit).
      final key = (item != null && entry != null)
          ? '${fp.id}:${item.id}:${entry.id}:forfeit'
          : (item != null)
              ? '${fp.id}:${item.id}:forfeit'
              : fp.id;
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
        requestDate: DateTime.now(),
        dispositions: {key: disposition},
      );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(forfeitedPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(
              'Disposal request sent for ${fp.srNumber} (${disposition == 'sale' ? 'Sale' : 'Destruction'}).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    }
  }

  // ⚠️ Three helpers went with the row builder: _isForfeitStatus,
  // _isForfeitEntry (a `[FORFEIT…` / `[CONFISCATED…` warehouse note) and
  // _itemHasFinalDisposition (a `[FINAL:…` one). All three are clauses in
  // postgres/49 now.

  /// Builds one row per forfeited item / per forfeit disposition event.
  /// A single SR can appear on multiple lines.
  // ⚠️ `_buildForfeitRows` lived here: 122 lines deciding which forfeited
  // records become which table rows. It is `forfeit_rows` (postgres/49)
  // now, transcribed clause by clause and checked row-for-row against this
  // code on the live data before it was removed.
  //
  // Its doc comment is worth keeping: one row per forfeited ITEM or per
  // forfeit DISPOSITION EVENT, so a single SR can appear on several lines.

  @override
  Widget build(BuildContext context) {
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    // ⚠️ One page from SQL. This screen fetched every forfeited package
    // with its items and warehouse entries, ran 122 lines of row-building over
    // it, filtered the result four ways, and rendered all of it -- there was
    // no pager at all. `forfeit_rows` (postgres/49) carries the lot.
    final query = ForfeitQuery(
      page: _page,
      search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
      activity: _activityFilter,
    );
    final forfeitedAsync = ref.watch(forfeitPageProvider(query));
    // ⚠️ Counted over the whole table, not the page.
    final counts = ref.watch(forfeitCountsProvider).valueOrNull;

    return AppShell(
      currentRoute: '/forfeited-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Builder(builder: (context) {
                final totalCount = counts?.total ?? 0;
                final actionableCount = counts?.actionable ?? 0;
                  return DisposalPageHeader(
                    title: 'Forfeited Goods',
                    subtitle:
                        'Manage forfeited packages and their 30-day appeal periods',
                    trailing: [
                      _StatChip(
                          label: 'Total',
                          value: totalCount.toString(),
                          color: context.colors.accentLightBlue),
                      // "In Appeal" counts what is BLOCKED, so it must exclude
                      // rows an appeal decision already freed — otherwise the
                      // two chips overlap.
                      _StatChip(
                          label: 'In Appeal',
                          value: (totalCount - actionableCount).toString(),
                          color: context.colors.warningAmber),
                      _StatChip(
                          label: 'Actionable',
                          value: actionableCount.toString(),
                          color: context.colors.successGreen),
                      SendDisposalRequestButton(
                        actionable: actionableCount,
                        onSubmitted: () {
                          ref.invalidate(forfeitedPackagesProvider);
                          ref.invalidate(
                              requestableForfeitedPackagesProvider);
                        },
                      ),
                    ],
                  );
              }),
              const Gap(24),

              // ── Search Bar ──────────────────────────────────────
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
                    TextField(
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by SR Number or Consignee...',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: context.colors.textMuted),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onChanged: (value) =>
                          setState(() {
                            _searchQuery = value.toLowerCase();
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
                              ref.watch(forfeitRowYearsProvider).valueOrNull ??
                                  const <String>[]),
                          onChanged: (range, year) => setState(() {
                            _dateRange = range;
                            _yearFilter = year;
                            _page = 0;
                          }),
                        ),
                        const SizedBox(width: 8),
                        
                        StyledDropdownButton<String>(
                          value:
                              _activityFilter == 'all' ? null : _activityFilter,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // Forfeited goods only ever carry a DISPOSAL
                          // activity — the SR form offers no other kind for
                          // this status.
                          options: kDisposalActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) =>
                              setState(() { _activityFilter = v ?? 'all'; _page = 0; }),
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

              // ── Data Table ──────────────────────────────────────
              Expanded(
                child: forfeitedAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (error, stackTrace) => ErrorView(
                    error: error.toString(),
                    onRetry: () => ref.refresh(forfeitedPackagesProvider),
                  ),
                  data: (data) {
                    // ⚠️ Nothing is built, filtered or sorted here any more.
                    //
                    // `_buildForfeitRows` walked every forfeited package with
                    // its items and warehouse entries -- 122 lines of rules --
                    // and the search, dates, year and activity chip then
                    // filtered the result. All of it is `forfeit_rows`
                    // (postgres/49) now, checked row-for-row against that code
                    // on the live data, and the table takes a page.
                    final rows = data.rows;
                    final packagesById = data.packages;

                    return Container(
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 10,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          // Keep the header + show a haloed empty state in the
                          // rows area when there's nothing (Released-page style).
                          empty: const EmptyTableState(
                              icon: Icons.gavel_outlined,
                              message: 'No forfeited packages found',
                              subtitle:
                                  'Try adjusting the search or date filters.'),
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Goods Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('HS Code'),
                                size: ColumnSize.S,
                                fixedWidth: 110),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            DataColumn2(
                                label: Text('Post Status Activity'),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Forfeited Date'),
                                size: ColumnSize.S,
                                fixedWidth: 110),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Appeal')),
                                size: ColumnSize.S,
                                fixedWidth: 140),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: rows.map((row) {
                            // ⚠️ The record, the item and the entry, resolved
                            // from THIS page's records rather than held on the
                            // row. A row that cannot find its record is a row
                            // the view built from data the fetch did not
                            // return -- skipped rather than crashed, since a
                            // half-drawn table is worse than a shorter one.
                            final pkg = packagesById[row.forfeitedPackageId];
                            if (pkg == null) return const DataRow(cells: []);
                            final rowItem = row.itemId == null
                                ? null
                                : pkg.packageDetails?.items
                                    .where((i) => i.id == row.itemId)
                                    .firstOrNull;
                            final rowEntry = row.entryId == null
                                ? null
                                : pkg.packageDetails?.warehouseEntries
                                    .where((e) => e.id == row.entryId)
                                    .firstOrNull;
                            // Appeal holds are PER ITEM: the directorate can hold
                            // one item of a package while its siblings stay in the
                            // normal appeal window. heldItemIds names the specific
                            // items on hold; only fall back to the package-wide
                            // appealHold flag for legacy rows that have no per-item
                            // list. So this row shows "APPEAL HOLD" only when THIS
                            // item is the one held — not every row of the package.
                            final rowOnAppealHold = pkg.heldItemIds.isNotEmpty
                                ? (row.itemId != null &&
                                    pkg.heldItemIds.contains(row.itemId))
                                : pkg.appealHold;
                            // Appeal decisions are PER ITEM too — resolve this
                            // row's item against the per-item decision map so
                            // deciding one item doesn't mark its siblings.
                            final rowHasDecision =
                                pkg.hasAppealDecisionForItem(row.itemId);
                            final rowDecisionLabel =
                                pkg.appealDecisionLabelForItem(row.itemId);

                            return DataRow(
                              // ⚠️ An EDGE, not a wash.
                              //
                              // This said "the appeal window has closed" in
                              // dangerRed at 4%. Perishable rows on the
                              // disposal tables say "different kind of
                              // goods" in warningAmber at 6% — and a red
                              // and an orange both diluted to a few percent
                              // over white are the same pale rose to the
                              // eye. Two unrelated meanings became one
                              // colour a reader had to guess at, so goods
                              // whose appeal had run out looked perishable.
                              //
                              // The bar keeps the signal on the row without
                              // competing: nothing else on these pages
                              // marks a row from its left edge.
                              cells: [
                                DataCell(TooltipText(pkg.srNumber,
                                    style: TextStyle(
                                        color: context.colors.accentLightBlue,
                                        fontWeight: FontWeight.bold))),
                                DataCell(TooltipText(row.itemName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500))),
                                DataCell(TooltipText(
                                    (row.hsCode != null &&
                                            row.hsCode!.isNotEmpty)
                                        ? row.hsCode!
                                        : '—',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12))),
                                DataCell(TooltipText('${row.qty}')),
                                DataCell(_PostStatusActivityChip(
                                    label: row.reason)),
                                DataCell(TooltipText(DateFormat('yyyy-MM-dd')
                                    .format(row.forfeitedDate))),
                                DataCell(TooltipText(pkg.consigneeName,
                                    overflow: TextOverflow.ellipsis)),
                                DataCell(Center(
                                  child: rowOnAppealHold
                                      // Appeal Directorate has placed a hold on
                                      // THIS item — it must NOT be sold/destroyed.
                                      ? Tooltip(
                                          message: pkg.appealHoldNote
                                                      ?.isNotEmpty ==
                                                  true
                                              ? pkg.appealHoldNote!
                                              : 'Appeal received — do not sell or destroy',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: context.colors.warningAmber
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: context
                                                      .colors.warningAmber
                                                      .withOpacity(0.5)),
                                            ),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.gavel_rounded,
                                                      size: 12,
                                                      color: context
                                                          .colors.warningAmber),
                                                  const Gap(4),
                                                  Flexible(
                                                    child: Text('APPEAL HOLD',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: 10.5,
                                                            color: context
                                                                .colors
                                                                .warningAmber,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                  ),
                                                ]),
                                          ),
                                        )
                                      : rowHasDecision
                                          // Appeal processed — directorate told
                                          // the yard what to do with this item.
                                          ? Tooltip(
                                              message:
                                                  'Appeal decision: $rowDecisionLabel',
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: context
                                                      .colors.accentLightBlue
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: context.colors
                                                          .accentLightBlue
                                                          .withOpacity(0.4)),
                                                ),
                                                child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.gavel_rounded,
                                                          size: 12,
                                                          color: context.colors
                                                              .accentLightBlue),
                                                      const Gap(4),
                                                      Flexible(
                                                        child: Text(
                                                            '→ $rowDecisionLabel',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                                fontSize: 10.5,
                                                                color: context
                                                                    .colors
                                                                    .accentLightBlue,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                      ),
                                                    ]),
                                              ),
                                            )
                                          // The SAME chip the Abandoned and
                                          // Other tables use, so one status
                                          // reads identically everywhere.
                                          // A forfeit carries its OWN recorded
                                          // deadline (forfeited_at + 30 days),
                                          // which is later than entry + 30.
                                          : AppealStateChip(
                                              entryDate: pkg.forfeitedAt,
                                              deadline: pkg.appealDeadline),
                                )),
                                DataCell(Center(
                                  child: IconButton(
                                    icon: Icon(Icons.info_outline_rounded,
                                        color: context.colors.accentLightBlue,
                                        size: 18),
                                    tooltip: 'View details',
                                    onPressed: pkg.packageDetails == null
                                        ? null
                                        : () => showAppDialog(
                                              context: context,
                                              builder: (_) =>
                                                  PackageDetailsDialog(
                                                package: pkg.packageDetails!,
                                                storageRate: storageRate,
                                                highlightEntry: rowEntry,
                                                // Pin the exact item this row is
                                                // about so the popup shows only
                                                // it (not every sibling) even
                                                // when the item has no entry.
                                                highlightItemId: row.itemId,
                                                useLegacySummary: true,
                                                appealDecisionLabel:
                                                    rowHasDecision
                                                        ? rowDecisionLabel
                                                        : null,
                                                // Restrict the Final Disposition
                                                // dialog to the decided action.
                                                appealDecisionCode: rowHasDecision
                                                    ? pkg.appealDecisionForItem(
                                                        row.itemId)
                                                    : null,
                                                // Final disposition once the
                                                // window has passed OR a per-item
                                                // appeal decision was received.
                                                allowFinalDisposition:
                                                    pkg.isAppealExpired ||
                                                        rowHasDecision,
                                                // Sale / Destroy → disposal
                                                // request to Central Disposal.
                                                onSaleOrDestroyRequest:
                                                    (disposition) =>
                                                        _requestSingleDisposal(
                                                            pkg, disposition,
                                                            item: rowItem,
                                                            entry: rowEntry),
                                              ),
                                            ),
                                  ),
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 100.ms)
                        .fadeIn();
                  },
                ),
              ),
              // ⚠️ The pager this table never had. Against the SERVER's
              // count: `rows.length` is the page size.
              forfeitedAsync.maybeWhen(
                data: (data) => TablePager(
                  total: data.total,
                  page: _page,
                  pageSize: kDispositionPageSize,
                  onPageChanged: (v) => setState(() => _page = v),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
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
