import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/styled_dropdown.dart';
import 'package:data_table_2/data_table_2.dart';

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key});
  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  PackageModel? _srResult;
  String? _srError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableSearchCtrl.text = ref.read(packageSearchProvider);
    });
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  /// Reset to the first page (called from a filter listener) — deferred so it
  /// doesn't mutate provider state during the build/listen callback.
  void _resetPage() {
    if (ref.read(packagePageProvider) == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(packagePageProvider.notifier).state = 0;
    });
  }

  void _onSrSubmitted(String val) {
    final sr = val.trim();
    if (sr.isEmpty) {
      setState(() {
        _srResult = null;
        _srError = null;
      });
      return;
    }
    final packages = ref.read(livePackagesProvider).valueOrNull ?? [];
    final match = packages
        .where((p) => p.srNumber.toLowerCase().contains(sr.toLowerCase()))
        .firstOrNull;
    setState(() {
      _srResult = match;
      _srError = match == null ? 'No package found matching: "$sr"' : null;
    });
  }

  String _formatWarehouseName(String name) {
    // Extract warehouse number from names like "SR Warehouse 03" -> "Warehouse 3"
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(packageFilterProvider);
    final pagedPackages = ref.watch(packagesPageProvider);
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ?? {DateTime(2020,1,1): 50.0};

    // Any filter change resets the table back to the first page.
    ref.listen(packageSearchProvider, (_, __) => _resetPage());
    ref.listen(packageDateRangeProvider, (_, __) => _resetPage());
    ref.listen(packageYearFilterProvider, (_, __) => _resetPage());

    return AppShell(
      currentRoute: '/packages',
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
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Package History',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text('Search and filter all inspected packages',
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // â”€â”€ Unified Search & Filter Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                                p.srNumber.toLowerCase().contains(query) ||
                                p.consigneeName.toLowerCase().contains(query));
                          },
                          onSelected: (package) {
                            setState(() {
                              _srResult = package;
                              _tableSearchCtrl.text = package.srNumber;
                              ref.read(packageSearchProvider.notifier).state =
                                  package.srNumber;
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
                                              .read(packageSearchProvider
                                                  .notifier)
                                              .state = '';
                                          setState(() {
                                            _srResult = null;
                                          });
                                        },
                                      )
                                    : null,
                                isDense: true,
                              ),
                              onChanged: (v) {
                                _tableSearchCtrl.text = v;
                                ref.read(packageSearchProvider.notifier).state =
                                    v;
                                setState(() {
                                  if (v.trim().isEmpty) _srResult = null;
                                });
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
                        Consumer(builder: (context, ref, _) {
                          final dateRange = ref.watch(packageDateRangeProvider);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
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
                                        .read(packageDateRangeProvider.notifier)
                                        .state = picked;
                                  } else if (picked == false) {
                                    ref
                                        .read(packageDateRangeProvider.notifier)
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              if (dateRange != null) ...[
                                const Gap(8),
                                IconButton(
                                  icon: Icon(Icons.clear_rounded,
                                      size: 16,
                                      color: context.colors.dangerRed),
                                  onPressed: () => ref
                                      .read(packageDateRangeProvider.notifier)
                                      .state = null,
                                  tooltip: 'Clear Date Filter',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ],
                          );
                        }),
                        // Year Filter Dropdown
                        Consumer(builder: (context, ref, _) {
                          final selectedYear = ref.watch(packageYearFilterProvider);
                          // Recent years (newest first). Avoids loading every
                          // package just to list years — the server filters by
                          // the chosen year via the SR-number suffix.
                          final thisYear = DateTime.now().year;
                          final years = [
                            for (var y = thisYear; y >= thisYear - 6; y--)
                              y.toString()
                          ];
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StyledDropdownButton<String>(
                                value: selectedYear,
                                allLabel: 'All Years',
                                icon: Icons.calendar_today_rounded,
                                columns: 2,
                                options: years
                                    .map((y) =>
                                        StyledDropdownOption(y, y))
                                    .toList(),
                                onChanged: (val) => ref
                                    .read(packageYearFilterProvider.notifier)
                                    .state = val,
                              ),
                              if (selectedYear != null) ...[
                                const Gap(8),
                                IconButton(
                                  icon: Icon(Icons.clear_rounded,
                                      size: 16,
                                      color: context.colors.dangerRed),
                                  onPressed: () => ref
                                      .read(packageYearFilterProvider.notifier)
                                      .state = null,
                                  tooltip: 'Clear Year Filter',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),

              if (_srResult != null) ...[
                const Gap(16),
                _SrResultCard(
                    package: _srResult!,
                    onDetails: () => showDialog(
                          context: context,
                          builder: (_) => PackageDetailsDialog(
                              package: _srResult!,
                              storageRate: storageRateHistory),
                        )).animate().fadeIn(),
              ],
              const Gap(16),
              Expanded(
                child: pagedPackages.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(packagesPageProvider)),
                  data: (page) {
                    // Rows come pre-filtered + pre-paged from the server.
                    final filteredList = page.rows;
                    final currentPage = ref.watch(packagePageProvider);
                    final from = page.total == 0
                        ? 0
                        : currentPage * kPackagePageSize + 1;
                    final to = currentPage * kPackagePageSize + filteredList.length;
                    final hasPrev = currentPage > 0;
                    final hasNext = to < page.total;

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
                          empty: const EmptyTableState(message: 'No packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                            columns: const [
                            DataColumn2(
                              label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                              label: Text('Cusdec No'), size: ColumnSize.M),
                            DataColumn2(
                              label: Text('Cusdec Date'), size: ColumnSize.M),
                            DataColumn2(
                              label: Center(child: Text('Entry Date')),
                              size: ColumnSize.M),
                            DataColumn2(
                              label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                              label: Text('Declarant'), size: ColumnSize.M),
                            DataColumn2(
                              label: Text('Declarant Phone'),
                              size: ColumnSize.M),
                            DataColumn2(
                              label: Center(child: Text('Details')),
                              size: ColumnSize.S,
                              fixedWidth: 55),
                            ],
                          rows: filteredList
                              .map((p) => DataRow(cells: [
                                    DataCell(Text(p.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                DataCell(Text(p.cusdecNo ?? 'â€”',
                                  overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.cusdecDate ?? 'â€”',
                                  overflow: TextOverflow.ellipsis)),
                                DataCell(Center(
                                  child: Text(p.entryDate != null
                                    ? DateFormat('yyyy-MM-dd')
                                      .format(p.entryDate!)
                                    : DateFormat('yyyy-MM-dd')
                                      .format(p.createdAt)))),
                                DataCell(Text(p.consigneeName,
                                  overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.declarantName ?? 'â€”',
                                  overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.consigneePhone ?? 'â€”',
                                  overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => PackageDetailsDialog(
                                            package: p,
                                            storageRate: storageRateHistory),
                                      ),
                                    ))),
                                  ]))
                              .toList(),
                        ),
                      ),
                          ),
                        ),
                        // ── Pager bar ──
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Text(
                                  page.total == 0
                                      ? 'No packages'
                                      : 'Showing $from–$to of ${page.total}',
                                  style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 13)),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Previous page',
                                icon: const Icon(Icons.chevron_left_rounded),
                                color: context.colors.primaryGold,
                                onPressed: hasPrev
                                    ? () => ref
                                        .read(packagePageProvider.notifier)
                                        .state = currentPage - 1
                                    : null,
                              ),
                              Text('Page ${currentPage + 1}',
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontWeight: FontWeight.w600)),
                              IconButton(
                                tooltip: 'Next page',
                                icon: const Icon(Icons.chevron_right_rounded),
                                color: context.colors.primaryGold,
                                onPressed: hasNext
                                    ? () => ref
                                        .read(packagePageProvider.notifier)
                                        .state = currentPage + 1
                                    : null,
                              ),
                            ],
                          ),
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

