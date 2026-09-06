import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:data_table_2/data_table_2.dart';

import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/post_status_activities.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/appeal_state_chip.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/disposal_page_header.dart';
import '../forfeited_packages/disposal_request_dialog.dart';

final detainedPackageSearchProvider = StateProvider<String>((ref) => '');
final detainedPackageDateRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

/// Post Status Activity filter — 'all', or one of [kDetainActivities].
final detainedPackageActivityProvider = StateProvider<String>((ref) => 'all');

/// The statuses that mean "held under inquiry".
const Set<String> _detainStatuses = {'detain', 'detained', 'held'};

/// A note that means this item has moved on — it is no longer merely detained.
bool _isSettledNote(String? note) {
  final n = (note ?? '').trim().toUpperCase();
  return n.startsWith('[FINAL:') ||
      n.startsWith('[ABANDONED]') ||
      n.startsWith('[OTHER]') ||
      n.startsWith('[FORFEIT');
}

bool _packageHasDetained(PackageModel p) =>
    p.items.any((item) => _itemIsDetained(p, item));

/// True if a single item is DETAINED and still awaiting a decision.
///
/// Detention is a holding status, not a disposition: unlike Abandoned or
/// "Other" there is no `[DETAIN]` event to record. The item simply carries a
/// detain status and has not been finalised or moved to another status.
bool _itemIsDetained(PackageModel p, PackageItem item) {
  if (!_detainStatuses.contains(item.status.trim().toLowerCase())) {
    return false;
  }
  final entries = p.warehouseEntries.where((e) => e.packageItemId == item.id);
  return !entries.any((e) => _isSettledNote(e.returnNotes));
}

/// Detained Goods — the yard's holding pool.
///
/// Detained goods sit under inquiry with no disposition recorded, so until now
/// there was no way to act on them: Forfeited, Abandoned and "Other" each had a
/// page that could send goods to Central Disposal for Sale or Destruction, but
/// Detain did not. This page gives them the same route.
///
/// The 30-day appeal window still governs when that route opens — and an
/// Appeal Directorate decision opens it early (see [AppealStateChip]).
class DetainedPackagesScreen extends ConsumerStatefulWidget {
  const DetainedPackagesScreen({super.key});

  @override
  ConsumerState<DetainedPackagesScreen> createState() =>
      _DetainedPackagesScreenState();
}

