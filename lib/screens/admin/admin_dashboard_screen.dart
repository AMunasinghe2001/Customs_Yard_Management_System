import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/status_chip.dart';


// Dashboard providers now moved to lib/core/providers.dart for shared access

class AdminDashboardScreen extends ConsumerWidget {
  /// The nav route to highlight. Admins land here via `/admin`; officers reuse
  /// this exact dashboard from `/dashboard` (one shared dashboard for both), so
  /// the route is passed in to keep the correct nav item highlighted.
  final String currentRoute;
  const AdminDashboardScreen({super.key, this.currentRoute = '/admin'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkgStats = ref.watch(dashboardStatsProvider);
    // Yard-scoped: only the admin's own yard (officers + admins), never
    // head-office (DC/SDDC) or other yards leaked by the cross-yard policy.
    final profiles = ref.watch(myYardProfilesProvider);
    final online = ref.watch(myYardOnlineProfilesProvider);
    final myYard = ref.watch(currentProfileProvider)?.yard;

    return AppShell(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // â”€â”€ Header: title + date Â· yard badge + staff stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          ref.watch(currentProfileProvider)?.isAdmin == true
                              ? 'Admin Dashboard'
                              : 'Dashboard',
                          style: Theme.of(context).textTheme.headlineLarge),
                      Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(DateTime.now()),
                          style:
                              TextStyle(color: context.colors.textSecondary)),
                    ],
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _yardBadge(context, myYard),
                    const Gap(12),
                    _buildHeaderStats(context, online, profiles),
                  ]),
                ],
              ).animate().fadeIn(),
              const Gap(20),

              // â”€â”€ Operational stat cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              pkgStats
                  .when(
                    loading: () => const _StatsLoadingRow(),
                    error: (e, _) => ErrorView(
                        error: e,
                        onRetry: () => ref.refresh(dashboardStatsProvider)),
                    // Plain row: every card now has the SAME 2-line content
                    // (the W/H Rate card was flattened to match _StatCard), so
                    // they line up at equal height without any stretch/
                    // IntrinsicHeight wrapper (which broke layout because the
                    // cards contain Expanded children).
                    data: (data) => Row(
                      children: [
                        Expanded(
                            child: _StatCard(
                                label: 'Forfeited Today',
                                value: "${data['forfeit'] ?? 0}",
                                icon: Icons.gavel_rounded,
                                color: context.colors.dangerRed)),
                        const Gap(16),
                        Expanded(
                            child: _StatCard(
                                label: 'Abandoned Today',
                                value: "${data['abandon'] ?? 0}",
                                icon: Icons.inventory_2_rounded,
                                color: context.colors.heldOrange)),
                        const Gap(16),
                        Expanded(
                            child: _StatCard(
                                label: 'Destroyed Today',
                                value: "${data['destroy'] ?? 0}",
                                icon: Icons.local_fire_department_rounded,
                                color: context.colors.warningAmber)),
                        const Gap(16),
                        Expanded(
                            child: _StatCard(
                                label: 'Released Today',
                                value: "${data['release'] ?? 0}",
                                icon: Icons.check_circle_rounded,
                                color: context.colors.successGreen)),
                        const Gap(16),
                        // Current per-day storage rate (headline) with the live
                        // total accruing across all held goods as the subtitle.
                        Expanded(child: _WarehouseChargeCard(ref: ref)),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 100.ms)
                  .slideY(begin: 0.1),

              const Gap(20),

              // â”€â”€ Body: two columns that fill the height (minimal scrolling) â”€
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: forfeit â†’ disposal lifecycle (fills the column)
                    Expanded(
                      flex: 5,
                      child: _ForfeitLifecycleSection(ref: ref)
                          .animate()
                          .fadeIn(delay: 200.ms)
                          .slideY(begin: 0.1),
                    ),
                    const Gap(24),
                    // Right: capacity + online staff (fixed) then recent
                    // activity expands to absorb the remaining height.
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOnlineOfficersList(context, ref, online, myYard)
                              .animate()
                              .fadeIn(delay: 300.ms)
                              .slideY(begin: 0.1),
                          const Gap(20),
                          Expanded(
                            child: _RecentActivitySection(ref: ref)
                                .animate()
                                .fadeIn(delay: 340.ms)
                                .slideY(begin: 0.1),
                          ),
                        ],
                      ),
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

  // Yard chip shown in the header so the admin knows the scope of everything
  // on this dashboard.
  Widget _yardBadge(BuildContext context, String? yard) {
    final gold = context.colors.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warehouse_rounded, color: gold, size: 16),
        const Gap(8),
        Text(yardName(yard),
            style: TextStyle(
                color: gold, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
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
              'In Yard',
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label,
            style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildOnlineOfficersList(BuildContext context, WidgetRef ref,
      AsyncValue<List<ProfileModel>> online, String? yard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Online in ${yardName(yard)}',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: context.colors.successGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: context.colors.successGreen.withOpacity(0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: context.colors.successGreen,
                    shape: BoxShape.circle),
              ),
              const Gap(6),
              Text(
                '${online.maybeWhen(data: (d) => d.length, orElse: () => 0)} online',
                style: TextStyle(
                    color: context.colors.successGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ),
        const Gap(10),
        Container(
          height: 156,
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: online.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.refresh(myYardOnlineProfilesProvider)),
            data: (list) => list.isEmpty
                ? _buildEmptyOnline(context)
                : Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.borderColor.withOpacity(0.6),
                          indent: 58),
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
          Text('No one currently online in this yard',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

}

// â”€â”€ Reusable bits â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// A left-aligned section title with an optional trailing widget (count chip,
/// "View all" link). Keeps every section header on the dashboard consistent.
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: context.colors.primaryGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Gap(10),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// An operational stat card: gold-on-tinted icon box + big value + label, with
/// a faint accent gradient. Used for the four headline metrics.
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.08),
            context.colors.cardDark,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
                const Gap(2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineMemberTile extends StatelessWidget {
  final ProfileModel profile;
  const _OnlineMemberTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    final hasImage = profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty;
    final isRemote = hasImage && profile.profileImageUrl!.startsWith('http');

    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colors.primaryGold.withOpacity(0.1),
          border: Border.all(
            color: context.colors.primaryGold.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: ClipOval(
          child: hasImage
              ? (isRemote
                  ? Image.network(
                      profile.profileImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitials(context),
                    )
                  : Image.file(
                      File(profile.profileImageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildInitials(context),
                    ))
              : _buildInitials(context),
        ),
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

  Widget _buildInitials(BuildContext context) {
    return Center(
      child: Text(
        profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : 'U',
        style: TextStyle(
          color: context.colors.primaryGold,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
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

/// Forfeit â†’ disposal lifecycle overview: appeal status, disposal-request
/// breakdown, final outcomes (tender sold / unsold / destroyed) and the next
/// scheduled tender-sale date. Scoped to the admin's yard.
class _ForfeitLifecycleSection extends StatelessWidget {
  final WidgetRef ref;
  const _ForfeitLifecycleSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(forfeitLifecycleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Forfeit & Disposal Lifecycle'),
        const Gap(12),
        Expanded(
          child: async.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.refresh(forfeitLifecycleProvider)),
            data: (d) {
              final next = d['nextTenderSaleDate'] as String?;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LifecycleGroup(
                      title: 'Appeal Directorate',
                      icon: Icons.gavel_rounded,
                      tiles: [
                        _LifecycleTile(
                            label: 'On Appeal Hold',
                            value: '${d['appealHold'] ?? 0}',
                            color: context.colors.heldOrange,
                            icon: Icons.pan_tool_rounded),
                        _LifecycleTile(
                            label: 'Decision Received',
                            value: '${d['appealDecided'] ?? 0}',
                            color: context.colors.accentLightBlue,
                            icon: Icons.how_to_reg_rounded),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Disposal Requests (Central Disposal)',
                      icon: Icons.local_shipping_rounded,
                      tiles: [
                        _LifecycleTile(
                            label: 'Sent for Sale',
                            value: '${d['requestedSale'] ?? 0}',
                            color: context.colors.primaryGold,
                            icon: Icons.sell_rounded),
                        _LifecycleTile(
                            label: 'Sent for Destruction',
                            value: '${d['requestedDestruction'] ?? 0}',
                            color: context.colors.dangerRed,
                            icon: Icons.delete_forever_rounded),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Final Outcomes',
                      icon: Icons.flag_rounded,
                      tiles: [
                        _LifecycleTile(
                            label: 'Tender Sold',
                            value: '${d['tenderSold'] ?? 0}',
                            color: context.colors.successGreen,
                            icon: Icons.check_circle_rounded),
                        _LifecycleTile(
                            label: 'Unsold',
                            value: '${d['tenderUnsold'] ?? 0}',
                            color: context.colors.textMuted,
                            icon: Icons.remove_shopping_cart_rounded),
                        _LifecycleTile(
                            label: 'Destroyed',
                            value: '${d['destroyed'] ?? 0}',
                            color: context.colors.warningAmber,
                            icon: Icons.local_fire_department_rounded),
                      ],
                    ),
                    const Gap(16),
                    _NextTenderSaleBanner(date: next),
                    const Gap(20),
                    // Warehouse capacity sits directly under the Tender Sale
                    // banner in this column.
                    _WarehouseCapacitySection(ref: ref),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A titled group of lifecycle stat tiles laid out in a wrap.
class _LifecycleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> tiles;
  const _LifecycleGroup(
      {required this.title, required this.icon, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 15, color: context.colors.textMuted),
          const Gap(8),
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textMuted)),
        ]),
        const Gap(8),
        Wrap(spacing: 12, runSpacing: 12, children: tiles),
      ],
    );
  }
}

/// A single lifecycle metric tile (icon + big number + label).
class _LifecycleTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _LifecycleTile(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      // Fixed height (tall enough for a TWO-line label) so every tile in a row
      // is the same size regardless of whether its label wraps to one or two
      // lines (e.g. "Sent for Destruction" vs "Sent for Sale").
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.0)),
                const Gap(2),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Highlights the next scheduled tender-sale date (or a calm "none scheduled").
class _NextTenderSaleBanner extends StatelessWidget {
  final String? date;
  const _NextTenderSaleBanner({required this.date});

  @override
  Widget build(BuildContext context) {
    final has = date != null && date!.isNotEmpty;
    final gold = context.colors.primaryGold;
    String pretty = 'â€”';
    if (has) {
      final parsed = DateTime.tryParse(date!);
      pretty = parsed != null
          ? DateFormat('EEEE, d MMMM yyyy').format(parsed)
          : date!;
    }
    return ConstrainedBox(
      // Narrower than the full column width so it doesn't dominate the section.
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: gold.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.event_available_rounded, color: gold, size: 20),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEXT TENDER SALE',
                  style: TextStyle(
                      color: gold,
                      fontSize: 10,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800)),
              const Gap(2),
              Text(has ? pretty : 'No tender sale scheduled',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ]),
    ),
    );
  }
}

/// Headline stat card for storage charges: shows the current per-day rate
/// (e.g. "LKR 40 / day") as the big number, with the live total accruing across
/// all goods still held in the yard shown underneath as a subtitle.
class _WarehouseChargeCard extends StatelessWidget {
  final WidgetRef ref;
  const _WarehouseChargeCard({required this.ref});

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final rate = ref.watch(currentStorageRateProvider);
    final accrued = ref.watch(currentWarehouseChargeProvider);

    final rateText = rate.maybeWhen(
        data: (r) => 'LKR ${NumberFormat('#,##0').format(r)}',
        orElse: () => 'â€¦');
    final accruedText = accrued.maybeWhen(
        data: (c) => 'Accrued: LKR ${NumberFormat('#,##0').format(c)}',
        orElse: () => 'Accruedâ€¦');

    return Container(
      // Match _StatCard padding exactly so this card is the same height.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gold.withOpacity(0.10), context.colors.cardDark],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.payments_rounded, color: gold, size: 22),
          ),
          const Gap(14),
          // Two equal halves so this card matches the other stat cards' height:
          // the per-day rate (headline) and the live accrued total. Each half is
          // a value + label line, mirroring [_StatCard].
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(rateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.1)),
                    ),
                    const Gap(3),
                    Text('/day',
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const Gap(2),
                Text('Current W/H Rate · $accruedText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-warehouse capacity utilisation for the admin's yard, shown as compact
/// fill bars so the admin can see at a glance which warehouses are filling up.
class _WarehouseCapacitySection extends StatelessWidget {
  final WidgetRef ref;
  const _WarehouseCapacitySection({required this.ref});

  Color _fillColor(BuildContext context, double percent) {
    if (percent >= 90) return context.colors.dangerRed;
    if (percent >= 70) return context.colors.heldOrange;
    return context.colors.successGreen;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(yardWarehouseCapacityProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Warehouse Capacity'),
        const Gap(10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: async.when(
            loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.refresh(yardWarehouseCapacityProvider)),
            data: (rows) {
              if (rows.isEmpty) {
                return _emptyHint(context, Icons.warehouse_rounded,
                    'No active warehouse stock in your yard');
              }
              // Cap the panel height; scroll if a yard has many warehouses.
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Gap(14),
                        _capacityRow(context, rows[i]),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _capacityRow(BuildContext context, Map<String, dynamic> r) {
    final used = r['used'] as int;
    final capacity = r['capacity'] as int;
    final percent = (r['percent'] as double);
    final color = _fillColor(context, percent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(r['warehouseName'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            const Gap(8),
            Text('$used / $capacity',
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 11.5)),
            const Gap(8),
            Text('${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const Gap(6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: context.colors.surfaceDark,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Today's package activity timeline (forfeit / release / destroy / etc.) so
/// the admin sees what's been happening in the yard at a glance.
class _RecentActivitySection extends StatelessWidget {
  final WidgetRef ref;
  const _RecentActivitySection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recentPackagesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recent Activity'),
        const Gap(10),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.colors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(recentPackagesProvider)),
              data: (list) {
                if (list.isEmpty) {
                  return _emptyHint(context, Icons.history_rounded,
                      'No package activity today');
                }
                return Scrollbar(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: context.colors.borderColor.withOpacity(0.5)),
                    itemBuilder: (ctx, i) => _activityTile(context, list[i]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _activityTile(BuildContext context, PackageModel p) {
    final (icon, color) = _statusVisual(context, p.status);
    // Custom row (not ListTile) so the trailing chip + time never overflow the
    // tile's fixed dense height — we control the layout entirely here.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.14),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.srNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(p.consigneeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          const Gap(10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(status: p.status, fixedWidth: 96),
              const Gap(2),
              Text(DateFormat('HH:mm').format(p.updatedAt.toLocal()),
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  /// Icon + colour for the leading badge, matching [StatusChip]'s grouping.
  (IconData, Color) _statusVisual(BuildContext context, String status) {
    switch (status) {
      case 'cleared':
      case 'returned':
        return (Icons.check_circle_rounded, context.colors.successGreen);
      case 'held':
      case 'detained':
      case 'Detain':
        return (Icons.pan_tool_rounded, context.colors.heldOrange);
      case 'Forfeit':
      case 'Forfiet':
      case 'forfeit':
      case 'forfiet':
      case 'forfeited':
      case 'confiscated':
        return (Icons.gavel_rounded, context.colors.dangerRed);
      case 'Abandoned':
      case 'abandoned':
        return (Icons.inventory_2_rounded, const Color(0xFF9E9E9E));
      case 'Re-export':
      case 're-export':
        return (Icons.flight_takeoff_rounded, const Color(0xFF00ACC1));
      case 'Destroy':
      case 'destroy':
        return (Icons.local_fire_department_rounded, const Color(0xFFE64A19));
      case 'inspecting':
        return (Icons.search_rounded, context.colors.warningAmber);
      default:
        return (Icons.inventory_rounded, context.colors.textMuted);
    }
  }
}

/// Shared "nothing here yet" placeholder for the dashboard panels.
Widget _emptyHint(BuildContext context, IconData icon, String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.textMuted, size: 28),
          const Gap(8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12.5)),
        ],
      ),
    ),
  );
}
