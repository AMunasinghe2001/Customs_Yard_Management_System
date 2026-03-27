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

// Reuse providers from DashboardScreen
final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {   
  return await ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);
  final all = await ref.read(packageServiceProvider).getAllPackages(since: startOfDay);
  return all.take(10).toList();
});

final categoryZoneSummaryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(warehouseServiceProvider).getCategoryZoneCombinedSummary();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgStats = ref.watch(dashboardStatsProvider);
    final recent = ref.watch(recentPackagesProvider);
    final profiles = ref.watch(allProfilesProvider);
    final online = ref.watch(onlineProfilesProvider);

    return AppShell(
      currentRoute: '/admin',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
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
                      Text('Admin Dashboard',
                          style: Theme.of(context).textTheme.headlineLarge),
                      Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(DateTime.now()),
                          style:
                              TextStyle(color: context.colors.textSecondary)),
                    ],
                  ),
                  _buildHeaderStats(context, online, profiles),
                ],
              ).animate().fadeIn(),
              const Gap(16),

              // TOP SECTION: Operational Stats
              pkgStats
                  .when(
                    loading: () => const _StatsLoadingRow(),
                    error: (e, _) => ErrorView(
                        error: e,
                        onRetry: () => ref.refresh(dashboardStatsProvider)),
                    data: (data) => Row(
                      children: [
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Seized Today',
                                "${data['seized'] ?? 0}",
                                Icons.gavel_rounded,
                                context.colors.dangerRed,
                                small: true)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Returned (Cleared)',
                                "${data['cleared'] ?? 0}",
                                Icons.check_circle_rounded,
                                context.colors.successGreen,
                                small: true)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Held in SR',
                                "${data['held'] ?? 0}",
                                Icons.report_problem_rounded,
                                context.colors.heldOrange,
                                small: true)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Warehouse Charges',
                                "LKR ${(data['storageRate'] ?? 0.0).toStringAsFixed(2)}",
                                Icons.account_balance_wallet_rounded,
                                context.colors.accentLightBlue,
                                small: true)),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 100.ms)
                  .slideY(begin: 0.1),

              const Gap(16),

              // MIDDLE & BOTTOM SECTION COMBINED:
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Online Officers & Shortcuts
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildQuickShortcutsGrid(context),
                          const Gap(24),
                          _buildSummaryGrid(context, ref),
                        ],
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
                    ),
                    const Gap(24),
                    // Right Column: Recent Activity
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOnlineOfficersList(context, ref, online),
                          const Gap(24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Recent Package Inspections',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              TextButton(
                                  onPressed: () => context.go('/packages'),
                                  child: const Text('View All Packages →')),
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

  Widget _buildHeaderStats(
      BuildContext context,
      AsyncValue<List<ProfileModel>> online,
      AsyncValue<List<ProfileModel>> all) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerStat(
              context,
              'Online',
              online.maybeWhen(
                  data: (d) => d.length.toString(), orElse: () => '...'),
              context.colors.successGreen),
          const VerticalDivider(width: 32, indent: 8, endIndent: 8),
          _headerStat(
              context,
              'Total Staff',
              all.maybeWhen(
                  data: (d) => d.length.toString(), orElse: () => '...'),
              context.colors.accentBlue),
        ],
      ),
    );
  }

  Widget _headerStat(
      BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label,
            style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildPkgStat(BuildContext context, String label, String value,
      IconData icon, Color color, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: small ? 8 : 12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(small ? 8 : 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: small ? 20 : 24),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: small ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
                Text(label,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: small ? 11 : 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineOfficersList(BuildContext context, WidgetRef ref,
      AsyncValue<List<ProfileModel>> online) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Officers Online',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.colors.successGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                online.maybeWhen(data: (d) => d.length.toString(), orElse: () => '0'),
                style: TextStyle(color: context.colors.successGreen, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const Gap(8),
        Container(
          height: 140, // Reduced height for logs-like feel
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: online.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
                error: e, onRetry: () => ref.refresh(onlineProfilesProvider)),
            data: (list) => list.isEmpty
                ? _buildEmptyOnline(context)
                : Scrollbar(
                  child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.borderColor,
                          indent: 50),
                      itemBuilder: (ctx, i) =>
                          _OnlineMemberTile(profile: list[i]),
                    ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyOnline(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sensors_off_rounded,
              color: context.colors.textMuted, size: 32),
          const Gap(8),
          Text('No officers currently online',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildQuickShortcutsGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Administrative Actions',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const Gap(12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.5,
          children: [
            _shortcut(context, 'Officers', Icons.person_add_rounded,
                () => context.go('/admin/panel?tab=0'),
                color: context.colors.primaryGold),
            _shortcut(context, 'Customs Rules', Icons.gavel_rounded,
                () => context.go('/admin/panel?tab=1'),
                color: context.colors.primaryGold),
            _shortcut(context, 'Categories', Icons.category_rounded,
                () => context.go('/admin/panel?tab=2'),
                color: context.colors.primaryGold),
            _shortcut(context, 'Storage Charges', Icons.payments_rounded,
                () => context.go('/admin/panel?tab=3'),
                color: context.colors.primaryGold),
            _shortcut(context, 'Hold Reasons', Icons.list_alt_rounded,
                () => context.go('/admin/panel?tab=4'),
                color: context.colors.primaryGold),
            _shortcut(context, 'System Logs', Icons.history_rounded,
                () => context.go('/admin/panel?tab=5'),
                color: context.colors.primaryGold),
          ],
        ),
      ],
    );
  }
  Widget _buildSummaryGrid(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: Column(
        key: const ValueKey('category_zone_summary_column'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category & Zone Inventory', 
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Gap(8),
          ref.watch(categoryZoneSummaryProvider).when(
            data: (summary) {
              if (summary.isEmpty) return const SizedBox(height: 100, child: Center(child: Text('No active inventory.')));
              return Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      // Body
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(0),
                          itemCount: summary.length,
                          separatorBuilder: (context, index) => Divider(color: context.colors.borderColor, height: 1),
                          itemBuilder: (context, index) {
                            final s = summary[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                ),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
  Widget _shortcut(
      BuildContext context, String label, IconData icon, VoidCallback onTap,
      {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: color ?? context.colors.accentLightBlue, size: 18),
              const Gap(8),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
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
    if (stats.isEmpty)
      return const Text('No active inventory.', style: TextStyle(fontSize: 12));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        children: stats.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key,
                          style: TextStyle(
                              color: context.colors.textPrimary, fontSize: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Text(e.value.toString(),
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _OnlineMemberTile extends StatelessWidget {
  final ProfileModel profile;
  const _OnlineMemberTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: context.colors.primaryGold.withOpacity(0.1),
        child: Text(profile.fullName[0].toUpperCase(),
            style: TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
      title: Text(profile.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(profile.role.toUpperCase(),
          style: TextStyle(
              color: context.colors.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
      trailing: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
            color: context.colors.successGreen, shape: BoxShape.circle),
      ),
    );
  }
}

class _StatsLoadingRow extends StatelessWidget {
  const _StatsLoadingRow();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
          4,
          (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 16 : 0),
                  height: 60,
                  decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14)),
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
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DataTable2(
          columnSpacing: 12,
          horizontalMargin: 12,
          fixedTopRows: 1,
          headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columns: [
            DataColumn2(
                label: Text('SR Number',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.M),
            DataColumn2(
                label: Text('Consignee',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                size: ColumnSize.L),
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
          rows: packages
              .map((p) => DataRow(cells: [
                    DataCell(Text(p.srNumber,
                        style: TextStyle(
                            color: context.colors.accentLightBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13))),
                    DataCell(Text(p.consigneeName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
                    DataCell(Center(child: StatusChip(status: p.status))),
                    DataCell(Text(
                        DateFormat('dd/MM/yy HH:mm').format(p.createdAt),
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 13))),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}
