import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/supabase_client.dart';


class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);
    final showReturned = ref.watch(warehouseEntryFilterProvider);

    return warehouses.when(
      loading: () => _buildLoadingState(context),
      error: (e, _) => AppShell(currentRoute: '/warehouses', child: ErrorView(error: e, onRetry: () => ref.refresh(warehousesProvider))),
      data: (ws) => DefaultTabController(
        length: ws.length,
        child: AppShell(
          currentRoute: '/warehouses',
          child: Scaffold(
            backgroundColor: context.colors.scaffoldBg,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WarehousesHeaderWithStats(ws),
                const Gap(20),
                Container(
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderColor),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: TabBar(
                      tabs: ws.map((w) => Tab(
                        child: Text(_formatWarehouseName(w.name), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      )).toList(),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(2),
                      indicator: BoxDecoration(
                        color: context.colors.primaryGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
                      ),
                      splashBorderRadius: BorderRadius.circular(12),
                      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (states.contains(WidgetState.hovered)) return Colors.grey.withOpacity(0.1);
                        if (states.contains(WidgetState.focused)) return Colors.grey.withOpacity(0.1);
                        return Colors.transparent;
                      }),
                      splashFactory: NoSplash.splashFactory,
                      labelColor: context.colors.primaryGold,
                      unselectedLabelColor: context.colors.textSecondary,
                      dividerColor: Colors.transparent,
                    ),
                  ),
                ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                const Gap(16),
                Expanded(
                  child: TabBarView(children: ws.map((w) => _WarehouseTab(warehouse: w)).toList()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return AppShell(
      currentRoute: '/warehouses',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
      ),
    );
  }
}

class _WarehouseTab extends ConsumerWidget {
  final WarehouseModel warehouse;
  const _WarehouseTab({required this.warehouse});

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
    final entries = ref.watch(liveWarehouseEntriesProvider(warehouse.id));
    return entries.when(
      loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.refresh(liveWarehouseEntriesProvider(warehouse.id))),
      data: (list) {
        final filter = ref.watch(warehouseStatusFilterProvider(warehouse.id));
        final reasonFilter = ref.watch(warehouseReasonFilterProvider(warehouse.id));
        final search = ref.watch(warehouseSearchProvider(warehouse.id)).toLowerCase();
        final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ?? {DateTime(2020,1,1): 50.0};

        final dateRange = ref.watch(warehouseDateRangeProvider(warehouse.id));
        final showReturned = ref.watch(warehouseEntryFilterProvider);
        final filteredList = list.where((e) {
          if (e.isReturned) return false;
          if (filter != 'all') {
            if (filter == 'confiscated') {
              if (!e.isPackageConfiscated) return false;
            } else {
              // ref.watch so the filter reacts when package data loads in any warehouse tab
              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
              if (pkg != null) {
                final item = e.packageItemId != null
                    ? pkg.items.where((i) => i.id == e.packageItemId).firstOrNull
                    : null;
                final rawStatus = item?.status ?? '';
                // Normalise: treat 'Forfiet' (typo) same as 'Forfeit'
                final normStatus = rawStatus.toLowerCase() == 'forfiet' ? 'Forfeit' : rawStatus;
                if (normStatus != filter) return false;
              }
              // If pkg not cached yet, include entry (will re-filter on next build)
            }
          }
          if (reasonFilter != 'all' && e.holdReason != reasonFilter) return false;
          if (dateRange != null) {
            final date = e.admittedAt;
            final startOfDay = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
            final endOfDay = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59);
            if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) return false;
          }
          if (search.isNotEmpty) {
            final matchesSr = (e.srNumber?.toLowerCase() ?? '').contains(search);
            final matchesConsignee = (e.consigneeName?.toLowerCase() ?? '').contains(search);
            final matchesReason = e.holdReason.toLowerCase().contains(search);
            if (!matchesSr && !matchesConsignee && !matchesReason) return false;
          }
          return true;
        }).toList();

        if (list.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.warehouse_rounded, size: 64, color: context.colors.textMuted.withOpacity(0.4)),
            const Gap(16),
            Text('${_formatWarehouseName(warehouse.name)} is empty', style: TextStyle(color: context.colors.textMuted, fontSize: 16)),
          ]));
        }

        return Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                

                // ── Unified Search & Filter Bar ──────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
                  ),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: TextField(
                          style: TextStyle(color: context.colors.textPrimary),
                          onChanged: (v) => ref.read(warehouseSearchProvider(warehouse.id).notifier).state = v,
                          decoration: InputDecoration(
                            hintText: 'Search SR #, consignee or reason...',
                            prefixIcon: Icon(Icons.search_rounded, color: context.colors.textMuted),
                            isDense: true,
                          ),
                        ),
                      ),
                    ]),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...['all', 'Detain', 'Forfeit', 'Abandoned', 'confiscated'].map((s) => FilterChip(
                          label: Text(s == 'all' ? 'ALL' : s.toUpperCase()),
                          selected: filter == s,
                          onSelected: (_) => ref.read(warehouseStatusFilterProvider(warehouse.id).notifier).state = s,
                          selectedColor: context.colors.primaryGold.withOpacity(0.2),
                          checkmarkColor: context.colors.primaryGold,
                          labelStyle: TextStyle(
                            color: filter == s ? context.colors.primaryGold : context.colors.textSecondary,
                            fontSize: 12, fontWeight: filter == s ? FontWeight.w700 : FontWeight.w400),
                        )),
                        Consumer(builder: (context, ref, _) {
                          final dateRange = ref.watch(warehouseDateRangeProvider(warehouse.id));
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDialog<dynamic>(
                                    context: context,
                                    builder: (context) => custom.DateRangePickerDialog(initialRange: dateRange),
                                  );
                                  if (picked is DateTimeRange) {
                                    ref.read(warehouseDateRangeProvider(warehouse.id).notifier).state = picked;
                                  } else if (picked == false) {
                                    ref.read(warehouseDateRangeProvider(warehouse.id).notifier).state = null;
                                  }
                                },
                                icon: Icon(Icons.date_range_rounded, size: 16, color: dateRange != null ? context.colors.primaryGold : context.colors.textSecondary),
                                label: Text(
                                  dateRange != null
                                    ? '${DateFormat('MMM d').format(dateRange.start)} - ${DateFormat('MMM d').format(dateRange.end)}'
                                    : 'Date Range',
                                  style: TextStyle(color: dateRange != null ? context.colors.primaryGold : context.colors.textSecondary, fontSize: 12, fontWeight: dateRange != null ? FontWeight.bold : FontWeight.normal),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: dateRange != null ? context.colors.primaryGold : context.colors.borderColor),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              if (dateRange != null) ...[
                                const Gap(8),
                                IconButton(
                                  icon: Icon(Icons.clear_rounded, size: 16, color: context.colors.dangerRed),
                                  onPressed: () => ref.read(warehouseDateRangeProvider(warehouse.id).notifier).state = null,
                                  tooltip: 'Clear Date Filter',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ],
                          );
                        }),
                        Consumer(builder: (context, ref, _) {
                          final rFilter = ref.watch(warehouseReasonFilterProvider(warehouse.id));
                          return ref.watch(holdReasonsProvider).when(
                            loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (reasons) {
                              final items = ['all', ...reasons.map((r) => r.reasonText)];
                              return Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.colors.borderColor),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: items.contains(rFilter) ? rFilter : 'all',
                                    isDense: true,
                                    dropdownColor: context.colors.surfaceDark,
                                    icon: Icon(Icons.arrow_drop_down, color: context.colors.primaryGold, size: 16),
                                    style: TextStyle(color: context.colors.textPrimary, fontSize: 12),
                                    onChanged: (v) {
                                      if (v != null) ref.read(warehouseReasonFilterProvider(warehouse.id).notifier).state = v;
                                    },
                                    items: items.map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s == 'all' ? 'All Reasons' : s),
                                    )).toList(),
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                const Gap(16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 10,
                          horizontalMargin: 12,
                          fixedTopRows: 1,
                          columns: const [
                            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(label: Text('Item Name'), size: ColumnSize.L),
                            DataColumn2(label: Text('No. of Packages'), size: ColumnSize.S, fixedWidth: 100),
                            DataColumn2(label: Center(child: Text('Charge')), size: ColumnSize.M),
                            DataColumn2(label: Center(child: Text('Status')), size: ColumnSize.M),
                            DataColumn2(label: Text('Reason'), size: ColumnSize.L),
                            DataColumn2(label: Center(child: Text('Entry Date')), size: ColumnSize.M),
                            DataColumn2(label: Center(child: Text('Details')), size: ColumnSize.S, fixedWidth: 60),
                          ],
                          rows: filteredList.map((e) {
                            final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                            String status = e.isReturned ? 'returned' : (e.isPackageConfiscated ? 'confiscated' : 'held');
                            if (pkg != null && e.packageItemId != null) {
                              final item = pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
                              if (item != null && !e.isReturned) {
                                status = item.status;
                              }
                            }
                            final isItemConfiscated =
                                WarehouseEntryModel.isNoChargeStatus(status.toLowerCase());
                            
                            final charge = pkg == null ? 0.0 : e.calculatePackageCharge(pkg.items, storageRateHistory);
                            final isFree = charge <= 0;

                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>((states) {
                                if (isItemConfiscated) return Colors.grey.withOpacity(0.08);
                                return null;
                              }),
                              cells: [
                                DataCell(Text(e.srNumber ?? e.packageId.substring(0, 8).toUpperCase(),
                                    style: TextStyle(
                                      color: isItemConfiscated ? context.colors.textMuted : context.colors.accentLightBlue, 
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13
                                    ))),
                                DataCell(Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (pkg == null) const Text('—', style: TextStyle(fontSize: 13))
                                    else if (e.packageItemId != null) ...[
                                      Text(pkg.items.where((i) => i.id == e.packageItemId).firstOrNull?.itemName ?? '—', 
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isItemConfiscated ? context.colors.textMuted : null), 
                                          overflow: TextOverflow.ellipsis),
                                      if (pkg.items.where((i) => i.id == e.packageItemId).firstOrNull?.category != null)
                                        Text(pkg.items.where((i) => i.id == e.packageItemId).firstOrNull!.category!, 
                                            style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
                                    ] else ...[
                                      Text(pkg.items.map((i) => i.itemName).join(', '), 
                                          style: TextStyle(fontSize: 13, color: isItemConfiscated ? context.colors.textMuted : null), 
                                          overflow: TextOverflow.ellipsis)
                                    ]
                                  ],
                                )),
                                DataCell(Text('${e.itemCount}', style: TextStyle(color: isItemConfiscated ? context.colors.textMuted : null))),
                                DataCell(Center(child: Text(
                                  pkg == null ? '—' : (isFree ? '—' : 'LKR ${NumberFormat('#,##0.00').format(charge)}'),
                                  style: TextStyle(
                                    color: isFree ? context.colors.textMuted : context.colors.primaryGold, 
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13
                                  ),
                                ))),
                                DataCell(Center(child: StatusChip(status: status))),
                                DataCell(Text(e.holdReason, 
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic, 
                                      fontSize: 12,
                                      color: isItemConfiscated ? context.colors.textMuted : null
                                    ), 
                                    overflow: TextOverflow.ellipsis)),
                                DataCell(Center(child: Text(DateFormat('dd/MM/yy').format(e.admittedAt),
                                    style: TextStyle(color: isItemConfiscated ? context.colors.textMuted : null)))),
                                DataCell(Center(child: IconButton(
                                  icon: Icon(Icons.info_outline_rounded, color: context.colors.accentLightBlue, size: 20),
                                  padding: const EdgeInsets.all(4),
                                  onPressed: () async {
                                    final pkgFull = await ref.read(packageDataProvider(e.packageId).future);
                                    if (pkgFull != null && context.mounted) {
                                      showDialog(
                                        context: context,
                                        builder: (_) => PackageDetailsDialog(
                                          package: pkgFull, 
                                          storageRate: storageRateHistory,
                                          highlightEntry: e,
                                          useWarehouseSummary: true,
                                        ),
                                      );
                                    }
                                  },
                                ))),
                              ],
                            );
                          }).toList(),
                        ),
                    ),
                  ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                ),
              ]),
            );
      },
    );
  }

  void _showReturnDialog(BuildContext context, WidgetRef ref, WarehouseEntryModel entry) {
    final notesCtrl = TextEditingController();
    final storageRateHistory = ref.read(storageRateProvider).valueOrNull ?? {DateTime(2020,1,1): 50.0};
    
    showDialog(
      context: context,
      builder: (ctx) => Consumer(builder: (context, ref, _) {
        final pkg = ref.watch(packageDataProvider(entry.packageId)).valueOrNull;
        final charge = pkg != null ? entry.calculatePackageCharge(pkg.items, storageRateHistory) : 0.0;
        
        return AlertDialog(
          title: const Text('Mark as Released'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SR Number: ${entry.srNumber ?? entry.packageId.substring(0, 8).toUpperCase()}',
                style: TextStyle(color: context.colors.textSecondary)),
            Text('Location: ${entry.warehouseName}',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.colors.surfaceDark, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Storage Days:', style: TextStyle(color: context.colors.textMuted)),
                  Text('${entry.storageDays}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                const Gap(4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Final Charge:', style: TextStyle(color: context.colors.textMuted)),
                  Text('LKR ${NumberFormat('#,##0.00').format(charge)}',
                      style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ]),
            ),
            const Gap(16),
            TextField(controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Release Notes (optional)'), maxLines: 2),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.successGreen, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(warehouseServiceProvider).markAsReturned(entry.id,
                      returnNotes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null);
                  ref.invalidate(liveWarehouseEntriesProvider(entry.warehouseId));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('✅ Package marked as released'), backgroundColor: context.colors.successGreen));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.dangerRed));
                }
              },
              child: const Text('Confirm Release'),
            ),
          ],
        );
      }),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value; final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        const Gap(10),
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}