// â”€â”€ SR Search Result Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SrResultCard extends ConsumerWidget {
  final PackageModel package;
  final VoidCallback onDetails;
  const _SrResultCard({required this.package, required this.onDetails});

  String _formatWarehouseName(String name) {
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeEntries =
        package.warehouseEntries.where((e) => !e.isReturned).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: context.colors.accentLightBlue.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_rounded,
              color: context.colors.accentLightBlue, size: 18),
          const Gap(8),
          Text(package.srNumber,
              style: TextStyle(
                  color: context.colors.accentLightBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const Spacer(),
          StatusChip(status: package.isReturned ? 'returned' : package.status),
        ]),
        const Gap(8),
        Text('Consignee: ${package.consigneeName}',
            style:
                TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        if (package.declarantName != null)
          Text('Declarant: ${package.declarantName}',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        const Gap(12),
        if (activeEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: package.status == 'held' 
                ? context.colors.dangerRed.withOpacity(0.1)
                : context.colors.successGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: package.status == 'held'
                  ? context.colors.dangerRed.withOpacity(0.3)
                  : context.colors.successGreen.withOpacity(0.3)
              ),
            ),
            child: Row(children: [
              Icon(
                package.status == 'held' ? Icons.error_outline_rounded : Icons.check_circle_outline,
                color: package.status == 'held' ? context.colors.dangerRed : context.colors.successGreen, 
                size: 18
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.status == 'held' 
                        ? 'INCOMPLETE ALLOCATION' 
                        : 'Not currently held in any warehouse.',
                      style: TextStyle(
                        color: package.status == 'held' ? context.colors.dangerRed : context.colors.successGreen, 
                        fontWeight: FontWeight.bold,
                        fontSize: 13
                      )
                    ),
                    if (package.status == 'held')
                      Text(
                        'This package was registered but never assigned to a warehouse (possibly due to a network error).',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 11)
                      ),
                  ],
                ),
              ),
              if (package.status == 'held')
                ElevatedButton(
                  onPressed: () {
                    // Navigate to registration and trigger lookup
                    ref.read(packageSearchProvider.notifier).state = package.srNumber;
                    context.push('/inspection');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.dangerRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36)
                  ),
                  child: const Text('FIX NOW', style: TextStyle(fontSize: 11)),
                ),
            ]),
          )
        else ...[
          Text('Current Warehouse Location:',
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
          const Gap(6),
          ...activeEntries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.heldOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: context.colors.heldOrange.withOpacity(0.35)),
                ),
                child: Row(children: [
                  Icon(Icons.warehouse_rounded,
                      color: context.colors.heldOrange, size: 18),
                  const Gap(10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_formatWarehouseName(e.warehouseName),
                            style: TextStyle(
                                color: context.colors.heldOrange,
                                fontWeight: FontWeight.w700)),
                        Text(
                            'Held since: ${DateFormat('dd/MM/yyyy HH:mm').format(e.admittedAt)}',
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                        Text('Reason: ${e.holdReason}',
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12)),
                      ])),
                  Text('${e.itemCount} items',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ]),
              )),
        ],
        const Gap(16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onDetails,
            icon: const Icon(Icons.info_outline_rounded, size: 16),
            label:
                const Text('View Full Details', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.accentLightBlue,
              side: BorderSide(
                  color: context.colors.accentLightBlue.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ),
      ]),
    );
  }
}

// â”€â”€ Warehouse Pill (for table) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WarehousePill extends StatelessWidget {
  final List<WarehouseEntryModel> warehouseEntries;
  const _WarehousePill({required this.warehouseEntries});

  static String _formatWarehouseName(String name) {
    // Extract warehouse number from names like "SR Warehouse 03" -> "Warehouse 3"
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final active = warehouseEntries.where((e) => !e.isReturned).toList();
    if (active.isEmpty)
      return Text('â€”', style: TextStyle(color: context.colors.textMuted));
    return Wrap(
        spacing: 4,
        children: active
            .map((e) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colors.heldOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: context.colors.heldOrange.withOpacity(0.4)),
                  ),
                  child: Text(_formatWarehouseName(e.warehouseName),
                      style: TextStyle(
                          color: context.colors.heldOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ))
            .toList());
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    color: context.colors.textPrimary, fontSize: 13))),
      ]),
    );
  }
}
