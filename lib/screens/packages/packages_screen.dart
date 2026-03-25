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
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
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

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(packageFilterProvider);
    final packages = ref.watch(livePackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? 0.0;

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
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      packages.when(
                          data: (list) {
                            final total = list.length;
                            final returned =
                                list.where((p) => p.isReturned).length;
                            return Text('$returned Returned',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold));
                          },
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox()),
                      const Gap(24),
                      Text('Show Returned',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 13)),
                      const Gap(8),
                      Switch(
                        value: ref.watch(packageShowReturnedProvider),
                        onChanged: (v) => ref
                            .read(packageShowReturnedProvider.notifier)
                            .state = v,
                        activeColor: context.colors.primaryGold,
                      ),
                    ]),
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
                        ...[
                          'all',
                          'pending',
                          'held',
                          'cleared',
                          'confiscated',
                          'returned'
                        ].map((s) => FilterChip(
                              label: Text(s.toUpperCase()),
                              selected: filter == s,
                              onSelected: (_) => ref
                                  .read(packageFilterProvider.notifier)
                                  .state = s,
                              selectedColor:
                                  context.colors.primaryGold.withOpacity(0.2),
                              checkmarkColor: context.colors.primaryGold,
                              labelStyle: TextStyle(
                                  color: filter == s
                                      ? context.colors.primaryGold
                                      : context.colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: filter == s
                                      ? FontWeight.w700
                                      : FontWeight.w400),
                            )),
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
                              const Gap(8),
                              ref.watch(holdReasonsProvider).when(
                                    loading: () => const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    error: (_, __) => const SizedBox.shrink(),
                                    data: (reasons) {
                                      final items = [
                                        'all',
                                        ...reasons.map((r) => r.reasonText)
                                      ];
                                      final currentReason = ref
                                          .watch(packageReasonFilterProvider);
                                      return Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color:
                                                  context.colors.borderColor),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: items.contains(currentReason)
                                                ? currentReason
                                                : 'all',
                                            isDense: true,
                                            dropdownColor:
                                                context.colors.surfaceDark,
                                            icon: Icon(Icons.arrow_drop_down,
                                                color:
                                                    context.colors.primaryGold,
                                                size: 16),
                                            style: TextStyle(
                                                color:
                                                    context.colors.textPrimary,
                                                fontSize: 12),
                                            onChanged: (v) {
                                              if (v != null)
                                                ref
                                                    .read(
                                                        packageReasonFilterProvider
                                                            .notifier)
                                                    .state = v;
                                            },
                                            items: items
                                                .map((s) => DropdownMenuItem(
                                                      value: s,
                                                      child: Text(s == 'all'
                                                          ? 'All Reasons'
                                                          : s),
                                                    ))
                                                .toList(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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
                              package: _srResult!, storageRate: storageRate),
                        )).animate().fadeIn(),
              ],
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
                    final showReturned = ref.watch(packageShowReturnedProvider);
                    final dateRange = ref.watch(packageDateRangeProvider);
                    final rFilter = ref.watch(packageReasonFilterProvider);
                    final filteredList = list.where((p) {
                      if (filter != 'all') {
                        if (filter == 'returned') {
                          if (!p.isReturned) return false;
                        } else {
                          if (p.status != filter) return false;
                        }
                      }
                      if (!showReturned && p.isReturned && filter != 'returned')
                        return false;
                      if (rFilter != 'all' && p.reason != rFilter) return false;
                      if (dateRange != null) {
                        final date = p.entryDate ?? p.createdAt;
                        final startOfDay = DateTime(dateRange.start.year,
                            dateRange.start.month, dateRange.start.day);
                        final endOfDay = DateTime(dateRange.end.year,
                            dateRange.end.month, dateRange.end.day, 23, 59, 59);
                        if (date.isBefore(startOfDay) || date.isAfter(endOfDay))
                          return false;
                      }
                      return true;
                    }).toList();

                    if (filteredList.isEmpty) {
                      return Center(
                          child: Text('No packages found',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 16)));
                    }

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
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Items'),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                            DataColumn2(
                                label: Text('Hold Reason'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Status')),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Date')),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Charge')),
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
                                    DataCell(Text(p.consigneeName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text('${p.totalItemCount}')),
                                    DataCell(Text(
                                        p.reason?.isNotEmpty == true
                                            ? p.reason!
                                            : '—',
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic),
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: StatusChip(
                                            status: p.isReturned
                                                ? 'returned'
                                                : p.status))),
                                    DataCell(Center(
                                        child: Text(p.entryDate != null
                                            ? DateFormat('dd/MM/yy')
                                                .format(p.entryDate!)
                                            : DateFormat('dd/MM/yy')
                                                .format(p.createdAt)))),
                                    DataCell(Center(
                                        child: Text(
                                            p.warehouseEntries.isEmpty
                                                ? '—'
                                                : 'LKR ${NumberFormat('#,##0.00').format(p.warehouseEntries.fold(0.0, (sum, e) => sum + e.calculateCharge(storageRate)))}',
                                            style: TextStyle(
                                                color: p.isConfiscated
                                                    ? context.colors.textMuted
                                                    : context
                                                        .colors.primaryGold,
                                                fontWeight: FontWeight.bold)))),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => PackageDetailsDialog(
                                            package: p,
                                            storageRate: storageRate),
                                      ),
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

// ── SR Search Result Card ──────────────────────────────────────

class _SrResultCard extends StatelessWidget {
  final PackageModel package;
  final VoidCallback onDetails;
  const _SrResultCard({required this.package, required this.onDetails});

  @override
  Widget build(BuildContext context) {
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
          Row(children: [
            Icon(Icons.check_circle_outline,
                color: context.colors.successGreen, size: 16),
            const Gap(6),
            Text('Not currently held in any warehouse.',
                style: TextStyle(
                    color: context.colors.successGreen, fontSize: 13)),
          ])
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
                        Text(e.warehouseName,
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

// ── Warehouse Pill (for table) ──────────────────────────────────

class _WarehousePill extends StatelessWidget {
  final List<WarehouseEntryModel> warehouseEntries;
  const _WarehousePill({required this.warehouseEntries});

  @override
  Widget build(BuildContext context) {
    final active = warehouseEntries.where((e) => !e.isReturned).toList();
    if (active.isEmpty)
      return Text('—', style: TextStyle(color: context.colors.textMuted));
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
                  child: Text(e.warehouseName,
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
