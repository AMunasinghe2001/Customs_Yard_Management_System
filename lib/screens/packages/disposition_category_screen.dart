import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import 'package:data_table_2/data_table_2.dart';

/// Generic screen for a final-disposition category (Sold / Destroyed /
/// Re-exported / Other). Reads warehouse entries tagged "[FINAL:<TAG>]".
class DispositionCategoryScreen extends ConsumerStatefulWidget {
  final String route;
  final String title;
  final String subtitle;
  final String countLabel;
  final String finalTag; // e.g. SOLD, DESTROYED, RE-EXPORTED, OTHER

  const DispositionCategoryScreen({
    super.key,
    required this.route,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.finalTag,
  });

  @override
  ConsumerState<DispositionCategoryScreen> createState() =>
      _DispositionCategoryScreenState();
}

class _DispositionCategoryScreenState
    extends ConsumerState<DispositionCategoryScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTimeRange? _dateRange;
  String? _yearFilter;
  int _page = 0;
  // Delivery sub-filter (Sold / Destroyed pages): null = all, true = delivered,
  // false = pending.
  bool? _deliveryFilter;

  bool get _hasDelivery =>
      widget.finalTag == 'SOLD' || widget.finalTag == 'DESTROYED';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // A disposition can be recorded two ways, each tagging return_notes
  // differently:
  //   • recordFinalDisposition → "[FINAL:RE-EXPORTED]" / "[FINAL:DESTROYED]" …
  //   • disposeWarehouseItem    → "[RE-EXPORT]" / "[DESTROY]" …  (present tense)
  // Both must surface in the matching category table. This maps each category's
  // finalTag to every bracket tag that belongs to it.
  static const Map<String, Set<String>> _acceptedTags = {
    'RE-EXPORTED': {'FINAL:RE-EXPORTED', 'RE-EXPORTED', 'RE-EXPORT'},
    'DESTROYED': {'FINAL:DESTROYED', 'DESTROYED', 'DESTROY'},
    'SOLD': {'FINAL:SOLD', 'SOLD'},
    'OTHER': {'FINAL:OTHER', 'OTHER'},
  };

  bool _matchesTag(WarehouseEntryModel e) {
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    final m = RegExp(r'^\[([^\]]+)\]').firstMatch(notes);
    if (m == null) return false;
    final tag = m.group(1)!.trim();
    final accepted =
        _acceptedTags[widget.finalTag] ?? {'FINAL:${widget.finalTag}'};
    return accepted.contains(tag);
  }

  String _extractNote(String? returnNotes) {
    if (returnNotes == null) return '';
    final idx = returnNotes.indexOf('—');
    if (idx == -1) return '';
    return returnNotes.substring(idx + 1).trim();
  }

  // Maps finalTag → the item statuses that correspond to it.
  static const Map<String, Set<String>> _statusForTag = {
    'RE-EXPORTED': {'re-exported'},
    'DESTROYED': {'destroyed'},
    'SOLD': {'sold'},
    'OTHER': {'other'},
  };

  List<_CategoryRow> _buildRows(List<PackageModel> packages) {
    final rows = <_CategoryRow>[];
    for (final package in packages) {
      // Track which items already have a tagged warehouse entry row so we
      // don't double-count them in the status fallback pass below.
      final coveredItemIds = <String>{};

      for (final entry in package.warehouseEntries) {
        if (!_matchesTag(entry)) continue;
        final item = package.items
            .where((i) => i.id == entry.packageItemId)
            .firstOrNull;
        if (entry.packageItemId != null) coveredItemIds.add(entry.packageItemId!);
        rows.add(_CategoryRow(
          package: package,
          entry: entry,
          itemName: item?.itemName ??
              (package.items.isNotEmpty
                  ? package.items.first.itemName
                  : '—'),
          note: _extractNote(entry.returnNotes),
          officer: entry.returnedByName ?? entry.returnedByBadge ?? '—',
        ));
      }

      // Fallback: items whose status matches this category but have no
      // tagged warehouse entry (e.g. items that were never warehouse-admitted
      // and whose Final Disposition was recorded via status-only update).
      final matchingStatuses = _statusForTag[widget.finalTag] ?? {};
      for (final item in package.items) {
        if (coveredItemIds.contains(item.id)) continue;
        if (!matchingStatuses.contains(item.status?.toLowerCase())) continue;
        rows.add(_CategoryRow(
          package: package,
          entry: null,
          item: item,
          itemName: item.itemName,
          note: '',
          officer: '—',
        ));
      }
    }
    rows.sort((a, b) {
      final aDate = a.entry?.returnedAt ?? a.entry?.admittedAt ?? a.package.updatedAt;
      final bDate = b.entry?.returnedAt ?? b.entry?.admittedAt ?? b.package.updatedAt;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  /// A compact pill for the Delivered / Pending / All delivery sub-filter,
  /// styled like the date/year filter chips beside it.
  Widget _deliveryFilterChip(String label, bool? value, IconData icon) {
    final selected = _deliveryFilter == value;
    final color = context.colors.primaryGold;
    return OutlinedButton.icon(
      onPressed: () => setState(() {
        _deliveryFilter = value;
        _page = 0;
      }),
      icon: Icon(icon,
          size: 16, color: selected ? color : context.colors.textSecondary),
      label: Text(label,
          style: TextStyle(
              color: selected ? color : context.colors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: selected ? color : context.colors.borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(livePackagesProvider);
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    // Delivery map for filtering (Sold uses tender-sale items; Destroyed uses
    // destruction items). Empty until loaded — rows then treated as Pending.
    final deliveredMap = !_hasDelivery
        ? const <String, bool>{}
        : (widget.finalTag == 'SOLD'
                ? ref.watch(packageDeliveredMapProvider)
                : ref.watch(packageDestroyedDeliveredMapProvider))
            .valueOrNull ??
            const <String, bool>{};

    return AppShell(
      currentRoute: widget.route,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                            style: TextStyle(
                                color: context.colors.textSecondary)),
                      ],
                    ),
                    packages.when(
                      data: (list) {
                        final count = _buildRows(list).length;
                        return Text('$count ${widget.countLabel}',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.bold));
                      },
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // Search + date range
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
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDialog<dynamic>(
                              context: context,
                              builder: (context) =>
                                  custom.DateRangePickerDialog(
                                      initialRange: _dateRange),
                            );
                            if (picked is DateTimeRange) {
                              setState(() {
                                _dateRange = picked;
                                _page = 0;
                              });
                            } else if (picked == false) {
                              setState(() {
                                _dateRange = null;
                                _page = 0;
                              });
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: _dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            _dateRange != null
                                ? '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}'
                                : 'Date Range',
                            style: TextStyle(
                                color: _dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.textSecondary,
                                fontSize: 12,
                                fontWeight: _dateRange != null
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: _dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.borderColor),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (_dateRange != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.dangerRed),
                            onPressed: () => setState(() {
                              _dateRange = null;
                              _page = 0;
                            }),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        YearFilterButton(
                          value: _yearFilter,
                          years: srYears(packages.valueOrNull == null
                              ? const <String>[]
                              : _buildRows(packages.valueOrNull!)
                                  .map((r) => r.package.srNumber)),
                          onChanged: (v) => setState(() {
                            _yearFilter = v;
                            _page = 0;
                          }),
                        ),
                        // Delivery filter — Sold / Destroyed pages only.
                        if (_hasDelivery) ...[
                          _deliveryFilterChip('All', null, Icons.all_inbox_rounded),
                          _deliveryFilterChip(
                              'Delivered', true, Icons.check_circle_rounded),
                          _deliveryFilterChip(
                              'Pending', false, Icons.schedule_rounded),
                        ],
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
                      onRetry: () => ref.refresh(livePackagesProvider)),
                  data: (list) {
                    final rows = _buildRows(list).where((row) {
                      if (_search.isNotEmpty) {
                        final s = _search.toLowerCase();
                        if (!row.package.srNumber.toLowerCase().contains(s) &&
                            !row.package.consigneeName
                                .toLowerCase()
                                .contains(s) &&
                            !row.itemName.toLowerCase().contains(s)) {
                          return false;
                        }
                      }
                      if (_dateRange != null) {
                        final date = row.entry?.returnedAt ??
                            row.entry?.admittedAt ??
                            row.package.updatedAt;
                        final startOfDay = DateTime(_dateRange!.start.year,
                            _dateRange!.start.month, _dateRange!.start.day);
                        final endOfDay = DateTime(
                            _dateRange!.end.year,
                            _dateRange!.end.month,
                            _dateRange!.end.day,
                            23,
                            59,
                            59);
                        if (date.isBefore(startOfDay) ||
                            date.isAfter(endOfDay)) return false;
                      }
                      if (!srYearMatches(row.package.srNumber, _yearFilter)) {
                        return false;
                      }
                      if (_hasDelivery && _deliveryFilter != null) {
                        final delivered =
                            deliveredMap[row.package.id] ?? false;
                        if (delivered != _deliveryFilter) return false;
                      }
                      return true;
                    }).toList();

                    // Client-side paging over the filtered rows.
                    final maxPage =
                        rows.isEmpty ? 0 : (rows.length - 1) ~/ kClientPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }
                    final pageRows = pageSlice(rows, _page.clamp(0, maxPage));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          empty: EmptyTableState(
                              message:
                                  'No ${widget.countLabel.toLowerCase()} packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                          columns: [
                            const DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            const DataColumn2(
                                label: Text('Item Name'), size: ColumnSize.M),
                            const DataColumn2(
                                label: Text('HS Code'),
                                size: ColumnSize.S,
                                fixedWidth: 110),
                            const DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            const DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            const DataColumn2(
                                label: Text('Officer'), size: ColumnSize.M),
                            const DataColumn2(
                                label: Text('Notes'), size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              const DataColumn2(
                                  label: Text('Financials'),
                                  size: ColumnSize.M),
                            if (_hasDelivery)
                              const DataColumn2(
                                  label: Text('Delivery'), fixedWidth: 120),
                            const DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: pageRows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(row.package.srNumber,
                                        style: TextStyle(
                                            color: context
                                                .colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text((() {
                                      final itemId = row.entry?.packageItemId ??
                                          row.item?.id;
                                      final hs = row.package.items
                                          .where((i) => i.id == itemId)
                                          .firstOrNull
                                          ?.hsCode;
                                      return (hs != null && hs.isNotEmpty)
                                          ? hs
                                          : '—';
                                    })(),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(
                                        '${row.entry?.itemCount ?? row.item?.quantity ?? 0}')),
                                    DataCell(Text(row.entry?.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.entry!.returnedAt!)
                                        : '—')),
                                    DataCell(Text(row.officer,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text(
                                        row.note.isEmpty ? '—' : row.note,
                                        overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_SaleFinancialsCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                      )),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_DeliveryStatusCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                      )),
                                    if (widget.finalTag == 'DESTROYED')
                                      DataCell(_DestroyedDeliveryStatusCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                      )),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color:
                                              context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) =>
                                              PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.entry?.packageItemId ?? row.item?.id,
                                            useLegacySummary: true,
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
                          total: rows.length,
                          page: _page.clamp(0, maxPage),
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

class _CategoryRow {
  final PackageModel package;
  final WarehouseEntryModel? entry;
  final String itemName;
  final String note;
  final String officer;
  // For status-only rows (no warehouse entry): the package item itself.
  final PackageItem? item;

  const _CategoryRow({
    required this.package,
    this.entry,
    required this.itemName,
    required this.note,
    required this.officer,
    this.item,
  });
}

// Read-only delivery STATUS chip (the action button is in the details dialog,
// enabled for yards). Uses per-item provider so each row shows its own status.
class _DeliveryStatusCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  const _DeliveryStatusCell({required this.package, this.packageItemId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) => item == null
          ? const Text('—')
          : _DeliveryStatusChip(delivered: item.isDelivered),
    );
  }
}

// Read-only delivery STATUS chip for a DESTROYED package (mirrors
// _DeliveryStatusCell but reads the destruction item).
class _DestroyedDeliveryStatusCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  const _DestroyedDeliveryStatusCell(
      {required this.package, this.packageItemId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}';
    final async = ref.watch(destructionItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) =>
          _DeliveryStatusChip(delivered: item?.delivered ?? false),
    );
  }
}

class _DeliveryStatusChip extends StatelessWidget {
  final bool delivered;
  const _DeliveryStatusChip({required this.delivered});
  @override
  Widget build(BuildContext context) {
    final color =
        delivered ? context.colors.successGreen : context.colors.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delivered ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 13, color: color),
        const SizedBox(width: 5),
        Text(delivered ? 'Delivered' : 'Pending',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Read-only sold price + tax total for a sold package. Uses per-item provider.
class _SaleFinancialsCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  const _SaleFinancialsCell({required this.package, this.packageItemId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += (t['amount'] as num?)?.toDouble() ?? 0;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${item.soldPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Tax: Rs ${taxSum.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}
