import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../core/post_status_activities.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/appeal_state_chip.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import '../forfeited_packages/disposal_request_dialog.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/disposal_page_header.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/date_filter_button.dart';
import '../../widgets/send_disposal_request_button.dart';

final abandonedPackageSearchProvider = StateProvider<String>((ref) => '');
final abandonedPackageReasonFilterProvider =
    StateProvider<String>((ref) => 'all');
final abandonedPackageDateRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

/// True if a warehouse entry represents an ABANDONED disposition event.
/// Dispositions are tagged in returnNotes as e.g. "[ABANDONED] — note".
bool _isAbandonedEntry(WarehouseEntryModel e) {
  if (!e.isReturned) return false;
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  return notes.startsWith('[ABANDONED]');
}

/// True if an item's status is "abandoned" (set directly on the registration
/// form, rather than through a later disposition action).
bool _statusIsAbandoned(String? s) =>
    (s ?? '').trim().toLowerCase() == 'abandoned';

// ⚠️ `_itemHasFinalDisposition` moved into the view: an item with a [FINAL:]
// entry has an outcome already, and offering an action on it would let the
// same goods be disposed of twice. The view's verify block asserts it.

/// True if a package has any abandoned item — either a form-level abandoned
/// item, or a partial/full abandonment disposition event.
bool _packageHasAbandoned(PackageModel p) {
  for (final item in p.items) {
    final entries = p.warehouseEntries.where((e) => e.packageItemId == item.id);
    if (entries.any(_isAbandonedEntry)) return true;
    if (_statusIsAbandoned(item.status) && !entries.any(_isAbandonedEntry)) {
      return true;
    }
  }
  return false;
}

class AbandonedPackagesScreen extends ConsumerStatefulWidget {
  const AbandonedPackagesScreen({super.key});
  @override
  ConsumerState<AbandonedPackagesScreen> createState() =>
      _AbandonedPackagesScreenState();
}