class _DetainedPackagesScreenState
    extends ConsumerState<DetainedPackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  String? _yearFilter;

  /// ⚠️ New: this page had no pager at all. Every filter change resets it, or
  /// a narrowed result leaves the reader stranded on a page that no longer
  /// exists.
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // ⚠️ SYNCHRONOUS, not in a post-frame callback.
    //
    // The search box is an Autocomplete, which builds its own controller. The
    // fieldViewBuilder copies _tableSearchCtrl into it, but a post-frame
    // callback runs AFTER that first build and calls no setState -- so leaving
    // the page and coming back left the table filtered by the remembered query
    // while the box showed nothing. The filter was on and invisible.
    //
    // Assigning here means the first build already has the text.
    _tableSearchCtrl.text = ref.read(detainedPackageSearchProvider);
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  /// Sends ONE detained item to Central Disposal for Sale or Destruction.
  ///
  /// `createDisposalRequest` creates the `source='detain'` forfeited_packages
  /// row on the fly, exactly as it does for Abandoned and "Other" goods. The
  /// item-level key keeps each item on its own row so a sibling item is never
  /// dragged along.
  Future<void> _requestSingleDisposal(PackageModel pkg, String disposition,
      {required String itemId, WarehouseEntryModel? entry}) async {
    try {
      final key = entry != null
          ? '${pkg.id}:$itemId:${entry.id}:detain'
          : '${pkg.id}:$itemId:detain';
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
        requestDate: DateTime.now(),
        dispositions: {key: disposition},
      );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(livePackagesProvider);
      ref.invalidate(requestableForfeitedPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text('Disposal request sent for ${pkg.srNumber} '
              '(${disposition == 'sale' ? 'Sale' : 'Destruction'}).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    }
  }

  /// One row per detained ITEM, so a single SR can appear several times.
  ///
  /// [sentKeys] — "pkgId:itemId" keys already sent in a disposal request;
  /// those rows drop off, the same way they do on the other status pages.
  /// The view's rows, as this page's widgets already expect them.
  ///
  /// ⚠️ Replaces `_buildRows`, which walked every package in the yard. Which
  /// items count as detained now lives in the view (postgres/25): the status
  /// is detain/detained/held, and NO warehouse entry carries a settled note.
  /// Detention is a holding status with no [DETAIN] event of its own, so what
  /// ends it is the arrival of some other disposition.
  List<_DetainRow> _rowsFrom(HeldGoodsPage result) {
    final out = <_DetainRow>[];
    for (final k in result.keys) {
      final pkg = result.packages[k.packageId];
      if (pkg == null) continue;
      final item = pkg.items.where((i) => i.id == k.itemId).firstOrNull;
      if (item == null) continue;

      final itemEntries =
          pkg.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
      // The live holding entry carries the qty, the hold reason and the
      // officer; fall back to the item itself when there is none.
      final held = itemEntries.where((e) => !e.isReturned).firstOrNull ??
          (itemEntries.isNotEmpty ? itemEntries.first : null);

      out.add(_DetainRow(
        package: pkg,
        item: item,
        entry: held,
        qty: held?.itemCount ?? item.quantity,
        date: held?.admittedAt ?? pkg.entryDate ?? pkg.createdAt,
        // ⚠️ The Post Status Activity, which is what `hold_reason` stores --
        // the filter matches on it, so the fallback must be spelled exactly
        // as kDetainActivities does or it could never be selected.
        reason: (held?.holdReason.trim().isNotEmpty ?? false)
            ? held!.holdReason.trim()
            : ((item.reasons?.trim().isNotEmpty ?? false)
                ? item.reasons!.trim()
                : 'Pending Inquiry'),
        officer: held?.admittedByName ?? held?.admittedByBadge ?? '—',
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ This page had NO pager at all: it fetched every package in the yard
    // and handed the whole list to DataTable2. Every row-selection rule now
    // lives in the `held_goods_rows` view (postgres/25, kind DETAINED), so a
    // page can be asked for by number.
    final query = HeldGoodsQuery(
      kind: 'DETAINED',
      page: _page,
      search: ref.watch(detainedPackageSearchProvider),
      dateStart: ref.watch(detainedPackageDateRangeProvider)?.start,
      dateEnd: ref.watch(detainedPackageDateRangeProvider)?.end,
      year: _yearFilter,
      activity: ref.watch(detainedPackageActivityProvider),
    );
    final packages = ref.watch(heldGoodsPageProvider(query));
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    // Appeal rulings, keyed by item id. A decision releases the goods early;
    // a hold keeps them frozen past the deadline.
    final appealOutcomes =
        ref.watch(allItemAppealOutcomesProvider).valueOrNull ??
            const <String, ItemAppealOutcome>{};
    final dateRange = ref.watch(detainedPackageDateRangeProvider);
    final activity = ref.watch(detainedPackageActivityProvider);
    // ⚠️ Items already sent to Central Disposal are excluded by the QUERY
    // now (`sent = false` on the view), not by a set held here.

    return AppShell(
      currentRoute: '/detained-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Consumer(
                builder: (context, ref, child) {
                  // ⚠️ Counted in SQL, by their own query. Derived from one
                  // page they would contradict the header they sit in;
                  // derived from the whole list they would undo the paging.
                  final counts =
                      ref.watch(heldGoodsCountsProvider('DETAINED')).valueOrNull ??
                          (total: 0, inAppeal: 0, actionable: 0);
                  final actionable = counts.actionable;
                  return DisposalPageHeader(
                    title: 'Detained Goods',
                    titleIcon: Icons.gpp_maybe_rounded,
                    subtitle: 'Goods held under inquiry — decide their outcome '
                        'or send them for sale or destruction',
                    trailing: [
                      _DetainStatChip(
                          label: 'Total',
                          value: '${counts.total}',
                          color: context.colors.accentLightBlue),
                      _DetainStatChip(
                          label: 'In Appeal',
                          value: '${counts.inAppeal}',
                          color: context.colors.warningAmber),
                      _DetainStatChip(
                          label: 'Actionable',
                          value: '$actionable',
                          color: context.colors.successGreen),
                      // Enabled once ANY row is actionable: the window passed,
                      // or an appeal decision is in. Opens the same bulk
                      // dialog the Forfeited page uses — detained goods appear
                      // in it as `source='detain'` rows.
                      ElevatedButton.icon(
                        icon: const Icon(Icons.local_shipping_rounded, size: 16),
                        label: const Text('Send Disposal Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: actionable > 0
                              ? context.colors.primaryGold
                              : context.colors.textMuted.withOpacity(0.2),
                          foregroundColor: actionable > 0
                              ? Colors.white
                              : context.colors.textMuted,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: actionable > 0 ? 2 : 0,
                        ),
                        onPressed: actionable > 0
                            ? () => showDialog(
                                  context: context,
                                  builder: (ctx) => DisposalRequestDialog(
                                    onSubmitted: () {
                                      ref.invalidate(livePackagesProvider);
                                      ref.invalidate(
                                          requestableForfeitedPackagesProvider);
                                    },
                                  ),
                                )
                            : null,
                      ),
                    ],
                  );
                },
              ).animate().fadeIn(),
              const Gap(20),

              // ── Search & filters ──
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
                    // Same SR autocomplete the Abandoned / Other pages use:
                    // typing suggests matching SRs, picking one filters to it.
                    Row(children: [
                      Expanded(
                        child: Autocomplete<PackageModel>(
                          displayStringForOption: (p) => p.srNumber,
                          initialValue:
                              TextEditingValue(text: _tableSearchCtrl.text),
                          optionsBuilder: (textEditingValue) {
                            final query =
                                textEditingValue.text.trim().toLowerCase();
                            if (query.isEmpty) return const <PackageModel>[];
                            final packages =
                                ref.read(livePackagesProvider).valueOrNull ??
                                    const <PackageModel>[];
                            return packages.where((p) =>
                                _packageHasDetained(p) &&
                                (p.srNumber.toLowerCase().contains(query) ||
                                    p.consigneeName
                                        .toLowerCase()
                                        .contains(query)));
                          },
                          onSelected: (package) {
                            setState(() {
                              _tableSearchCtrl.text = package.srNumber;
                              ref
                                  .read(detainedPackageSearchProvider.notifier)
                                  .state = package.srNumber;
                            });
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 500,
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: context.colors.surfaceDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: context.colors.borderColor),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4))
                                    ],
                                  ),
                                  child: ListView.builder(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return InkWell(
                                        onTap: () => onSelected(option),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                          child: Row(children: [
                                            Text(option.srNumber,
                                                style: TextStyle(
                                                    color: context
                                                        .colors.accentLightBlue,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const Gap(12),
                                            Expanded(
                                                child: Text(
                                                    option.consigneeName,
                                                    style: TextStyle(
                                                        color: context.colors
                                                            .textSecondary,
                                                        fontSize: 13),
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                            StatusChip(status: option.status),
                                          ]),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            if (controller.text != _tableSearchCtrl.text &&
                                _tableSearchCtrl.text.isNotEmpty &&
                                controller.text.isEmpty) {
                              controller.text = _tableSearchCtrl.text;
                            }
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style:
                                  TextStyle(color: context.colors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search SR #, consignee or goods...',
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: context.colors.textMuted),
                                suffixIcon: controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear_rounded,
                                            color: context.colors.textMuted),
                                        onPressed: () {
                                          controller.clear();
                                          _tableSearchCtrl.clear();
                                          ref
                                              .read(
                                                  detainedPackageSearchProvider
                                                      .notifier)
                                              .state = '';
                                        },
                                      )
                                    : null,
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onChanged: (v) {
                                _tableSearchCtrl.text = v;
                                ref
                                    .read(
                                        detainedPackageSearchProvider.notifier)
                                    .state = v;
                              },
                            );
                          },
                        ),
                      ),
                    ]),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDialog<DateTimeRange>(
                              context: context,
                              builder: (_) => custom.DateRangePickerDialog(
                                  initialRange: dateRange),
                            );
                            if (picked != null) {
                              ref
                                  .read(
                                      detainedPackageDateRangeProvider.notifier)
                                  .state = picked;
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            dateRange == null
                                ? 'Date Range'
                                : '${DateFormat('yyyy-MM-dd').format(dateRange.start)}'
                                    ' → '
                                    '${DateFormat('yyyy-MM-dd').format(dateRange.end)}',
                            style: TextStyle(
                                color: dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.textSecondary,
                                fontWeight: dateRange != null
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (dateRange != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.dangerRed),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => ref
                                .read(detainedPackageDateRangeProvider.notifier)
                                .state = null,
                          ),
                        const SizedBox(width: 8),
                        StyledDropdownButton<String>(
                          value: activity == 'all' ? null : activity,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // Detained goods only ever carry a DETAIN activity —
                          // the SR form offers no other kind for this status,
                          // so the disposal ones could never match.
                          options: kDetainActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => ref
                              .read(detainedPackageActivityProvider.notifier)
                              .state = v ?? 'all',
                        ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          // ⚠️ Its own query: one page of twenty rows would
                          // offer only the years currently visible.
                          years: srYears(ref
                                  .watch(heldGoodsYearsProvider('DETAINED'))
                                  .valueOrNull ??
                              const <String>[]),
                          onChanged: (v) => setState(() {
                            _yearFilter = v;
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
                child: packages.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.refresh(heldGoodsPageProvider(query))),
                  data: (result) {
                    // Filtered, sorted and paged by the database. Nothing left
                    // to narrow here.
                    final rows = _rowsFrom(result);
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    return Column(children: [
                      Expanded(
                        child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: context.colors.borderColor)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 12,
                          fixedTopRows: 1,
                          empty: const EmptyTableState(
                              icon: Icons.gavel_outlined,
                              message: 'No detained goods',
                              subtitle:
                                  'Goods held under inquiry appear here.'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
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
                                label: Text('Entry Date'), size: ColumnSize.S),
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
                            final outcome = appealOutcomes[row.item.id];
                            // Sale / Destroy only once the window has closed
                            // or the directorate has ruled — the same gate the
                            // Goods Actions sheet applies.
                            final canDispose = _isActionable(row, outcome);
                            return DataRow(cells: [
                              DataCell(TooltipText(row.package.srNumber,
                                  style: TextStyle(
                                      color: context.colors.accentLightBlue,
                                      fontWeight: FontWeight.w600))),
                              DataCell(TooltipText(row.itemName,
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(TooltipText(
                                  (row.item.hsCode?.isNotEmpty ?? false)
                                      ? row.item.hsCode!
                                      : '—',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))),
                              DataCell(Center(child: Text('${row.qty}'))),
                              DataCell(TooltipText(row.reason,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic))),
                              DataCell(TooltipText(
                                  DateFormat('yyyy-MM-dd').format(row.date))),
                              DataCell(TooltipText(
                                  row.package.consigneeName.isNotEmpty
                                      ? row.package.consigneeName
                                      : '—',
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(Center(
                                  child: AppealStateChip(
                                      entryDate: row.package.entryDate ??
                                          row.package.createdAt,
                                      outcome: outcome))),
                              DataCell(Center(
                                child: IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      color: context.colors.accentLightBlue,
                                      size: 18),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: row.package,
                                      storageRate: storageRateHistory,
                                      highlightEntry: row.entry,
                                      highlightItemId: row.item.id,
                                      useLegacySummary: true,
                                      // When the Appeal Directorate has ruled,
                                      // banner the ruling and enable ONLY that
                                      // action — the yard must carry out what
                                      // was decided, not choose afresh.
                                      appealDecisionLabel: outcome?.label,
                                      appealDecisionCode:
                                          (outcome?.isDecided ?? false)
                                              ? outcome!.decision
                                              : null,
                                      forceFinalDisposition: canDispose,
                                      allowFinalDisposition: canDispose,
                                      onSaleOrDestroyRequest: canDispose
                                          ? (disposition) =>
                                              _requestSingleDisposal(
                                                  row.package, disposition,
                                                  itemId: row.item.id,
                                                  entry: row.entry)
                                          : null,
                                    ),
                                  ),
                                ),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                    )
                            .animate()
                            .slideY(
                                begin: 0.1, duration: 400.ms, delay: 300.ms)
                            .fadeIn(),
                      ),
                      TablePager(
                        // The database's count for this filter.
                        total: result.total,
                        page: _page.clamp(0, maxPage),
                        pageSize: kDispositionPageSize,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether these goods can be sent for disposal yet.
  ///
  /// The 30-day appeal window blocks it, EXCEPT once the Appeal Directorate
  /// has ruled — a decision ends the wait. A hold blocks it either way, because
  /// that appeal is still open.
  static bool _isActionable(_DetainRow row, ItemAppealOutcome? outcome) {
    if (outcome?.onHold ?? false) return false;
    if (outcome?.unblocksAction ?? false) return true;
    return !isWithinAppealWindow(
        row.package.entryDate ?? row.package.createdAt);
  }
}

class _DetainRow {
  final PackageModel package;
  final PackageItem item;

  /// The warehouse entry holding these goods; null when none was recorded.
  final WarehouseEntryModel? entry;
  final int qty;
  final DateTime date;
  final String reason;
  final String officer;

  const _DetainRow({
    required this.package,
    required this.item,
    required this.entry,
    required this.qty,
    required this.date,
    required this.reason,
    required this.officer,
  });

  String get itemName => item.itemName;
}

class _DetainStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetainStatChip(
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
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
