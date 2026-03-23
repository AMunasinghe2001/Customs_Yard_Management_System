import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import 'package:data_table_2/data_table_2.dart';


class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SR Unit Warehouses', style: Theme.of(context).textTheme.headlineLarge),
                      Text('Track packages held in SR Unit facilities',
                          style: TextStyle(color: context.colors.textSecondary)),
                    ]),
                    Row(children: [
                      Text('Show Returned', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                      const Gap(8),
                      Switch(value: showReturned,
                          onChanged: (v) => ref.read(warehouseEntryFilterProvider.notifier).state = v,
                          activeColor: context.colors.primaryGold),
                    ]),
                  ],
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
                        child: Text(w.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      )).toList(),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(2),
                      indicator: BoxDecoration(
                        color: context.colors.primaryGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
                      ),
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
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
                  error: (e, _) => Center(child: Text('Error: $e')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(liveWarehouseEntriesProvider(warehouse.id));
    return entries.when(
      loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        final filter = ref.watch(warehouseStatusFilterProvider(warehouse.id));
        final search = ref.watch(warehouseSearchProvider(warehouse.id)).toLowerCase();
        final storageRate = ref.watch(storageRateProvider).valueOrNull ?? 0.0;

        final filteredList = list.where((e) {
          if (filter != 'all' && e.packageStatus != filter) return false;
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
            Text('${warehouse.name} is empty', style: TextStyle(color: context.colors.textMuted, fontSize: 16)),
          ]));
        }

        return Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _MiniStat(label: 'Total', value: '${list.length}', color: context.colors.accentLightBlue),
                  const Gap(12),
                  _MiniStat(label: 'Held', value: '${list.where((e) => !e.isReturned).length}', color: context.colors.heldOrange),
                  const Gap(12),
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
                  child: Row(children: [
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
                    const Gap(12),
                    ...['all', 'pending', 'held', 'cleared', 'confiscated'].map((s) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text(s.toUpperCase()),
                        selected: filter == s,
                        onSelected: (_) => ref.read(warehouseStatusFilterProvider(warehouse.id).notifier).state = s,
                        selectedColor: context.colors.primaryGold.withOpacity(0.2),
                        checkmarkColor: context.colors.primaryGold,
                        labelStyle: TextStyle(
                          color: filter == s ? context.colors.primaryGold : context.colors.textSecondary,
                          fontSize: 12, fontWeight: filter == s ? FontWeight.w700 : FontWeight.w400),
                      ),
                    )),
                  ]),
                ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                const Gap(16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 12,
                          fixedTopRows: 1,
                          isHorizontalScrollBarVisible: false, // No horizontal scroll
                          columns: const [
                            DataColumn2(label: Text('SR Number'), size: ColumnSize.M, fixedWidth: 120),
                            DataColumn2(label: Text('Consignee'), size: ColumnSize.L),
                            DataColumn2(label: Text('Items Held'), size: ColumnSize.S, fixedWidth: 100),
                            DataColumn2(label: Text('Hold Reason'), size: ColumnSize.L),
                            DataColumn2(label: Text('Admitted'), size: ColumnSize.M, fixedWidth: 140),
                            DataColumn2(label: Text('Status'), size: ColumnSize.S, fixedWidth: 100),
                            DataColumn2(label: Text('Returned'), size: ColumnSize.S, fixedWidth: 100),
                            DataColumn2(label: Text('Charge (LKR)'), size: ColumnSize.S, fixedWidth: 120),
                            DataColumn2(label: Text('Action'), size: ColumnSize.S, fixedWidth: 140),
                          ],
                          rows: filteredList.map((e) => DataRow(cells: [
                            DataCell(Text(e.srNumber ?? e.packageId.substring(0, 8).toUpperCase(),
                                style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600))),
                            DataCell(Text(e.consigneeName ?? '—', style: const TextStyle(fontSize: 13))),
                            DataCell(Text('${e.itemCount}')),
                            DataCell(Text(e.holdReason, style: const TextStyle(fontSize: 13))),
                            DataCell(Text(DateFormat('dd/MM/yy HH:mm').format(e.admittedAt))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: e.isReturned 
                                    ? context.colors.successGreen.withOpacity(0.15) 
                                    : (e.isPackageConfiscated ? context.colors.dangerRed.withOpacity(0.15) : context.colors.heldOrange.withOpacity(0.15)),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: e.isReturned 
                                    ? context.colors.successGreen.withOpacity(0.4) 
                                    : (e.isPackageConfiscated ? context.colors.dangerRed.withOpacity(0.4) : context.colors.heldOrange.withOpacity(0.4))),
                              ),
                              child: Text(e.isReturned 
                                  ? 'RETURNED' 
                                  : (e.isPackageConfiscated ? 'CONFISCATED' : 'IN HOLD'),
                                  style: TextStyle(color: e.isReturned 
                                      ? context.colors.successGreen 
                                      : (e.isPackageConfiscated ? context.colors.dangerRed : context.colors.heldOrange), 
                                      fontSize: 11, fontWeight: FontWeight.w700)),
                            )),
                            DataCell(Text(e.returnedAt != null ? DateFormat('dd/MM/yy').format(e.returnedAt!) : '—',
                                style: TextStyle(color: context.colors.textMuted))),
                            DataCell(Text('LKR ${NumberFormat('#,##0.00').format(e.calculateCharge(storageRate))}',
                                style: TextStyle(color: e.isPackageConfiscated ? context.colors.textMuted : context.colors.primaryGold, fontWeight: FontWeight.bold))),
                            DataCell(e.isReturned
                                ? Text('—', style: TextStyle(color: context.colors.textMuted))
                                : (e.isPackageConfiscated 
                                    ? Tooltip(message: 'Confiscated goods cannot be returned', child: Text('LOCKED', style: TextStyle(color: context.colors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)))
                                    : TextButton(
                                        onPressed: () => _showReturnDialog(context, ref, e),
                                        style: TextButton.styleFrom(foregroundColor: context.colors.successGreen),
                                        child: const Text('Mark Returned'),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Returned'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Package: ${entry.packageId.substring(0, 8).toUpperCase()}',
              style: TextStyle(color: context.colors.textSecondary)),
          Text('Reason: ${entry.holdReason}',
              style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w600)),
          const Gap(16),
          TextField(controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Return Notes (optional)'), maxLines: 2),
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
      ),
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
      child: Row(children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        const Gap(10),
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}