class _AbandonedPackagesScreenState
    extends ConsumerState<AbandonedPackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  String? _yearFilter;

  /// ⚠️ New: this page had no pager at all. Reset on every filter change, or
  /// a narrowed result strands the reader on a page that no longer exists.
  int _page = 0;

  /// Submits a single-package disposal request (Sale / Destruction) for an
  /// abandoned package — used by the details popup's Final Disposition
  /// Sale/Destroy buttons. createDisposalRequest creates the synthetic
  /// forfeited_packages row for abandoned goods automatically.
  Future<void> _requestSingleDisposal(
      PackageModel pkg, PackageItem item, String disposition,
      {WarehouseEntryModel? entry}) async {
    try {
      // Include the entry ID when a warehouse entry exists so createDisposalRequest
      // can store entry.itemCount as entry_qty on the FP row — giving Tender Sales
      // the correct qty (e.g. 6 or 5) instead of the full registered quantity.
      final key = entry != null
          ? '${pkg.id}:${item.id}:${entry.id}:abandoned'
          : '${pkg.id}:${item.id}:abandoned';
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
          content: Text(
              'Disposal request sent for ${pkg.srNumber} (${disposition == 'sale' ? 'Sale' : 'Destruction'}).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    }
  }

  /// Builds one row per abandonment — broken down per package item.
  /// A single SR can appear on multiple lines: once per abandoned item, and
  /// once per separate abandonment event (e.g. detained → partly abandoned).
  /// [sentKeys] — "pkgId:itemId" keys for items already sent in a disposal
  /// request; those rows are hidden from the table.

  /// Whether these goods can be sent for disposal yet.
  ///
  /// Computed from data ALREADY on screen — the row and the appeal outcomes —
  /// so the header and the Send Disposal Request button settle as soon as the
  /// table does. Reading it from `requestableForfeitedPackagesProvider` meant
  /// waiting on that provider's heavy cross-table query, which is why the
  /// button took a moment to light up.
  ///
  /// ⚠️ The rule moved into `getHeldGoodsCounts`, which applies it in one
  /// place for the header: a HOLD always blocks, a decision releases early,
  /// and otherwise the 30-day window decides. Counting it here as well would
  /// mean the header and the query could disagree.

  /// The view's rows, as this page's widgets already expect them.
  ///
  /// ⚠️ Replaces `_buildRows`. Both sources live in the view now: an
  /// [ABANDONED] disposition EVENT (repeatable per item -- a partial
  /// abandonment is its own row) and a form-level 'abandoned' status with no
  /// event of its own, where the held entry supplies the context. Finalised
  /// items are excluded there too.
  List<_AbandonedRow> _rowsFrom(HeldGoodsPage result) {
    final out = <_AbandonedRow>[];
    for (final k in result.keys) {
      final pkg = result.packages[k.packageId];
      if (pkg == null) continue;
      final item = pkg.items.where((i) => i.id == k.itemId).firstOrNull;
      if (item == null) continue;

      final itemEntries =
          pkg.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
      // 'AE:<entryId>' is an abandonment EVENT; anything else is the
      // form-level status row, which takes the earliest entry as context.
      final isEvent = k.rowKey.startsWith('AE:');
      final entry = isEvent
          ? itemEntries
              .where((e) => 'AE:${e.id}' == k.rowKey)
              .firstOrNull
          : (itemEntries.isNotEmpty ? itemEntries.first : null);

      out.add(_AbandonedRow(
        package: pkg,
        item: item,
        entry: entry,
        qty: entry?.itemCount ?? item.quantity,
        date: isEvent
            ? (entry?.returnedAt ?? entry?.admittedAt)
            : entry?.admittedAt,
        reason: entry?.holdReason ??
            (item.reasons?.isNotEmpty == true ? item.reasons! : '—'),
        officer: isEvent
            ? (entry?.returnedByName ?? entry?.returnedByBadge ?? '—')
            : (entry?.admittedByName ?? '—'),
      ));
    }
    return out;
  }

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
    _tableSearchCtrl.text = ref.read(abandonedPackageSearchProvider);
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ This page had NO pager: it fetched every package in the yard and
    // handed the whole list to DataTable2. Both row sources -- the
    // [ABANDONED] disposition event and the form-level status -- now live in
    // the `held_goods_rows` view (postgres/25, kind ABANDONED).
    final query = HeldGoodsQuery(
      kind: 'ABANDONED',
      page: _page,
      search: ref.watch(abandonedPackageSearchProvider),
      dateStart: ref.watch(abandonedPackageDateRangeProvider)?.start,
      dateEnd: ref.watch(abandonedPackageDateRangeProvider)?.end,
      year: _yearFilter,
      activity: ref.watch(abandonedPackageReasonFilterProvider),
    );
    final packages = ref.watch(heldGoodsPageProvider(query));
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    // Appeal rulings, keyed by item id. A decision releases the goods early;
    // a hold keeps them frozen past the deadline.
    final appealOutcomes =
        ref.watch(allItemAppealOutcomesProvider).valueOrNull ??
            const <String, ItemAppealOutcome>{};
    // ⚠️ Items already sent to Central Disposal are excluded by the QUERY
    // now (`sent = false` on the view), not by a set held here.
    final dateRange = ref.watch(abandonedPackageDateRangeProvider);
    final rFilter = ref.watch(abandonedPackageReasonFilterProvider);

    return AppShell(
      currentRoute: '/abandoned-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Consumer(
                builder: (context, ref, child) {
                  // ⚠️ Counted in SQL, by their own query. Derived from one
                  // page they would contradict the header they sit in;
                  // derived from the whole list they would undo the paging.
                  final counts = ref
                          .watch(heldGoodsCountsProvider('ABANDONED'))
                          .valueOrNull ??
                      (total: 0, inAppeal: 0, actionable: 0);
                  final total = counts.total;
                  final actionable = counts.actionable;
                  return DisposalPageHeader(
                    title: 'Abandoned Goods',
                    subtitle: 'Manage abandoned goods and send them for disposal',
                    trailing: [
                      _AbandonedStatChip(
                          label: 'Total',
                          value: '$total',
                          color: context.colors.accentLightBlue),
                      _AbandonedStatChip(
                          label: 'In Appeal',
                          value:
                              '${total - actionable < 0 ? 0 : total - actionable}',
                          color: context.colors.warningAmber),
                      _AbandonedStatChip(
                          label: 'Actionable',
                          value: '$actionable',
                          color: context.colors.successGreen),
                      SendDisposalRequestButton(
                        actionable: actionable,
                        onSubmitted: () {
                          ref.invalidate(
                              requestableForfeitedPackagesProvider);
                          ref.invalidate(livePackagesProvider);
                        },
                      ),
                    ],
                  );
                },
              ).animate().fadeIn(),
              const Gap(20),

              // ── Unified Search & Filter Bar ──────────────────────
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
                    Row(children: [
                      Expanded(
                        child: Autocomplete<PackageModel>(
                          displayStringForOption: (p) => p.srNumber,
                          initialValue:
                              TextEditingValue(text: _tableSearchCtrl.text),
                          optionsBuilder: (textEditingValue) {
                            final query =
                                textEditingValue.text.trim().toLowerCase();
                            if (query.isEmpty) return const [];
                            final packages =
                                ref.read(livePackagesProvider).valueOrNull ??
                                    [];
                            return packages.where((p) =>
                                _packageHasAbandoned(p) &&
                                (p.srNumber.toLowerCase().contains(query) ||
                                    p.consigneeName
                                        .toLowerCase()
                                        .contains(query)));
                          },
                          onSelected: (package) {
                            setState(() {
                              _tableSearchCtrl.text = package.srNumber;
                              ref
                                  .read(abandonedPackageSearchProvider.notifier)
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
                                          child: Row(
                                            children: [
                                              Text(option.srNumber,
                                                  style: TextStyle(
                                                      color: context.colors
                                                          .accentLightBlue,
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
                                                      overflow: TextOverflow
                                                          .ellipsis)),
                                              StatusChip(status: option.status),
                                            ],
                                          ),
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
                                hintText: 'Search SR #, consignee or item...',
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
                                                  abandonedPackageSearchProvider
                                                      .notifier)
                                              .state = '';
                                        },
                                      )
                                    : null,
                                isDense: true,
                              ),
                              onChanged: (v) {
                                _tableSearchCtrl.text = v;
                                ref
                                    .read(
                                        abandonedPackageSearchProvider.notifier)
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
                        DateFilterButton(
                          dateRange: dateRange,
                          year: _yearFilter,
                          years: srYears(ref
                                  .watch(heldGoodsYearsProvider('ABANDONED'))
                                  .valueOrNull ??
                              const <String>[]),
                          onChanged: (range, year) {
                            ref
                                .read(
                                    abandonedPackageDateRangeProvider.notifier)
                                .state = range;
                            setState(() {
                              _yearFilter = year;
                              _page = 0;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        
                        StyledDropdownButton<String>(
                          value: rFilter == 'all' ? null : rFilter,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // Abandoned goods only ever carry a DISPOSAL
                          // activity (the SR form offers no other kind for
                          // this status), so listing the detain ones would
                          // only offer filters that can never match.
                          options: kDisposalActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => ref
                              .read(
                                  abandonedPackageReasonFilterProvider.notifier)
                              .state = v ?? 'all',
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
                    // Filtered, sorted and paged by the database.
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
                              message: 'No abandoned packages found'),
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
                                label: Text('Abandoned Date'),
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
                          rows: rows
                              .map((row) => DataRow(cells: [
                                    DataCell(TooltipText(row.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(TooltipText(
                                        (row.item.hsCode != null &&
                                                row.item.hsCode!.isNotEmpty)
                                            ? row.item.hsCode!
                                            : '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12))),
                                    DataCell(Center(child: Text('${row.qty}'))),
                                    DataCell(_PostStatusActivityChip(
                                        label: row.reason)),
                                    DataCell(TooltipText(row.date != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.date!)
                                        : '—')),
                                    DataCell(TooltipText(
                                        row.package.consigneeName.isNotEmpty
                                            ? row.package.consigneeName
                                            : '—',
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: AppealStateChip(
                                            entryDate: row.package.entryDate ??
                                                row.package.createdAt,
                                            outcome:
                                                appealOutcomes[row.item.id]))),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showAppDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.item.id,
                                            useLegacySummary: true,
                                            // When the Appeal Directorate
                                            // has ruled, banner the ruling and
                                            // enable ONLY that action — the
                                            // yard carries out what was
                                            // decided, it does not choose
                                            // afresh.
                                            appealDecisionLabel:
                                                appealOutcomes[row.item.id]
                                                    ?.label,
                                            appealDecisionCode: (appealOutcomes[
                                                            row.item.id]
                                                        ?.isDecided ??
                                                    false)
                                                ? appealOutcomes[row.item.id]!
                                                    .decision
                                                : null,
                                            // ⚠️ NOT unconditionally true. The
                                            // comment here used to claim every
                                            // row in this table is actionable,
                                            // but the table paints an
                                            // AppealStateChip above — so a row
                                            // CAN still be inside its 30-day
                                            // window, and that combination gave
                                            // an enabled Final Disposition
                                            // button beside an "Appealing · 12d"
                                            // chip. Same gate as the chip.
                                            forceFinalDisposition:
                                                canActOnHeldGoods(
                                                    entryDate: row.package
                                                            .entryDate ??
                                                        row.package.createdAt,
                                                    outcome: appealOutcomes[
                                                        row.item.id]),
                                            allowFinalDisposition:
                                                canActOnHeldGoods(
                                                    entryDate: row.package
                                                            .entryDate ??
                                                        row.package.createdAt,
                                                    outcome: appealOutcomes[
                                                        row.item.id]),
                                            onSaleOrDestroyRequest:
                                                !canActOnHeldGoods(
                                                        entryDate: row.package
                                                                .entryDate ??
                                                            row.package
                                                                .createdAt,
                                                        outcome: appealOutcomes[
                                                            row.item.id])
                                                    ? null
                                                    : (disposition) =>
                                                        _requestSingleDisposal(
                                                            row.package,
                                                            row.item,
                                                            disposition,
                                                            entry: row.entry),
                                          ),
                                        );
                                      },
                                    ))),
                                  ]))
                              .toList(),
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
}

class _AbandonedStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AbandonedStatChip(
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

class _AbandonedRow {
  final PackageModel package;
  final PackageItem item;
  final WarehouseEntryModel? entry; // null only if no warehouse entry exists
  final int qty;
  final DateTime? date;
  final String reason;
  final String officer;

  const _AbandonedRow({
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
