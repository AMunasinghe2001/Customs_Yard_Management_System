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

    return AppShell(
      currentRoute: '/warehouses',
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: context.colors.scaffoldBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('SR Unit Warehouses', style: Theme.of(context).textTheme.headlineLarge),
                        Text('Track packages held in SR Unit facilities',
                            style: TextStyle(color: context.colors.textSecondary)),
                      ]),
                      SizedBox(child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ref.watch(allWarehouseEntriesProvider).when(
                          data: (list) {
                            final packageEntries = <String, List<WarehouseEntryModel>>{};
                            for (var e in list) {
                              packageEntries.putIfAbsent(e.packageId, () => []).add(e);
                            }
                            final returnedCount = packageEntries.values.where((entries) => 
                              entries.any((e) => e.isReturned)
                            ).length;
                            return Text('$returnedCount Returned',
                                style: TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.bold));
                          },
                          loading: () => const SizedBox(),
                    error: (e, _) => ErrorView(error: e, onRetry: () => ref.refresh(allWarehouseEntriesProvider)),
                        ),
                        const Gap(24),
                        Text('Show Returned', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                        const Gap(8),
                        Switch(value: showReturned,
                            onChanged: (v) => ref.read(warehouseEntryFilterProvider.notifier).state = v,
                            activeColor: context.colors.primaryGold),
                      ])),
                    ],
                  ),
                ).animate().fadeIn(),
              ),
              const Gap(20),
              warehouses.when(
                loading: () => const TabBar(tabs: [Tab(text: 'Warehouse 01'), Tab(text: 'Warehouse 02'), Tab(text: 'Warehouse 03')]),
                error: (e, _) => Text('Error: $e'),
                data: (ws) => Container(
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
              ),
              const Gap(16),
              Expanded(
                child: warehouses.when(
                  loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(error: e, onRetry: () => ref.refresh(warehousesProvider)),
                  data: (ws) => TabBarView(children: ws.map((w) => _WarehouseTab(warehouse: w)).toList()),
                ),
              ),
            ],
          ),
        ),
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
          if (filter != 'all') {
            if (filter == 'returned') {
              if (!e.isReturned) return false;
            } else {
              if (e.packageStatus != filter) return false;
            }
          }
          if (!showReturned && e.isReturned && filter != 'returned') return false;
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
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                  _MiniStat(label: 'Total', value: '${list.length}', color: context.colors.accentLightBlue),
                  _MiniStat(label: 'Held', value: '${list.where((e) => !e.isReturned).length}', color: context.colors.heldOrange),
                  _MiniStat(label: 'Confiscated', value: '${list.where((e) => e.isPackageConfiscated).length}', color: context.colors.dangerRed),
                  _MiniStat(label: 'Returned', value: '${list.where((e) => e.isReturned).length}', color: context.colors.successGreen),
                ]).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
                const Gap(20),

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
                        ...['all', 'pending', 'held', 'cleared', 'confiscated', 'returned'].map((s) => FilterChip(
                          label: Text(s.toUpperCase()),
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
                          rows: filteredList.map((e) => DataRow(cells: [
                            DataCell(Text(e.srNumber ?? e.packageId.substring(0, 8).toUpperCase(),
                                style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600))),
                            DataCell(Consumer(builder: (context, ref, _) {
                              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                              if (pkg == null) return const Text('—', style: TextStyle(fontSize: 13));
                              if (e.packageItemId != null) {
                                final item = pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item?.itemName ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                    if (item?.category != null)
                                      Text(item!.category!, style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
                                  ],
                                );
                              } else {
                                final names = pkg.items.map((i) => i.itemName).join(', ');
                                return Text(names.isEmpty ? '—' : names, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis);
                              }
                            })),
                            DataCell(Consumer(builder: (context, ref, _) {
                              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                              int displayCount = e.itemCount;
                              
                              // Auto-repair display logic for old entries that saved 1 as itemCount
                              if (pkg != null && e.packageItemId != null && displayCount == 1 && !e.isReturned) {
                                final item = pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
                                if (item != null && item.quantity > 1) {
                                  // Find sum of returned items to show correct held sum
                                  final returnedSum = pkg.warehouseEntries
                                      .where((we) => we.packageItemId == item.id && we.isReturned)
                                      .fold(0, (sum, we) => sum + we.itemCount);
                                  displayCount = item.quantity - returnedSum;
                                  if (displayCount < 1) displayCount = 1;
                                }
                              }
                              
                              return Text('$displayCount');
                            })),
                            DataCell(Center(child: Consumer(builder: (context, ref, _) {
                              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                              return Text(
                                pkg == null 
                                  ? '—' 
                                  : 'LKR ${NumberFormat('#,##0.00').format(e.calculatePackageCharge(pkg.items, storageRateHistory))}',
                                style: TextStyle(color: e.isPackageConfiscated ? context.colors.textMuted : context.colors.primaryGold, fontWeight: FontWeight.bold),
                              );
                            }))),
                            DataCell(Center(child: Consumer(builder: (context, ref, _) {
                              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                              String status = e.isReturned ? 'returned' : (e.isPackageConfiscated ? 'confiscated' : 'held');
                              if (pkg != null && e.packageItemId != null) {
                                final item = pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
                                if (item != null && !e.isReturned) {
                                  status = item.status;
                                }
                              }
                              return StatusChip(status: status);
                            }))),
                            DataCell(Consumer(builder: (context, ref, _) {
                              // If it's linked to an item, use the item's reasons
                              final pkg = ref.watch(packageDataProvider(e.packageId)).valueOrNull;
                              String displayReason = e.holdReason;
                              if (pkg != null && e.packageItemId != null) {
                                final item = pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
                                if (item?.reasons != null && item!.reasons!.isNotEmpty) {
                                  displayReason = item.reasons!;
                                }
                              }
                              return Text(displayReason, 
                                  style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12), 
                                  overflow: TextOverflow.ellipsis);
                            })),
                            DataCell(Center(child: Text(DateFormat('dd/MM/yy').format(e.admittedAt)))),
                            DataCell(Center(child: IconButton(
                              icon: Icon(Icons.info_outline_rounded, color: context.colors.accentLightBlue, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final pkg = await ref.read(packageServiceProvider).getPackageById(e.packageId);
                                if (pkg != null && context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: pkg, 
                                      storageRate: storageRateHistory,
                                      highlightEntry: e,
                                    ),
                                  );
                                }
                              },
                            ))),
                          ])).toList(),
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
          title: const Text('Mark as Returned / Release'),
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
                decoration: const InputDecoration(labelText: 'Return / Release Notes (optional)'), maxLines: 2),
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
                    SnackBar(content: const Text('✅ Package marked as returned'), backgroundColor: context.colors.successGreen));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.dangerRed));
                }
              },
              child: const Text('Confirm Return'),
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
