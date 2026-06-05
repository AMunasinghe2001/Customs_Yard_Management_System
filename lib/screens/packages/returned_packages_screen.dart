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
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/styled_dropdown.dart';
import 'package:data_table_2/data_table_2.dart';

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

  WarehouseEntryModel? _latestReturnedEntry(PackageModel package) {
    final entries =
        package.warehouseEntries.where((e) => e.isReturned).toList();
    if (entries.isEmpty) return null;
    entries.sort((a, b) {
      final aDate = a.returnedAt ?? a.admittedAt;
      final bDate = b.returnedAt ?? b.admittedAt;
      return bDate.compareTo(aDate);
    });
    return entries.first;
  }

  /// A returned entry that represents an actual RELEASE — not a forfeit,
  /// abandonment or other disposition. Plain/untagged returns are releases;
  /// final releases are tagged "[FINAL:RELEASED]" or "[RELEASE...]".
  bool _isReleaseEntry(WarehouseEntryModel e) {
    if (!e.isReturned) return false;
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    if (notes.isEmpty) return true;
    if (!notes.startsWith('[')) return true; // free-text receipt note
    return notes.startsWith('[FINAL:RELEASED]') || notes.startsWith('[RELEASE');
  }

  List<_ReturnedRow> _buildReturnedRows(List<PackageModel> packages) {
    final rows = <_ReturnedRow>[];
    for (final package in packages) {
      for (final entry in package.warehouseEntries) {
        if (!_isReleaseEntry(entry)) continue;
        rows.add(_ReturnedRow(
          package: package,
          entry: entry,
          itemName: _returnedItemName(package, entry),
          receiptNo: _extractReceiptNo(entry.returnNotes),
          receiptDate: _extractReceiptDate(entry.returnNotes),
        ));
      }
    }
    rows.sort((a, b) {
      final aDate = a.entry.returnedAt ?? a.entry.admittedAt;
      final bDate = b.entry.returnedAt ?? b.entry.admittedAt;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  String _returnedItemName(PackageModel package, WarehouseEntryModel? entry) {
    if (entry == null) return '—';
    final itemId = entry.packageItemId;
    for (final item in package.items) {
      if (item.id == itemId) return item.itemName;
    }
    if (package.items.isNotEmpty) return package.items.first.itemName;
    return '—';
  }

  String? _extractReceiptNo(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    for (final part in notes.split('|')) {
      final text = part.trim();
      if (text.toLowerCase().startsWith('receipt no:')) {
        final idx = text.indexOf(':');
        if (idx != -1) return text.substring(idx + 1).trim();
      }
    }
    return null;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableSearchCtrl.text = ref.read(returnedPackageSearchProvider);
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
    final search = ref.watch(returnedPackageSearchProvider);
    final dateRange = ref.watch(returnedPackageDateRangeProvider);
    final rFilter = ref.watch(returnedPackageReasonFilterProvider);

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
                        Text('Released Packages',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(
                          'View and search all packages that have been released',
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final pkgs = ref.watch(livePackagesProvider);
                            return pkgs.when(
                              data: (list) {
                                final count = _buildReturnedRows(list).length;
                                return Text('$count Released',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold));
                              },
                              loading: () => const SizedBox(),
                              error: (_, __) => const SizedBox(),
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
                        ref.watch(holdReasonsProvider).when(
                              loading: () => const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (reasons) {
                                return StyledDropdownButton<String>(
                                  value: rFilter == 'all' ? null : rFilter,
                                  allLabel: 'All Reasons',
                                  icon: Icons.label_outline_rounded,
                                  menuWidth: 320,
                                  options: reasons
                                      .map((r) => StyledDropdownOption(
                                          r.reasonText, r.reasonText))
                                      .toList(),
                                  onChanged: (v) => ref
                                      .read(returnedPackageReasonFilterProvider
                                          .notifier)
                                      .state = v ?? 'all',
                                );
                              },
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
                    final rows = _buildReturnedRows(list).where((row) {
                      if (search.isNotEmpty) {
                        final s = search.toLowerCase();
                        final receiptNo = row.receiptNo?.toLowerCase() ?? '';
                        final itemName = row.itemName.toLowerCase();
                        if (!row.package.srNumber
                                .toLowerCase()
                                .contains(s) &&
                            !row.package.consigneeName
                                .toLowerCase()
                                .contains(s) &&
                            !itemName.contains(s) &&
                            !receiptNo.contains(s)) {
                          return false;
                        }
                      }

                      if (rFilter != 'all' && row.entry.holdReason != rFilter)
                        return false;

                      if (dateRange != null) {
                        final date =
                            row.entry.returnedAt ?? row.entry.admittedAt;
                        final startOfDay = DateTime(dateRange.start.year,
                            dateRange.start.month, dateRange.start.day);
                        final endOfDay = DateTime(dateRange.end.year,
                            dateRange.end.month, dateRange.end.day, 23, 59, 59);
                        if (date.isBefore(startOfDay) || date.isAfter(endOfDay))
                          return false;
                      }
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
                          empty: const EmptyTableState(message: 'No released packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                            columns: const [
                              DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                              DataColumn2(
                                label: Text('Item Name'), size: ColumnSize.M),
                              DataColumn2(
                                label: Text('Released Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 120),
                              DataColumn2(
                                label: Text('Charge'),
                                size: ColumnSize.M),
                              DataColumn2(
                                label: Text('Receipt No'), size: ColumnSize.M),
                              DataColumn2(
                                label: Text('Receipt Date'),
                                size: ColumnSize.M),
                              DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                            ],
                            rows: rows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(row.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: Text(
                                            '${row.entry.itemCount}'))),
                                    DataCell(Text((() {
                                      return 'LKR ${NumberFormat('#,##0.00').format(row.entry.calculatePackageCharge(row.package.items, storageRateHistory))}';
                                    })(),
                                        style: TextStyle(
                                            color: context.colors.primaryGold,
                                            fontWeight: FontWeight.bold))),
                                    DataCell(Text(row.receiptNo ?? '—',
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text((() {
                                      if (row.receiptDate != null)
                                        return row.receiptDate!;
                                      return row.entry.returnedAt != null
                                          ? DateFormat('yyyy-MM-dd')
                                              .format(row.entry.returnedAt!)
                                          : '—';
                                    })())),
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
                                            useLegacySummary: true,
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

  const _ReturnedRow({
    required this.package,
    required this.entry,
    required this.itemName,
    this.receiptNo,
    this.receiptDate,
  });
}

