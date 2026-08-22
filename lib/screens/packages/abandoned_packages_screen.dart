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
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../forfeited_packages/disposal_request_dialog.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/tooltip_text.dart';

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

/// True if the item has been moved on to a final disposition
/// (Released/Sold/Destroyed/Re-exported/Other) — it should no longer appear
/// in the Abandoned table.
bool _itemHasFinalDisposition(PackageModel p, String itemId) {
  return p.warehouseEntries.any((e) =>
      e.packageItemId == itemId &&
      (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
}

/// True if a package has any abandoned item — either a form-level abandoned
/// item, or a partial/full abandonment disposition event.
bool _packageHasAbandoned(PackageModel p) {
  for (final item in p.items) {
    final entries =
        p.warehouseEntries.where((e) => e.packageItemId == item.id);
    if (entries.any(_isAbandonedEntry)) return true;
    if (_statusIsAbandoned(item.status) &&
        !entries.any(_isAbandonedEntry)) {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  /// Builds one row per abandonment — broken down per package item.
  /// A single SR can appear on multiple lines: once per abandoned item, and
  /// once per separate abandonment event (e.g. detained → partly abandoned).
  /// [sentKeys] — "pkgId:itemId" keys for items already sent in a disposal
  /// request; those rows are hidden from the table.
  List<_AbandonedRow> _buildRows(List<PackageModel> packages,
      {Set<String> sentKeys = const {}}) {
    final rows = <_AbandonedRow>[];
    for (final package in packages) {
      for (final item in package.items) {
        // Skip items that have already moved to a final disposition.
        if (_itemHasFinalDisposition(package, item.id)) continue;
        // Skip items already sent in a disposal request.
        if (sentKeys.contains('${package.id}:${item.id}')) continue;

        final itemEntries = package.warehouseEntries
            .where((e) => e.packageItemId == item.id)
            .toList();

        // 1. Disposition abandonment events ([ABANDONED] in returnNotes) —
        //    each event is its own row (partial/full, repeatable per item).
        final abandonedEntries =
            itemEntries.where(_isAbandonedEntry).toList();
        for (final entry in abandonedEntries) {
          rows.add(_AbandonedRow(
            package: package,
            item: item,
            entry: entry,
            qty: entry.itemCount,
            date: entry.returnedAt ?? entry.admittedAt,
            reason: entry.holdReason,
            officer:
                entry.returnedByName ?? entry.returnedByBadge ?? '—',
          ));
        }

        // 2. Form-level abandonment (item.status == 'abandoned') with no
        //    disposition event — use the held entry for context.
        if (_statusIsAbandoned(item.status) && abandonedEntries.isEmpty) {
          final ctx = itemEntries.isNotEmpty ? itemEntries.first : null;
          rows.add(_AbandonedRow(
            package: package,
            item: item,
            entry: ctx,
            qty: ctx?.itemCount ?? item.quantity,
            date: ctx?.admittedAt,
            reason: ctx?.holdReason ??
                (item.reasons?.isNotEmpty == true
                    ? item.reasons!
                    : '—'),
            officer: ctx?.admittedByName ?? '—',
          ));
        }
      }
    }
    rows.sort((a, b) {
      final aDate = a.date ?? DateTime(2000);
      final bDate = b.date ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableSearchCtrl.text = ref.read(abandonedPackageSearchProvider);
    });
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(livePackagesProvider);
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final search = ref.watch(abandonedPackageSearchProvider);
    final sentKeys =
        ref.watch(sentAbandonedOtherFpKeysProvider).valueOrNull ?? {};
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
                        Text('Abandoned Goods',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(
                          'Manage abandoned goods and send them for disposal',
                          style: TextStyle(
                              color: context.colors.textSecondary)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final pkgs = ref.watch(livePackagesProvider);
                            final sk = ref
                                    .watch(sentAbandonedOtherFpKeysProvider)
                                    .valueOrNull ??
                                {};
                            return pkgs.when(
                              data: (list) => _AbandonedStatChip(
                                  label: 'Abandoned',
                                  value:
                                      '${_buildRows(list, sentKeys: sk).length}',
                                  color: context.colors.accentLightBlue),
                              loading: () => const SizedBox(),
                              error: (_, __) => const SizedBox(),
                            );
                          },
                        ),
                        const Gap(8),
                        // Requestable count = abandoned packages not yet sent in
                        // a disposal request (surfaced by the shared provider).
                        Consumer(
                          builder: (context, ref, child) {
                            final req =
                                ref.watch(requestableForfeitedPackagesProvider);
                            final n = req.maybeWhen(
                                data: (list) => list
                                    .where((p) => p.isAbandonedSource)
                                    .length,
                                orElse: () => 0);
                            return _AbandonedStatChip(
                                label: 'Requestable',
                                value: '$n',
                                color: context.colors.primaryGold);
                          },
                        ),
                        const Gap(16),
                        Consumer(
                          builder: (context, ref, child) {
                            final req =
                                ref.watch(requestableForfeitedPackagesProvider);
                            final n = req.maybeWhen(
                                data: (list) => list
                                    .where((p) => p.isAbandonedSource)
                                    .length,
                                orElse: () => 0);
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.local_shipping_rounded,
                                  size: 16),
                              label: const Text('Send Disposal Request'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: n > 0
                                    ? context.colors.primaryGold
                                    : context.colors.textMuted.withOpacity(0.2),
                                foregroundColor: n > 0
                                    ? Colors.white
                                    : context.colors.textMuted,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                elevation: n > 0 ? 2 : 0,
                              ),
                              onPressed: n > 0
                                  ? () => showDialog(
                                        context: context,
                                        builder: (ctx) => DisposalRequestDialog(
                                          onSubmitted: () {
                                            ref.invalidate(
                                                requestableForfeitedPackagesProvider);
                                            ref.invalidate(livePackagesProvider);
                                          },
                                        ),
                                      )
                                  : null,
                            );
                          },
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
                                hintText:
                                    'Search SR #, consignee or item...',
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
                                  .read(abandonedPackageDateRangeProvider
                                      .notifier)
                                  .state = picked;
                            } else if (picked == false) {
                              ref
                                  .read(abandonedPackageDateRangeProvider
                                      .notifier)
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
                                .read(abandonedPackageDateRangeProvider
                                    .notifier)
                                .state = null,
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        StyledDropdownButton<String>(
                          value: rFilter == 'all' ? null : rFilter,
                          allLabel: 'All Activities',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          options: kAllPostStatusActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => ref
                              .read(abandonedPackageReasonFilterProvider
                                  .notifier)
                              .state = v ?? 'all',
                        ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          years: srYears(_buildRows(
                                  packages.valueOrNull ?? const <PackageModel>[],
                                  sentKeys: sentKeys)
                              .map((r) => r.package.srNumber)),
                          onChanged: (v) => setState(() => _yearFilter = v),
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
                      onRetry: () => ref.refresh(livePackagesProvider)),
                  data: (list) {
                    final rows =
                        _buildRows(list, sentKeys: sentKeys).where((row) {
                      if (search.isNotEmpty) {
                        final s = search.toLowerCase();
                        final itemName = row.itemName.toLowerCase();
                        if (!row.package.srNumber
                                .toLowerCase()
                                .contains(s) &&
                            !row.package.consigneeName
                                .toLowerCase()
                                .contains(s) &&
                            !itemName.contains(s)) {
                          return false;
                        }
                      }

                      if (rFilter != 'all' && row.reason != rFilter)
                        return false;

                      if (dateRange != null && row.date != null) {
                        final date = row.date!;
                        final startOfDay = DateTime(dateRange.start.year,
                            dateRange.start.month, dateRange.start.day);
                        final endOfDay = DateTime(dateRange.end.year,
                            dateRange.end.month, dateRange.end.day, 23, 59, 59);
                        if (date.isBefore(startOfDay) || date.isAfter(endOfDay))
                          return false;
                      }
                      if (!srYearMatches(row.package.srNumber, _yearFilter))
                        return false;
                      return true;
                    }).toList();

                    return Container(
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
                                label: Text('Abandoned Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 130),
                            DataColumn2(
                                label: Text('Reason'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Abandoned Date'),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Appeal')),
                                size: ColumnSize.S,
                                fixedWidth: 130),
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
                                    DataCell(Center(
                                        child: Text('${row.qty}'))),
                                    DataCell(TooltipText(row.reason,
                                        overflow: TextOverflow.ellipsis)),
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
                                            entryDate:
                                                row.package.entryDate ??
                                                    row.package.createdAt))),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.item.id,
                                            useLegacySummary: true,
                                            // Every row in this table is an
                                            // actionable abandoned item — force
                                            // the Final Disposition button.
                                            forceFinalDisposition: true,
                                            onSaleOrDestroyRequest:
                                                (disposition) =>
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
