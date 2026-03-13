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
import '../../widgets/status_chip.dart';

final dashboardStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final all = await ref.read(packageServiceProvider).getAllPackages();
  return all.take(10).toList();
});

final warehouseStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(warehouseServiceProvider).getWarehouseStats();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final recent = ref.watch(recentPackagesProvider);
    final warehouseStats = ref.watch(warehouseStatsProvider);
    final profile = ref.watch(currentProfileProvider);

    return AppShell(
      currentRoute: profile?.isAdmin == true ? '/admin' : '/dashboard',
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
                error: (e, _) => Text('Error: $e', style: TextStyle(color: context.colors.dangerRed)),
                data: (data) => IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _StatCard(label: 'Total Today', value: "${data['total'] ?? 0}",
                        icon: Icons.inventory_2_rounded, color: context.colors.accentLightBlue)
                        .animate().slideY(begin: 0.3, duration: 400.ms).fadeIn()),
                      const Gap(16),
                      Expanded(child: _StatCard(label: 'Cleared', value: "${data['cleared'] ?? 0}",
                        icon: Icons.check_circle_rounded, color: context.colors.successGreen)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 100.ms).fadeIn()),
                      const Gap(16),
                      Expanded(child: _StatCard(label: 'Held in SR', value: "${data['held'] ?? 0}",
                        icon: Icons.warehouse_rounded, color: context.colors.heldOrange)
                        .animate().slideY(begin: 0.3, duration: 400.ms, delay: 200.ms).fadeIn()),
                      const Gap(16),
                      Expanded(
                        child: warehouseStats.when(
                          loading: () => _StatCard(label: 'SR Warehouses', value: '—',
                              icon: Icons.warehouse_rounded, color: context.colors.accentBlue),
                          error: (_, __) => _StatCard(label: 'SR Warehouses', value: 'Err',
                              icon: Icons.warehouse_rounded, color: context.colors.dangerRed),
                          data: (ws) => _StatCard(
                            label: 'SR-W01 Active',
                            value: "${ws['SR-W01'] ?? 0}",
                            subLabel: "W02: ${ws['SR-W02'] ?? 0}  W03: ${ws['SR-W03'] ?? 0}",
                            icon: Icons.warehouse_rounded,
                            color: context.colors.accentBlue,
                          ),
                        ),
                      ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 300.ms).fadeIn(),
                    ],
                  ),
                ),
              ),
              const Gap(28),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Packages', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(onPressed: () => context.go('/packages'), child: const Text('View All →')),
                ],
              ),
              const Gap(12),
              recent.when(
                loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
                error: (e, _) => Text('Error: $e'),
                data: (packages) => _RecentPackagesTable(packages: packages),
              ),
            ],
          ),
        ),
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
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.subLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 24),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
                Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
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
      decoration: BoxDecoration(
        color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('SR Number')),
                    DataColumn(label: Text('Consignee')),
                    DataColumn(label: Text('Origin')),
                    DataColumn(label: Text('Items')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Date')),
                  ],
                  rows: packages.map((p) => DataRow(cells: [
                    DataCell(Text(p.srNumber,
                        style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600))),
                    DataCell(Text(p.consigneeName)),
                    DataCell(Text(p.originCountry)),
                    DataCell(Text('${p.totalItemCount}')),
                    DataCell(StatusChip(status: p.status)),
                    DataCell(Text(DateFormat('dd/MM/yy HH:mm').format(p.createdAt))),
                  ])).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
