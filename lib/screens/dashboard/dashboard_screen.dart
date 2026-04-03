import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';
import 'package:data_table_2/data_table_2.dart';

final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final all = await ref.read(packageServiceProvider).getAllPackages();
  return all.take(10).toList();
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

double? _latestStorageRate(Map<DateTime, double>? rates) {
  if (rates == null || rates.isEmpty) return null;
  final latestEntry = rates.entries.reduce(
    (a, b) => a.key.isAfter(b.key) ? a : b,
  );
  return latestEntry.value;
}

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
    final storageRate = _latestStorageRate(
      ref.watch(storageRateProvider).valueOrNull,
    );
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
                            label: 'Seized Today',
                            value: "${data['seized'] ?? 0}",
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFEF5350),
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Returned (Cleared)',
                            value: "${data['cleared'] ?? 0}",
                            icon: Icons.check_circle_rounded,
                            color: context.colors.successGreen,
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 100.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Held in SR',
                            value: "${data['held'] ?? 0}",
                            icon: Icons.warehouse_rounded,
                            color: context.colors.heldOrange,
                            small: true,
                          ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 200.ms).fadeIn(),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _StatCard(
                            label: 'Warehouse Charges',
                            value: storageRate != null
                                ? 'LKR ${storageRate.toStringAsFixed(2)}'
                                : 'LKR 0.00',
                            icon: Icons.payment_rounded,
                            color: context.colors.accentLightBlue,
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
                    // LEFT COLUMN: Quick Actions
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildOfficerQuickActions(context),
                          ],
                        ),
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
                              Text('Recent Packages',
                                  style: Theme.of(context).textTheme.titleLarge),
                              TextButton(
                                  onPressed: () => context.go('/packages'),
                                  child: const Text('View All →')),
                            ],
                          ),
                          const Gap(8),
                          Expanded(
                            child: recent.when(
                              loading: () => const Center(
                                  child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: CircularProgressIndicator())),
                              error: (e, _) => ErrorView(
                                  error: e,
                                  onRetry: () =>
                                      ref.refresh(recentPackagesProvider)),
                              data: (packages) =>
                                  _RecentPackagesTable(packages: packages),
                            ),
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
    final storageRate = _latestStorageRate(
      ref.watch(storageRateProvider).valueOrNull,
    );
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
                      child: _StatCard(label: 'Seized Today', value: "${data['seized'] ?? 0}",
                        icon: Icons.warning_amber_rounded, color: const Color(0xFFEF5350))
                        .animate().slideY(begin: 0.3, duration: 400.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Returned (Cleared)', value: "${data['cleared'] ?? 0}",
                        icon: Icons.check_circle_rounded, color: context.colors.successGreen)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 100.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Held in SR', value: "${data['held'] ?? 0}",
                        icon: Icons.warehouse_rounded, color: context.colors.heldOrange)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 200.ms).fadeIn(),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 180),
                      child: _StatCard(label: 'Warehouse Charges', 
                        value: storageRate != null
                            ? 'LKR ${storageRate.toStringAsFixed(2)}'
                            : 'LKR 0.00',
                        icon: Icons.payment_rounded, color: context.colors.accentLightBlue)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 300.ms).fadeIn(),
                    ),
                  ],
                ),
              ),
              const Gap(28),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Packages', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(onPressed: () => context.go('/packages'), child: const Text('View All →')),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
              const Gap(12),
              recent.when(
                loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.refresh(recentPackagesProvider)),
                data: (packages) => SizedBox(
                  height: 400,
                  child: _RecentPackagesTable(packages: packages),
                ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

class _RecentPackagesTable extends StatelessWidget {
  final List<PackageModel> packages;
  const _RecentPackagesTable({required this.packages});

  @override
  Widget build(BuildContext context) {
    if (packages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.borderColor),
        ),
        child: Center(child: Text('No packages inspected yet today',
            style: TextStyle(color: context.colors.textMuted))),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
        child: DataTable2(
          columnSpacing: 12,
          horizontalMargin: 12,
          minWidth: 600,
          fixedTopRows: 1,
          isVerticalScrollBarVisible: true,
          isHorizontalScrollBarVisible: false,
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          headingRowColor: WidgetStateProperty.all(Colors.transparent),
          columns: [
            DataColumn2(label: Text('SR Number', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)), size: ColumnSize.M),
            DataColumn2(label: Text('Declarant', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)), size: ColumnSize.L),
            DataColumn2(label: Text('Item Name', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)), size: ColumnSize.L),
            DataColumn2(label: Text('Cusdec No', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)), size: ColumnSize.M),
            DataColumn2(label: Center(child: Text('Status', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold))), size: ColumnSize.S, fixedWidth: 100),
            DataColumn2(label: Text('Warehouse', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)), size: ColumnSize.M),
            DataColumn2(label: Center(child: Text('Date', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold))), size: ColumnSize.S, fixedWidth: 100),
          ],
          rows: packages.map((p) => DataRow(cells: [
            DataCell(Text(p.srNumber,
                style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600))),
            DataCell(Text(p.declarantName ?? '-', overflow: TextOverflow.ellipsis)),
            DataCell(Text(p.items.isNotEmpty ? p.items.first.itemName : p.description ?? '-', overflow: TextOverflow.ellipsis)),
            DataCell(Text(p.cusdecNo ?? '-', overflow: TextOverflow.ellipsis)),
            DataCell(Center(child: StatusChip(status: p.status))),
            DataCell(Text(p.warehouseEntries.isNotEmpty ? p.warehouseEntries.first.warehouseCode : '-')),
            DataCell(Center(child: Text(DateFormat('dd/MM/yy').format(p.createdAt)))),
          ])).toList(),
        ),
    );
  }
}
