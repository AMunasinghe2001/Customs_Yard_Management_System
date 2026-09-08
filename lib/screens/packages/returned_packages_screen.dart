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
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/destruction_status_pill.dart';
import '../../widgets/handover_cell.dart';

final returnedPackageSearchProvider = StateProvider<String>((ref) => '');
final returnedPackageReasonFilterProvider =
    StateProvider<String>((ref) => 'all');
final returnedPackageDateRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

class ReturnedPackagesScreen extends ConsumerStatefulWidget {
  const ReturnedPackagesScreen({super.key});
  @override
  ConsumerState<ReturnedPackagesScreen> createState() =>
      _ReturnedPackagesScreenState();
}

class _ReturnedPackagesScreenState
    extends ConsumerState<ReturnedPackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  String? _yearFilter;
  int _page = 0; // current client-side page of the filtered rows

  // ⚠️ `_latestReturnedEntry`, `_isReleaseEntry`, `_returnedItemName` and
  // `_extractReceiptNo` all moved into the `disposition_rows` view (source 4,
  // postgres/21, plus the receipt split in 22). They are not gone — they are
  // in SQL, because paging in SQL needs the rows to exist in SQL.
  //
  // The release rule in particular is worth finding there: a release is the
  // one disposition with NO tag, so it matches the ABSENCE of a bracket,
  // which the other three sources' tag list cannot express.

  /// The view's rows, as this page's widgets already expect them.
  ///
  /// Only rehydrates the twenty rows that came back — which rows count as a
  /// release, in what order, and which page are all the view's job now.
  List<_ReturnedRow> _rowsFrom(DispositionPageWithPackages result) {
    final out = <_ReturnedRow>[];
    for (final r in result.rows) {
      final pkg = result.packages[r.packageId];
      if (pkg == null) continue;
      final entry =
          pkg.warehouseEntries.where((e) => e.id == r.entryId).firstOrNull;
      // Every released row comes from an entry; one that cannot be resolved
      // was deleted between the two queries.
      if (entry == null) continue;
      out.add(_ReturnedRow(
        package: pkg,
        entry: entry,
        itemName: r.itemName,
        // Parsed by the view now, so the search box can match it in SQL.
        receiptNo: r.receiptNo,
        receiptDate: _extractReceiptDate(entry.returnNotes),
        delivered: r.delivered,
        deliveredAt: r.deliveredAt,
      ));
    }
    return out;
  }

  String? _extractReceiptDate(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    for (final part in notes.split('|')) {
      final text = part.trim();
      if (text.toLowerCase().startsWith('date:')) {
        final idx = text.indexOf(':');
        if (idx != -1) return text.substring(idx + 1).trim();
      }
    }
    return null;
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
    _tableSearchCtrl.text = ref.read(returnedPackageSearchProvider);
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  void _resetPage() {
    if (_page == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _page = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final search = ref.watch(returnedPackageSearchProvider);
    final dateRange = ref.watch(returnedPackageDateRangeProvider);
    final rFilter = ref.watch(returnedPackageReasonFilterProvider);

    // ⚠️ Everything this page filters on goes into the key, so every filter
    // is applied in SQL. A RELEASE is the disposition with NO tag -- see the
    // view's fourth source -- which is why it has a final_tag of its own
    // rather than being matched from the tag list.
    final query = DispositionQuery(
      finalTag: 'RELEASED',
      page: _page,
      search: search,
      dateStart: dateRange?.start,
      dateEnd: dateRange?.end,
      year: _yearFilter,
      holdReason: rFilter,
    );
    final page = ref.watch(dispositionPageWithPackagesProvider(query));

    // Any filter change jumps back to the first page.
    ref.listen(returnedPackageSearchProvider, (_, __) => _resetPage());
    ref.listen(returnedPackageDateRangeProvider, (_, __) => _resetPage());
    ref.listen(returnedPackageReasonFilterProvider, (_, __) => _resetPage());

    return AppShell(
      currentRoute: '/returned-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
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
                        Text('Released Goods',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(
                            'View and search all goods that have been released',
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The count the DATABASE reports for this filter.
                        page.when(
                          data: (p) => Text('${p.total} Released',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                      ],
                    ),
                  ],
                ),
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
                                p.isReturned &&
                                (p.srNumber.toLowerCase().contains(query) ||
                                    p.consigneeName
                                        .toLowerCase()
                                        .contains(query)));
                          },
                          onSelected: (package) {
                            setState(() {
                              _tableSearchCtrl.text = package.srNumber;
                              ref
                                  .read(returnedPackageSearchProvider.notifier)
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
                            // Sync external controller if needed
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
                                hintText:
                                    'Search SR #, consignee or declarant...',
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
                                                  returnedPackageSearchProvider
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
                                        returnedPackageSearchProvider.notifier)
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
                            final picked = await showDialog<dynamic>(
                              context: context,
                              builder: (context) =>
                                  custom.DateRangePickerDialog(
                                      initialRange: dateRange),
                            );
                            if (picked is DateTimeRange) {
                              ref
                                  .read(
                                      returnedPackageDateRangeProvider.notifier)
                                  .state = picked;
                            } else if (picked == false) {
                              ref
                                  .read(
                                      returnedPackageDateRangeProvider.notifier)
                                  .state = null;
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            dateRange != null
                                ? '${DateFormat('MMM d').format(dateRange.start)} - ${DateFormat('MMM d').format(dateRange.end)}'
                                : 'Date Range',
                            style: TextStyle(
                                color: dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.textSecondary,
                                fontSize: 12,
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
                            onPressed: () => ref
                                .read(returnedPackageDateRangeProvider.notifier)
                                .state = null,
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        StyledDropdownButton<String>(
                          value: rFilter == 'all' ? null : rFilter,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // Goods reach this page from any status, so every
                          // activity is reachable here.
                          options: kAllPostStatusActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => ref
                              .read(
                                  returnedPackageReasonFilterProvider.notifier)
                              .state = v ?? 'all',
                        ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          // ⚠️ Its own query: the page holds twenty rows,
                          // which would offer only the years visible now.
                          years: srYears(ref
                                  .watch(
                                      dispositionYearSourceProvider('RELEASED'))
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
                child: page.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref
                          .refresh(dispositionPageWithPackagesProvider(query))),
                  data: (result) {
                    // Already filtered, sorted and paged by the database --
                    // including the Reason dropdown and the receipt-number
                    // search, which are why this page needed two columns on
                    // the view that no other page uses.
                    final pageRows = _rowsFrom(result);
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                                color: context.colors.cardDark,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: context.colors.borderColor)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DataTable2(
                                columnSpacing: 12,
                                horizontalMargin: 12,
                                fixedTopRows: 1,
                                empty: const EmptyTableState(
                                    message: 'No released packages found'),
                                isVerticalScrollBarVisible: true,
                                isHorizontalScrollBarVisible: false,
                                columns: const [
                                  DataColumn2(
                                      label: Text('SR Number'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Goods Name'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('HS Code'),
                                      size: ColumnSize.S,
                                      fixedWidth: 110),
                                  DataColumn2(
                                      label: Text('Released Qty'),
                                      size: ColumnSize.S,
                                      fixedWidth: 110),
                                  DataColumn2(
                                      label: Text('Entry Date'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Release Date'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Warehouse Charge'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Receipt No'),
                                      size: ColumnSize.M),
                                  // ⚠️ The COLLECTION, which is not the
                                  // release. The receipt above says an
                                  // officer ruled the goods released; this
                                  // says whether the owner has come for
                                  // them. Same width as every other
                                  // delivery column, because it holds the
                                  // same fixed-size pill.
                                  DataColumn2(
                                      label: Center(child: Text('Delivery')),
                                      fixedWidth:
                                          kDestructionStatusColumnWidth),
                                  DataColumn2(
                                      label: Center(child: Text('Details')),
                                      size: ColumnSize.S,
                                      fixedWidth: 55),
                                ],
                                rows: pageRows
                                    .map((row) => DataRow(cells: [
                                          DataCell(TooltipText(
                                              row.package.srNumber,
                                              style: TextStyle(
                                                  color: context
                                                      .colors.accentLightBlue,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                          DataCell(TooltipText(row.itemName,
                                              overflow: TextOverflow.ellipsis)),
                                          DataCell(TooltipText((() {
                                            final hs = row.package.items
                                                .where((i) =>
                                                    i.id ==
                                                    row.entry.packageItemId)
                                                .firstOrNull
                                                ?.hsCode;
                                            return (hs != null && hs.isNotEmpty)
                                                ? hs
                                                : '—';
                                          })(),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12))),
                                          DataCell(Center(
                                              child: Text(
                                                  '${row.entry.itemCount}'))),
                                          // Entry Date (SR form) — falls back to the
                                          // warehouse admit date.
                                          DataCell(TooltipText((() {
                                            final d = row.package.entryDate ??
                                                row.entry.admittedAt;
                                            return DateFormat('yyyy-MM-dd')
                                                .format(d);
                                          })())),
                                          // Release Date = the entry's returned date.
                                          DataCell(TooltipText(row
                                                      .entry.returnedAt !=
                                                  null
                                              ? DateFormat('yyyy-MM-dd')
                                                  .format(row.entry.returnedAt!)
                                              : '—')),
                                          // Warehouse charge from the SR Entry Date →
                                          // Release Date (not the warehouse admit date).
                                          DataCell(TooltipText((() {
                                            final e = row.entry;
                                            final chargeStart =
                                                row.package.entryDate ??
                                                    e.admittedAt;
                                            final tempEntry =
                                                WarehouseEntryModel(
                                              id: e.id,
                                              packageId: e.packageId,
                                              packageItemId: e.packageItemId,
                                              warehouseId: e.warehouseId,
                                              warehouseName: e.warehouseName,
                                              warehouseCode: e.warehouseCode,
                                              holdReason: e.holdReason,
                                              itemCount: e.itemCount,
                                              admittedAt: chargeStart,
                                              dailyRate: e.dailyRate,
                                              returnedAt: e.returnedAt,
                                            );
                                            return 'LKR ${NumberFormat('#,##0.00').format(tempEntry.calculatePackageCharge(row.package.items, storageRateHistory))}';
                                          })(),
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                          DataCell(TooltipText(
                                              row.receiptNo ?? '—',
                                              overflow: TextOverflow.ellipsis)),
                                          DataCell(Center(
                                            child: HandoverCell(
                                              entry: row.entry,
                                              delivered: row.delivered,
                                              kind: HandoverEntryKind.released,
                                              // ⚠️ The package and the
                                              // rate history, so the button
                                              // can price the storage the
                                              // owner owes before the goods
                                              // leave. Without them it
                                              // falls back to a bare flag
                                              // and the charge on this very
                                              // row goes uncollected.
                                              package: row.package,
                                              rates: storageRateHistory,
                                            ),
                                          )),
                                          DataCell(Center(
                                              child: IconButton(
                                            icon: Icon(
                                                Icons.info_outline_rounded,
                                                color: context
                                                    .colors.accentLightBlue,
                                                size: 18),
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) =>
                                                    PackageDetailsDialog(
                                                  package: row.package,
                                                  storageRate:
                                                      storageRateHistory,
                                                  highlightEntry: row.entry,
                                                  useLegacySummary: true,
                                                  // ⚠️ The same section
                                                  // Re-exported Goods
                                                  // carries. Both endings
                                                  // are ruled once and
                                                  // handed over later, and
                                                  // an officer reading one
                                                  // popup should not have
                                                  // to learn a second
                                                  // layout for the same
                                                  // fact.
                                                  handover: HandoverOutcome(
                                                    kind:
                                                        HandoverKind.released,
                                                    decidedAt:
                                                        row.entry.returnedAt,
                                                    delivered:
                                                        row.delivered ?? false,
                                                    deliveredAt:
                                                        row.deliveredAt,
                                                  ),
                                                ),
                                              );
                                            },
                                          ))),
                                        ]))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                        TablePager(
                          // The database's count for this filter.
                          total: result.total,
                          page: _page.clamp(0, maxPage),
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

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
          const Gap(4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ReturnedRow {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final String itemName;
  final String? receiptNo;
  final String? receiptDate;

  /// Has the owner actually collected the goods?
  ///
  /// ⚠️ A release is two events wearing one date: an officer RULES it,
  /// writing the receipt, and the owner COMES FOR THEM later. This page
  /// showed only the first, so all 33 rows looked finished while the yard
  /// could still be storing every one of them.
  final bool? delivered;
  final DateTime? deliveredAt;

  const _ReturnedRow({
    required this.package,
    required this.entry,
    required this.itemName,
    this.receiptNo,
    this.receiptDate,
    this.delivered,
    this.deliveredAt,
  });
}
