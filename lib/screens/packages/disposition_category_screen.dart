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
import '../../services/services.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/destruction_status_pill.dart';

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
    // ⚠️ 'FINAL:DESTROY' (no ED) is the PENDING tag disposeWarehouseItem
    // writes -- it upper-cases the action name, and the action is
    // "Destroy". Without it here a package marked for destruction never
    // reached this page at all, so it could never be confirmed.
    'DESTROYED': {
      'FINAL:DESTROYED',
      'FINAL:DESTROY',
      'DESTROYED',
      'DESTROY',
      'SUPPOSED TO BE DESTROYED'
    },
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
    'DESTROYED': {'destroyed', 'supposed to be destroyed', 'destroy'},
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
                              widget.finalTag == 'DESTROYED'
                                  ? 'Destroyed'
                                  : 'Delivered',
                              true,
                              Icons.check_circle_rounded),
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
                        if (widget.finalTag == 'DESTROYED') {
                          if (row.isDestroyed != _deliveryFilter) return false;
                        } else {
                          // Match the per-SALE delivery state (receipt-pinned),
                          // falling back to the per-item / package-level value.
                          final itemId = row.entry?.packageItemId ?? '';
                          final receipt =
                              _parseSaleReceipt(row.entry?.returnNotes) ?? '';
                          final delivered = deliveredMap[
                                  '${row.package.id}|$itemId|$receipt'] ??
                              deliveredMap['${row.package.id}|$itemId'] ??
                              deliveredMap[row.package.id] ??
                              false;
                          if (delivered != _deliveryFilter) return false;
                        }
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
                                label: Text('Goods Name'), size: ColumnSize.M),
                            if (widget.finalTag != 'DESTROYED')
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
                            if (widget.finalTag != 'SOLD' &&
                                widget.finalTag != 'DESTROYED')
                              const DataColumn2(
                                  label: Text('Officer'), size: ColumnSize.M),
                            // Destroyed rows carry no receipt and no useful
                            // note -- the column only ever printed the DSR
                            // number already shown elsewhere, so it is dropped
                            // there to match Central Disposal's own table.
                            if (widget.finalTag != 'DESTROYED')
                              DataColumn2(
                                  label: Text(widget.finalTag == 'SOLD'
                                      ? 'Receipt No'
                                      : 'Notes'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              const DataColumn2(
                                  label: Text('Valuation'), size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              DataColumn2(
                                  label: Text('Sold Price'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              // Same width as the Destroyed Goods status
                              // column: both hold the same fixed-size pill, so
                              // a narrower box here would clip it.
                              const DataColumn2(
                                  label: Center(child: Text('Delivery')),
                                  fixedWidth: kDestructionStatusColumnWidth),
                            // What the destruction actually cost -- the same
                            // SR-level figure Central Disposal's own Destroyed
                            // Goods table shows, so the yard can see the spend
                            // without opening the popup.
                            if (widget.finalTag == 'DESTROYED')
                              const DataColumn2(
                                  label: Text('Destruction Expenses'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'DESTROYED')
                              const DataColumn2(
                                  label: Center(child: Text('Status')),
                                  fixedWidth: kDestructionStatusColumnWidth),
                            const DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: pageRows
                              .map((row) => DataRow(cells: [
                                    DataCell(TooltipText(row.package.srNumber,
                                        style: TextStyle(
                                            color: context
                                                .colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag != 'DESTROYED')
                                      DataCell(TooltipText((() {
                                        final itemId =
                                            row.entry?.packageItemId ??
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
                                    DataCell(TooltipText(
                                        '${row.entry?.itemCount ?? row.item?.quantity ?? 0}')),
                                    DataCell(TooltipText(row.entry?.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.entry!.returnedAt!)
                                        : '—')),
                                    if (widget.finalTag != 'SOLD' &&
                                        widget.finalTag != 'DESTROYED')
                                      DataCell(TooltipText(row.officer,
                                          overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag != 'DESTROYED')
                                      DataCell(TooltipText(
                                          (() {
                                            if (widget.finalTag == 'SOLD') {
                                              return _parseSaleReceipt(
                                                      row.entry?.returnNotes) ??
                                                  '—';
                                            }
                                            return row.note.isEmpty
                                                ? '—'
                                                : row.note;
                                          })(),
                                          overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_SaleValuationCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                        qty: row.entry?.itemCount ??
                                            row.item?.quantity,
                                      )),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_SaleFinancialsCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                      )),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(Center(child: _DeliveryStatusCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                      ))),
                                    if (widget.finalTag == 'DESTROYED')
                                      DataCell(DestructionExpenseCell(
                                          srNumber: row.package.srNumber)),
                                    if (widget.finalTag == 'DESTROYED')
                                      DataCell(Center(
                                        child: DestructionStatusPill(
                                          destroyed: row.isDestroyed,
                                          onMark: row.isDestroyed
                                              ? null
                                              : () => _confirmMarkDestroyed(
                                                  context, ref, row),
                                        ),
                                      )),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color:
                                              context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        // The forfeited row behind this sale,
                                        // so the popup can show the same
                                        // per-round Tender History the Unsold
                                        // page shows. A sold package may have
                                        // been re-valued several times before
                                        // it sold, and that chain was
                                        // invisible here.
                                        final saleItem = ref
                                            .read(saleItemForPackageItemProvider(
                                                '${row.package.id}|'
                                                '${row.entry?.packageItemId ?? row.item?.id ?? ''}'))
                                            .asData
                                            ?.value;
                                        showDialog(
                                          context: context,
                                          builder: (_) =>
                                              PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.entry?.packageItemId ?? row.item?.id,
                                            useLegacySummary: true,
                                            tenderHistoryFor:
                                                saleItem?.forfeited,
                                            // The SAME quantity the row's
                                            // Valuation cell uses. These rows
                                            // are built from warehouse
                                            // entries, where `item` is null —
                                            // so passing only item.quantity
                                            // sent null, and the history fell
                                            // back to a qty of 1 and printed
                                            // "@ 950 × 1" beside a table
                                            // reading "@ 665 × 150".
                                            valuationQty: row.entry?.itemCount ??
                                                row.item?.quantity,
                                            // Same figure the Central
                                            // Disposal Destroyed Goods popup
                                            // now carries -- without it the
                                            // yard's own popup showed "not
                                            // available" even once Central
                                            // Disposal had recorded the
                                            // destruction expenses.
                                            srFinancials: ref
                                                .watch(srFinancialsProvider)
                                                .valueOrNull
                                                ?.where((f) =>
                                                    f.srNumber.trim() ==
                                                    row.package.srNumber
                                                        .trim())
                                                .firstOrNull,
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

  bool get isDestroyed {
    final notes = (entry?.returnNotes ?? '').trim().toUpperCase();
    if (notes.startsWith('[FINAL:DESTROYED]') || notes.startsWith('[DESTROYED]')) return true;
    if (item?.status?.toLowerCase() == 'destroyed') return true;
    return false;
  }
}

// Read-only delivery STATUS chip (the action button is in the details dialog,
// enabled for yards). Uses per-item provider so each row shows its own status.
/// Delivery status for a SOLD item, and the action that changes it.
///
/// Confirming delivery is the yard's ONE routine action on a sold row, and it
/// was buried in the details popup: open the row, scroll, press, watch the
/// popup close. It belongs in the table, next to the status it changes.
///
/// ⚠️ There is no revert. Once delivered the chip is a plain label again --
/// goods that have left with their buyer cannot un-leave.
class _DeliveryStatusCell extends ConsumerStatefulWidget {
  final PackageModel package;
  final String? packageItemId;

  /// Pins the exact TSI row when an item was sold across several partial sales.
  final String? receipt;
  const _DeliveryStatusCell(
      {required this.package, this.packageItemId, this.receipt});

  @override
  ConsumerState<_DeliveryStatusCell> createState() =>
      _DeliveryStatusCellState();
}

class _DeliveryStatusCellState extends ConsumerState<_DeliveryStatusCell> {
  bool _saving = false;

  String get _key =>
      '${widget.package.id}|${widget.packageItemId ?? ''}|${widget.receipt ?? ''}';

  Future<void> _markDelivered(TenderSaleItemModel item) async {
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).toggleDeliveryStatus(item.id, true);
      // ⚠️ Invalidate the SHARED providers, not just this cell's. Central
      // Disposal's Sold table reads the same tender_sale_items row through
      // them, so refreshing only here would leave the two portals disagreeing
      // about whether the goods had been handed over.
      ref.invalidate(saleItemForPackageItemProvider(_key));
      ref.invalidate(saleItemForPackageProvider(widget.package.id));
      ref.read(tenderSaleItemsRefreshProvider.notifier).trigger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Marked as Delivered'),
          backgroundColor: context.colors.successGreen,
        ));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e, action: 'Confirming delivery');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(saleItemForPackageItemProvider(_key));
    // Only a yard confirms delivery; Central Disposal watches.
    final profile = ref.watch(currentProfileProvider);
    final canEdit = profile != null && !profile.isDisposal;

    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        // The SAME pill the Destroyed Goods column uses -- one fixed box for
        // all three states, so neither column jumps as a row changes state and
        // the two tables line up beside each other.
        return Tooltip(
          message: item.isDelivered
              ? 'The buyer has taken the goods'
              : (canEdit
                  ? 'Confirm the buyer has taken the goods'
                  : 'Awaiting the yard to confirm hand-over'),
          child: DeliveryStatusPill(
            delivered: item.isDelivered,
            busy: _saving,
            onMark: canEdit ? () => _markDelivered(item) : null,
          ),
        );
      },
    );
  }
}

// Read-only delivery STATUS chip for a DESTROYED package (mirrors
// _DeliveryStatusCell but reads the destruction item).
/// The Valuation Directorate's valuation (unit cost × qty) for a SOLD item —
/// shown alongside the actual sold price so both figures can be compared.
class _SaleValuationCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  /// Pins the exact TSI row when an item was sold across several partial sales
  /// (same package_item_id, distinct qty/valuation per sale).
  final String? receipt;
  /// The quantity shown in the table's Qty column — the valuation must multiply
  /// by exactly this so "@ unit × qty" stays consistent with what the row shows.
  final int? qty;
  const _SaleValuationCell(
      {required this.package, this.packageItemId, this.receipt, this.qty});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}|${receipt ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Text('—', style: TextStyle(color: context.colors.textMuted)),
      data: (item) {
        final fp = item?.forfeited;
        if (fp == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        // Prefer the LATEST tender re-valuation, exactly as Central Disposal
        // does. Without this the yard showed the ORIGINAL valuation for a
        // package that had since been re-valued, so the two screens disagreed
        // about the same goods.
        final revals =
            ref.watch(tenderRevaluationsProvider(fp.id)).asData?.value ??
                const <String, TenderRevaluationModel>{};
        // Warm the rest of the details popup's Tender History while the table
        // is on screen. This cell already resolves the forfeited package for
        // every visible row, so the two remaining reads cost nothing here and
        // the section is ready the moment the popup opens instead of fetching
        // on click. (Central Disposal never needed this — its Tender Sales tab
        // had already cached the data.)
        ref.watch(tenderRoundsForPackageProvider(fp.id));
        ref.watch(tenderBidsProvider(fp.id));
        TenderRevaluationModel? latest;
        for (final r in revals.values) {
          if (latest == null || r.createdAt.isAfter(latest.createdAt)) {
            latest = r;
          }
        }
        final isRevalued = latest != null;
        final unitCost = latest?.valuationCost ?? fp.valuationCost;
        if (unitCost == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        final int effQty;
        if (qty != null && qty! > 0) {
          effQty = qty!;
        } else if (fp.entryQty != null) {
          effQty = fp.entryQty!;
        } else if (fp.itemId != null) {
          effQty = fp.packageDetails?.items
                  .where((i) => i.id == fp.itemId)
                  .firstOrNull
                  ?.quantity ??
              1;
        } else {
          effQty = fp.packageDetails?.items
                  .fold<int>(0, (s, i) => s + i.quantity) ??
              1;
        }
        final total = unitCost * effQty;
        final fmt = NumberFormat('#,##0');
        // Blue + a price-change icon when the figure is a re-valuation, the
        // same signal Central Disposal uses.
        final priceColor = isRevalued
            ? context.colors.accentLightBlue
            : context.colors.primaryGold;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ⚠️ The amount must be allowed to SHRINK. With
            // MainAxisSize.min and an unconstrained Text, a large re-valued
            // figure ("Rs 22,768,380" plus the icon) is wider than the column
            // and Flutter paints its overflow stripes straight down the table
            // -- the vertical red bar seen on Sold Goods. Flexible + ellipsis
            // lets the number give way instead.
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('Rs ${fmt.format(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              if (isRevalued) ...[
                const SizedBox(width: 4),
                Icon(Icons.price_change_rounded,
                    size: 11, color: context.colors.accentLightBlue),
              ],
            ]),
            Text(
                '@ ${fmt.format(unitCost)} × $effQty'
                '${isRevalued ? ' · re-valued' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 10, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

Future<void> _confirmMarkDestroyed(
    BuildContext context, WidgetRef ref, _CategoryRow row) async {
  final itemId = row.entry?.packageItemId ?? row.item?.id;
  if (itemId == null) return;
  final qty = row.entry?.itemCount ?? row.item?.quantity ?? 1;
  DateTime pickedDate = DateTime.now();
  final notesCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) => StyledFormDialog(
        label: 'DESTROY GOODS',
        title: 'Mark as Destroyed',
        icon: Icons.local_fire_department_rounded,
        headerAccentColor: ctx.colors.dangerRed,
        width: 480,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.colors.dangerRed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Destruction'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StyledFormSection(
              title: 'Package Information',
              icon: Icons.inventory_2_rounded,
              children: [
                _DialogDetailRow(
                    label: 'SR Number', value: row.package.srNumber),
                _DialogDetailRow(label: 'Goods Name', value: row.itemName),
                _DialogDetailRow(label: 'Quantity', value: '$qty'),
              ],
            ),
            const Gap(14),
            StyledFormSection(
              title: 'Destruction Details',
              icon: Icons.edit_calendar_rounded,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_today_rounded,
                      color: ctx.colors.primaryGold, size: 20),
                  title: const Text('Destruction Date',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle:
                      Text(DateFormat('yyyy-MM-dd').format(pickedDate)),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: pickedDate,
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setDlgState(() => pickedDate = d);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
                const Gap(8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Remarks (Optional)',
                    hintText:
                        'Enter destruction certificate # or remarks...',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed == true) {
    try {
      await WarehouseService().recordFinalDisposition(
        packageItemId: itemId,
        dispositionType: 'DESTROYED',
        qty: qty,
        dispositionDate: pickedDate,
        notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
      );
      ref.invalidate(livePackagesProvider);
      ref.invalidate(disposalDestroyedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${row.itemName} marked as Destroyed.'),
            backgroundColor: context.colors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, e);
      }
    }
  }
}

class _DialogDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DialogDetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}


/// Parse the receipt number from a "[FINAL:SOLD] — Receipt: <no>" warehouse
/// note. Used to pin the exact TSI row for an item sold across several partial
/// tenders (same package_item_id, distinct prices/receipts).
String? _parseSaleReceipt(String? returnNotes) {
  if (returnNotes == null) return null;
  final m = RegExp(r'Receipt:\s*([^\|—]+)', caseSensitive: false)
      .firstMatch(returnNotes);
  return m?.group(1)?.trim();
}

/// Read-only sold price + tax total for a sold package. Uses per-item provider.
class _SaleFinancialsCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  /// Receipt of THIS sale — pins the exact TSI row when an item was sold across
  /// several partial tenders (same package_item_id, distinct prices).
  final String? receipt;
  const _SaleFinancialsCell(
      {required this.package, this.packageItemId, this.receipt});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key =
        '${package.id}|${packageItemId ?? ''}|${receipt ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += parseDbNum(t['amount']) ?? 0;
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
