import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/empty_table_state.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/tooltip_text.dart';

final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final all = await ref.read(packageServiceProvider).getAllPackages();
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final tomorrowStart = todayStart.add(const Duration(days: 1));
  
  return all.where((p) {
    return (p.createdAt.isAfter(todayStart) || p.createdAt.isAtSameMomentAs(todayStart)) && 
           p.createdAt.isBefore(tomorrowStart);
  }).toList();
});

final warehouseStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(warehouseServiceProvider).getWarehouseStats();
});

final zoneStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(warehouseServiceProvider).getZoneStats();
});

final categoryStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(warehouseServiceProvider).getCategoryStats();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final recent = ref.watch(recentPackagesProvider);
    final profile = ref.watch(currentProfileProvider);
    final isOfficer = profile?.role == 'officer';

    if (isOfficer) {
      return _buildOfficerDashboard(context, ref, stats, recent);
    } else {
      return _buildAdminDashboard(context, ref, stats, recent);
    }
  }

  // ───── OFFICER DASHBOARD (NON-SCROLLING) ─────
  Widget _buildOfficerDashboard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>> stats,
    AsyncValue<List<PackageModel>> recent,
  ) {
    return AppShell(
      currentRoute: '/dashboard',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inspection Dashboard',
                          style: Theme.of(context).textTheme.headlineLarge),
                      Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(DateTime.now()),
                          style:
                              TextStyle(color: context.colors.textSecondary)),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('New Inspection'),
                    onPressed: () => context.go('/inspection'),
                  ),
                ],
              ).animate().fadeIn(),
              const Gap(16),

              // STATS ROW
              stats
                  .when(
                    loading: () => _StatsLoadingRow(),
                    error: (e, _) => ErrorView(
                        error: e,
                        onRetry: () => ref.refresh(dashboardStatsProvider)),
                    data: (data) => Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Forfeited Today',
                            value: "${data['forfeit'] ?? 0}",
                            icon: Icons.gavel_rounded,
                            color: const Color(0xFFEF5350),
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Abandoned Today',
                            value: "${data['abandon'] ?? 0}",
                            icon: Icons.inventory_2_rounded,
                            color: context.colors.heldOrange,
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 100.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Destroyed Today',
                            value: "${data['destroy'] ?? 0}",
                            icon: Icons.local_fire_department_rounded,
                            color: context.colors.warningAmber,
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 200.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Released Today',
                            value: "${data['release'] ?? 0}",
                            icon: Icons.check_circle_rounded,
                            color: context.colors.successGreen,
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 300.ms).fadeIn(),
                        ),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 100.ms)
                  .slideY(begin: 0.1),

              const Gap(16),

              // MAIN CONTENT (2-COLUMN LAYOUT)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT COLUMN: Quick Actions & Inventory
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOfficerQuickActions(context),
                          const Gap(20),
                          Expanded(child: _buildCategoryZoneSummary(context, ref)),
                        ],
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
                    ),
                    const Gap(24),
                    // RIGHT COLUMN: Recent Packages
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Recent Goods',
                                  style: Theme.of(context).textTheme.titleLarge),
                              TextButton(
                                  onPressed: () => context.go('/packages'),
                                  child: const Text('View All →')),
                            ],
                          ),
                          const Gap(8),
                          Expanded(
                            child: _RecentPackagesTable(recent: recent),
                          ),
                        ],
                      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── ADMIN DASHBOARD (SCROLLING) ─────
  Widget _buildAdminDashboard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>> stats,
    AsyncValue<List<PackageModel>> recent,
  ) {
    return AppShell(
      currentRoute: '/dashboard',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard', style: Theme.of(context).textTheme.headlineLarge),
                      Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                          style: TextStyle(color: context.colors.textSecondary)),
                    ],
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('New Inspection'),
                    onPressed: () => context.go('/inspection'),
                  ),
                ],
              ).animate().fadeIn(),
              const Gap(28),

              stats.when(
                loading: () => _StatsLoadingRow(),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.refresh(dashboardStatsProvider)),
                data: (data) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Forfeited Today', value: "${data['forfeit'] ?? 0}",
                        icon: Icons.gavel_rounded, color: const Color(0xFFEF5350))
                        .animate().slideY(begin: 0.3, duration: 400.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Abandoned Today', value: "${data['abandon'] ?? 0}",
                        icon: Icons.inventory_2_rounded, color: context.colors.heldOrange)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 100.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Destroyed Today', value: "${data['destroy'] ?? 0}",
                        icon: Icons.local_fire_department_rounded, color: context.colors.warningAmber)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 200.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Released Today', value: "${data['release'] ?? 0}",
                        icon: Icons.check_circle_rounded, color: context.colors.successGreen)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 300.ms).fadeIn(),
                    ),
                  ],
                ),
              ),
              const Gap(28),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Goods', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(onPressed: () => context.go('/packages'), child: const Text('View All →')),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
              const Gap(12),
              SizedBox(
                height: 400,
                child: _RecentPackagesTable(recent: recent),
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 500.ms).fadeIn(),

              const Gap(32),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inventory by Category', style: Theme.of(context).textTheme.titleMedium),
                        const Gap(12),
                        ref.watch(categoryStatsProvider).when(
                          data: (stats) => _GridSummary(stats: stats, color: Colors.teal),
                          loading: () => const Center(child: LinearProgressIndicator()),
                          error: (e, _) => Text('Error: $e'),
                        ),
                      ],
                    ),
                  ),
                  const Gap(24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zone Occupancy', style: Theme.of(context).textTheme.titleMedium),
                        const Gap(12),
                        ref.watch(zoneStatsProvider).when(
                          data: (stats) => _GridSummary(stats: stats, color: Colors.purple),
                          loading: () => const Center(child: LinearProgressIndicator()),
                          error: (e, _) => Text('Error: $e'),
                        ),
                      ],
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }

  // ───── OFFICER QUICK ACTIONS ─────
  Widget _buildOfficerQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const Gap(12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _actionCard(context, 'New Inspection', Icons.add_box_rounded,
                () => context.go('/inspection'),
                color: context.colors.primaryGold),
            const Gap(10),
            _actionCard(context, 'Search Packages', Icons.search_rounded,
                () => context.go('/packages'),
                color: context.colors.accentBlue),
            const Gap(10),
            _actionCard(context, 'View Warehouses', Icons.warehouse_rounded,
                () => context.go('/warehouses'),
                color: context.colors.heldOrange),
          ],
        ),
      ],
    );
  }

  // ───── CATEGORY & ZONE INVENTORY ─────
  Widget _buildCategoryZoneSummary(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category & Zone Inventory', 
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const Gap(12),
        Expanded(
          child: ref.watch(categoryZoneSummaryProvider).when(
            data: (summary) {
              if (summary.isEmpty) return const SizedBox(height: 100, child: Center(child: Text('No active inventory.')));
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Column(
                  children: [
                    // Fixed Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceDark,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                        border: Border(bottom: BorderSide(color: context.colors.borderColor)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 5, child: Text('Category', style: TextStyle(fontSize: 11, color: context.colors.primaryGold, fontWeight: FontWeight.bold))),
                          Expanded(flex: 5, child: Text('W/H - Zone', style: TextStyle(fontSize: 11, color: context.colors.primaryGold, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: context.colors.primaryGold, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    // Scrollable Body
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(0),
                        itemCount: summary.length,
                        separatorBuilder: (context, index) => Divider(color: context.colors.borderColor, height: 1),
                        itemBuilder: (context, index) {
                          final s = summary[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(flex: 5, child: Text(s['category'], style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                                Expanded(flex: 5, child: Text('${s['warehouse']} - ${s['zone']}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                                Expanded(flex: 2, child: Text(s['count'].toString(), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.colors.accentLightBlue))),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(child: LinearProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ),
      ],
    );
  }

  // ───── ACTION CARD WIDGET ─────
  Widget _actionCard(BuildContext context, String label, IconData icon,
      VoidCallback onTap,
      {required Color color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Gap(12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

}

class _GridSummary extends StatelessWidget {
  final Map<String, int> stats;
  final Color color;
  const _GridSummary({required this.stats, required this.color});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const Text('No active inventory data available.');
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        children: stats.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key, style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(e.value.toString(), 
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subLabel;
  final IconData icon;
  final Color color;
  final bool small;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.subLabel, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(small ? 16 : 20),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(small ? 10 : 12),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: small ? 20 : 24),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: small ? 20 : 26, fontWeight: FontWeight.w800, height: 1.1)),
                Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: small ? 11 : 13)),
                if (subLabel != null)
                  Text(subLabel!, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsLoadingRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) => Expanded(
        child: Container(
          margin: EdgeInsets.only(right: i < 3 ? 16 : 0),
          height: 90,
          decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14)),
          child: Center(child: CircularProgressIndicator(color: context.colors.primaryGold, strokeWidth: 2)),
        ),
      )),
    );
  }
}

class _RecentPackagesTable extends ConsumerWidget {
  final AsyncValue<List<PackageModel>> recent;
  const _RecentPackagesTable({required this.recent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DataTable2(
          columnSpacing: 8,
          horizontalMargin: 8,
          fixedTopRows: 1,
          empty: const EmptyTableState(message: 'No inspections recorded today'),
          isVerticalScrollBarVisible: true,
          isHorizontalScrollBarVisible: false,
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
          columns: [
            DataColumn2(
                label: Text('SR Number',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.M),
            DataColumn2(
                label: Text('Goods Name',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.L),
            DataColumn2(
                label: Text('Qty',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.S,
                fixedWidth: 60),
            DataColumn2(
                label: Center(
                  child: Text('Status',
                      style: TextStyle(
                          color: context.colors.primaryGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                size: ColumnSize.S,
                fixedWidth: 100),
            DataColumn2(
                label: Text('Date',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.M),
          ],
          rows: recent.when(
            data: (packages) {
              if (packages.isEmpty) {
                return [];
              }
              return packages.expand((p) {
                if (p.items.isEmpty) {
                  return [
                    DataRow(cells: [
                      DataCell(TooltipText(p.srNumber,
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                      const DataCell(TooltipText('No items', style: TextStyle(fontSize: 13))),
                      const DataCell(TooltipText('0',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold))),
                      DataCell(Center(child: StatusChip(status: p.status))),
                      DataCell(TooltipText(
                          DateFormat('dd/MM HH:mm').format(p.updatedAt),
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 13))),
                    ])
                  ];
                }

                return p.items.map((item) {
                  String effectiveStatus =
                      (item.status != null && item.status != 'pending')
                          ? item.status!
                          : p.status;

                  return DataRow(cells: [
                    DataCell(TooltipText(p.srNumber,
                        style: TextStyle(
                            color: context.colors.accentLightBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13))),
                    DataCell(TooltipText(item.itemName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
                    DataCell(TooltipText(item.quantity.toString(),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold))),
                    DataCell(Center(child: StatusChip(status: effectiveStatus))),
                    DataCell(TooltipText(DateFormat('dd/MM HH:mm').format(p.updatedAt),
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 13))),
                  ]);
                });
              }).toList();
            },
            loading: () => [
              const DataRow(cells: [
                DataCell(TooltipText('')),
                DataCell(SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
                DataCell(TooltipText('')),
                DataCell(TooltipText('')),
                DataCell(TooltipText('')),
              ])
            ],
            error: (e, _) => [
              DataRow(cells: [
                const DataCell(TooltipText('Error')),
                DataCell(TooltipText(e.toString())),
                const DataCell(TooltipText('')),
                const DataCell(TooltipText('')),
                const DataCell(TooltipText('')),
              ])
            ],
          ),
        ),
      ),
    );
  }
}
