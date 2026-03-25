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
final dashboardStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.read(packageServiceProvider).getDashboardStats();
});

final recentPackagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final all = await ref.read(packageServiceProvider).getAllPackages();
  return all.take(10).toList();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgStats = ref.watch(dashboardStatsProvider);
    final recent = ref.watch(recentPackagesProvider);
    final profiles = ref.watch(allProfilesProvider);
    final online = ref.watch(onlineProfilesProvider);
    final rules = ref.watch(allRulesProvider);

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
                                'Total Today',
                                "${data['total'] ?? 0}",
                                Icons.inventory_2_rounded,
                                context.colors.accentLightBlue)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Cleared',
                                "${data['cleared'] ?? 0}",
                                Icons.check_circle_rounded,
                                context.colors.successGreen)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Held in SR',
                                "${data['held'] ?? 0}",
                                Icons.report_problem_rounded,
                                context.colors.heldOrange)),
                        const Gap(12),
                        Expanded(
                            child: _buildPkgStat(
                                context,
                                'Active Rules',
                                rules.maybeWhen(
                                    data: (d) => d
                                        .where((r) => r.isActive)
                                        .length
                                        .toString(),
                                    orElse: () => '...'),
                                Icons.gavel_rounded,
                                context.colors.warningAmber)),
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
                          Expanded(
                            child:
                                _buildOnlineOfficersList(context, ref, online),
                          ),
                          const Gap(16),
                          _buildQuickShortcutsGrid(context),
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
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
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
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
                Text(label,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
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
        Text('Officers Currently Logged In',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const Gap(12),
        Expanded(
          child: Container(
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
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.borderColor,
                          indent: 60),
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
                () => context.go('/admin/panel?tab=0')),
            _shortcut(context, 'Rules', Icons.gavel_rounded,
                () => context.go('/admin/panel?tab=1')),
            _shortcut(context, 'Categories', Icons.category_rounded,
                () => context.go('/admin/panel?tab=2')),
            _shortcut(context, 'Logs', Icons.history_rounded,
                () => context.go('/admin/panel?tab=4')),
            _shortcut(context, 'Charges', Icons.settings_suggest_rounded,
                () => context.go('/admin/panel?tab=3'),
                color: context.colors.primaryGold),
            _shortcut(context, 'Reports', Icons.summarize_rounded,
                () => context.go('/reports'),
                color: context.colors.primaryGold),
          ],
        ),
      ],
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
                label: Text('Status',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
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
                    DataCell(StatusChip(status: p.status)),
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