class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});
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
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _WarehousesHeaderWithStats extends ConsumerWidget {
  final List<WarehouseModel> warehouses;
  const _WarehousesHeaderWithStats(this.warehouses);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (context) {
        final tabController = DefaultTabController.of(context);
        return AnimatedBuilder(
          animation: tabController,
          builder: (context, _) {
            final activeTab = tabController.index;
            final warehouse = warehouses[activeTab];
            final entries = ref.watch(liveWarehouseEntriesProvider(warehouse.id)).valueOrNull ?? [];

            int total = entries.where((e) => !e.isReturned).length;
            // ref.watch so header stats rebuild when package data loads for any warehouse
            int held = entries.where((e) {
              if (e.isReturned) return false;
              if (e.isPackageConfiscated) return false;
              if (e.packageItemId != null) {
                final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                final item = pkg?.items.where((i) => i.id == e.packageItemId).firstOrNull;
                final s = item?.status?.toLowerCase() ?? '';
                return !WarehouseEntryModel.isNoChargeStatus(s);
              }
              return true;
            }).length;
            int confiscated = entries.where((e) {
              if (e.isReturned) return false;
              if (e.isPackageConfiscated) return true;
              if (e.packageItemId != null) {
                final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                final item = pkg?.items.where((i) => i.id == e.packageItemId).firstOrNull;
                final s = item?.status?.toLowerCase() ?? '';
                return WarehouseEntryModel.isNoChargeStatus(s);
              }
              return false;
            }).length;

            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 16,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SR Unit Warehouses', style: Theme.of(context).textTheme.headlineLarge),
                      const Gap(4),
                      Text('Track packages held in SR Unit facilities',
                          style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                    ]),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatChip(label: 'Total', value: total.toString(), color: context.colors.accentLightBlue).animate().fadeIn(delay: 100.ms).scale(),
                        const Gap(8),
                        _StatChip(label: 'Held', value: held.toString(), color: context.colors.heldOrange).animate().fadeIn(delay: 200.ms).scale(),
                        const Gap(8),
                        _StatChip(label: 'Confiscated', value: confiscated.toString(), color: context.colors.dangerRed).animate().fadeIn(delay: 300.ms).scale(),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(),
            );
          },
        );
      }
    );
  }
}
