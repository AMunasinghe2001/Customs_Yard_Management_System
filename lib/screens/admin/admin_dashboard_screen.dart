import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/status_chip.dart';


// Dashboard providers now moved to lib/core/providers.dart for shared access

class AdminDashboardScreen extends ConsumerStatefulWidget {
  /// The nav route to highlight. Admins land here via `/admin`; officers reuse
  /// this exact dashboard from `/dashboard` (one shared dashboard for both), so
  /// the route is passed in to keep the correct nav item highlighted.
  final String currentRoute;
  const AdminDashboardScreen({super.key, this.currentRoute = '/admin'});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto-recover: if a weak signal made some panels fail, quietly re-fetch
    // them every 25s so they fill in once the connection is back — without the
    // user having to hit refresh. (Online staff self-polls separately.)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted) _refreshAll(silent: true);
    });
  }

  /// One place that reloads everything on the dashboard — used by the single
  /// "Retry" button and by the silent auto-refresh timer.
  void _refreshAll({bool silent = false}) {
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(allProfilesProvider);
    ref.invalidate(myYardProfilesProvider);
    ref.invalidate(forfeitLifecycleProvider);
    ref.invalidate(currentStorageRateProvider);
    ref.invalidate(currentWarehouseChargeProvider);
    ref.invalidate(yardWarehouseCapacityProvider);
    ref.invalidate(recentPackagesProvider);
    if (!silent) ref.invalidate(myYardOnlineProfilesProvider);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pkgStats = ref.watch(dashboardStatsProvider);
    // Yard-scoped: only the admin's own yard (officers + admins), never
    // head-office (DC/SDDC) or other yards leaked by the cross-yard policy.
    final profiles = ref.watch(myYardProfilesProvider);
    final online = ref.watch(myYardOnlineProfilesProvider);
    final myYard = ref.watch(currentProfileProvider)?.yard;
    // ⚠️ The DIRECTORATE that runs this yard, read from the ICT-
    // maintained link table -- never hardcoded, because ICT re-pairs yards
    // and directorates from the portal at run time.
    final myPrefix = ref.watch(myDirectoratePrefixProvider).value;

    return AppShell(
      currentRoute: widget.currentRoute,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: title + date · yard badge + staff stats ──────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ⚠️ The YARD's name, not the role's.
                      //
                      // "Admin Dashboard" said who was looking; every page
                      // under it is filtered to one yard, and which yard
                      // that is was only visible in a badge on the far side
                      // of the header. An officer signed into two yards on
                      // two machines could not tell the screens apart.
                      //
                      // The role has not been dropped -- it is under the
                      // officer's name in the rail, where it says what they
                      // may do rather than what they are looking at.
                      //
                      // ⚠️ The DIRECTORATE leads, the yard's NAME follows:
                      // "CED · Grey Line 1 Dashboard".
                      //
                      // "Admin Dashboard" said who was looking, while every
                      // page under it is filtered to one yard. The yard code
                      // alone was no better: GL1 is meaningless until you
                      // know it belongs to CED, and ICT groups yards under
                      // directorates precisely because that is the division
                      // that matters. So the header names the directorate
                      // and spells the yard out; the badge opposite carries
                      // the directorate alone.
                      //
                      // The prefix arrives a frame late (it is a future), so
                      // the title falls back to the yard name rather than
                      // flashing an empty separator.
                      Text(
                          myYard == null || myYard.isEmpty
                              ? 'Dashboard'
                              : (myPrefix == null || myPrefix.isEmpty
                                  ? '${yardName(myYard)} Dashboard'
                                  : '$myPrefix · ${yardName(myYard)} Dashboard'),
                          style: Theme.of(context).textTheme.headlineLarge),
                      // ⚠️ A LIVE clock, ticking. A dashboard that
                      // auto-refreshes every 25 seconds but shows a time
                      // frozen at whenever it was opened is worse than one
                      // showing no time at all -- the reader trusts it.
                      StreamBuilder<DateTime>(
                        stream: Stream.periodic(
                            const Duration(seconds: 1), (_) => DateTime.now()),
                        initialData: DateTime.now(),
                        builder: (context, snap) => Text(
                          DateFormat('EEEE, d MMMM yyyy · HH:mm:ss')
                              .format(snap.data ?? DateTime.now()),
                          style:
                              TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _yardBadge(context, myYard, myPrefix),
                    const Gap(12),
                    _buildHeaderStats(context, online, profiles),
                  ]),
                ],
              ).animate().fadeIn(),
              const Gap(20),

              // ── ONE consolidated connection banner ──────────────────────
              // If ANY dashboard panel failed to load (usually a weak signal),
              // show a single banner with a single Retry — instead of every
              // panel shouting its own error. Retry reloads them all at once.
              if ([
                pkgStats,
                ref.watch(forfeitLifecycleProvider),
                ref.watch(recentPackagesProvider),
                ref.watch(yardWarehouseCapacityProvider),
              ].any((a) => a.hasError)) ...[
                _ConnectionBanner(
                  onRetry: _refreshAll,
                  // The actual failure, so the banner can say whether this is
                  // the network or a bug. It used to assert "check your
                  // internet connection" for every cause, including plain SQL
                  // errors.
                  error: [
                    pkgStats,
                    ref.watch(forfeitLifecycleProvider),
                    ref.watch(recentPackagesProvider),
                    ref.watch(yardWarehouseCapacityProvider),
                  ].firstWhere((a) => a.hasError).error,
                ),
                const Gap(16),
              ],

              // ── What the yard HOLDS, and what it is WAITING on ────
              //
              // ⚠️ These two rows used to be five "today" cards --
              // forfeited today, abandoned today, destroyed today, released
              // today -- which read 0 on any day nothing happened, which is
              // most days. Meanwhile the yard held 226 items across four
              // Held Goods pages and the dashboard said nothing about them.
              //
              // ⚠️ Grouped and titled, like the lifecycle section below,
              // and drawn with the SAME tile. A dashboard where the top
              // strip and the panel under it use different shapes for the
              // same kind of figure makes the reader work out twice what
              // they are looking at.
              //
              // Every figure opens the page that holds it.
              ref.watch(yardHoldingCountsProvider).when(
                    loading: () => const _StatsLoadingRow(),
                    // Quiet on error -- the single top banner owns the retry.
                    error: (e, _) => const _StatsLoadingRow(),
                    data: (h) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _GroupHeading(
                            title: 'Held in Yard',
                            icon: Icons.warehouse_rounded),
                        const Gap(8),
                        Row(children: [
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Detained',
                                value: '${h['detained'] ?? 0}',
                                color: context.colors.accentLightBlue,
                                icon: Icons.shield_rounded,
                                route: '/detained-packages'),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Abandoned',
                                value: '${h['abandoned'] ?? 0}',
                                color: context.colors.heldOrange,
                                icon: Icons.inventory_2_rounded,
                                route: '/abandoned-packages'),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Other',
                                value: '${h['other'] ?? 0}',
                                color: context.colors.textSecondary,
                                icon: Icons.category_rounded,
                                route: '/other-packages'),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Forfeited',
                                value: '${h['forfeited'] ?? 0}',
                                color: context.colors.dangerRed,
                                icon: Icons.gavel_rounded,
                                route: '/forfeited-packages'),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Perishable — awaiting DG',
                                value: '${h['perishableAwaiting'] ?? 0}',
                                color: context.colors.successGreen,
                                icon: Icons.eco_rounded,
                                route: '/perishable-goods'),
                          ),
                          const Gap(12),
                          // ⚠️ The rate belongs with what the yard HOLDS:
                          // it is the price those goods are accruing at, and
                          // the accrued total sits opposite it in the row
                          // below. Six tiles a row either way, so the two rows
                          // line up column for column.
                          Expanded(child: _StorageRateTile(ref: ref)),
                        ]),
                        const Gap(16),
                        _GroupHeading(
                            title: 'Waiting on Another Directorate',
                            icon: Icons.hourglass_top_rounded),
                        const Gap(8),
                        Row(children: [
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Awaiting Valuation',
                                value: '${h['awaitingValuation'] ?? 0}',
                                color: context.colors.primaryGold,
                                icon: Icons.calculate_rounded),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Re-tenderable',
                                value: '${h['reTenderable'] ?? 0}',
                                color: context.colors.warningAmber,
                                icon: Icons.replay_rounded),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _LifecycleTile(
                                stretch: true,
                                label: 'Unsold — exhausted',
                                value: '${h['exhausted'] ?? 0}',
                                color: context.colors.dangerRed,
                                icon: Icons.block_rounded,
                                route: '/unsold-packages'),
                          ),
                          const Gap(12),
                          // Today's activity, kept as ONE tile rather than
                          // the four cards of zero it used to be.
                          Expanded(
                            child: pkgStats.maybeWhen(
                              data: (d) => _LifecycleTile(
                                  stretch: true,
                                  label: 'Recorded today',
                                  value: '${(d['forfeit'] ?? 0) + (d['abandon'] ?? 0) + (d['destroy'] ?? 0) + (d['release'] ?? 0)}',
                                  color: context.colors.accentLightBlue,
                                  icon: Icons.today_rounded),
                              orElse: () => const SizedBox(height: 76),
                            ),
                          ),
                          const Gap(12),
                          Expanded(child: _AccruedStorageTile(ref: ref)),
                        ]),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 100.ms)
                  .slideY(begin: 0.1),

              const Gap(20),

              // ── Body: two columns that fill the height (minimal scrolling) ─
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
  Widget _yardBadge(BuildContext context, String? yard, String? prefix) {
    final gold = context.colors.primaryGold;
    final code = (yard == null || yard.isEmpty) ? '' : yard;
    final label = code.isEmpty
        ? yardName(yard)
        : (prefix == null || prefix.isEmpty ? code : '$prefix/$code');
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
        // ⚠️ The FULL code -- "CED/GL1". The title beside it spells the
        // yard out in words; this is the same yard written the way it
        // appears on an SR number and in every filter, which is the form an
        // officer types. Either half alone is the one they cannot use.
        Text(label,
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
          height: 172,
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: online.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildEmptyOnline(context),
            data: (list) => list.isEmpty
                ? _buildEmptyOnline(context)
                : Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 2),
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

// ── Reusable bits ─────────────────────────────────────────────────────────

/// A quiet in-panel placeholder shown when a single panel fails to load. It
/// carries NO retry button — the one top banner owns the retry, so the user
/// isn't faced with a dozen separate error boxes.
class _QuietPanelError extends StatelessWidget {
  const _QuietPanelError();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 22, color: context.colors.textMuted.withOpacity(0.6)),
          const Gap(6),
          Text('Couldn\'t load',
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// The single error banner for the whole dashboard. Shown once at the top when
/// any panel fails to load; its one Retry reloads everything.
///
/// ⚠️ It reports WHICH kind of failure happened. It used to say "check your
/// internet connection" unconditionally, so a SQL bug in one panel's query
/// sent the user to look at their network.
class _ConnectionBanner extends StatelessWidget {
  final VoidCallback onRetry;
  final Object? error;
  const _ConnectionBanner({required this.onRetry, this.error});

  /// True only for a genuine unreachable-server error. A Postgres message can
  /// contain the word "connection" without the network being at fault.
  bool get _isNetwork {
    final e = error;
    if (e == null) return true;
    final s = e.toString().toLowerCase();
    if (s.contains('severity.error') ||
        s.contains('does not exist') ||
        s.contains('syntax error') ||
        s.contains('is not a subtype')) {
      return false;
    }
    return e is SocketException ||
        s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('timed out') ||
        s.contains('network is unreachable');
  }

  @override
  Widget build(BuildContext context) {
    final network = _isNetwork;
    final tint =
        network ? context.colors.warningAmber : context.colors.dangerRed;
    final message = network
        ? "Couldn't load some data — the server did not answer. Check that "
            'it is running and that this PC is on the network.'
        : "Couldn't load some data — the database rejected a request. This is "
            'a fault in the app; send the details to ICT.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(network ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
            size: 18, color: tint),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              if (!network && error != null) ...[
                const Gap(4),
                SelectableText(
                  error.toString().replaceFirst(
                      RegExp(r'^Severity\.\w+\s*'), ''),
                  maxLines: 2,
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontFamily: 'monospace',
                      fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const Gap(12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: OutlinedButton.styleFrom(
            foregroundColor: tint,
            side: BorderSide(color: tint.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ]),
    ).animate().fadeIn().slideY(begin: -0.2);
  }
}


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
// ⚠️ `_StatCard` lived here and is gone.
//
// The dashboard drew its top strip with one shape and the lifecycle panel
// under it with another, for the same kind of figure -- a count, a label,
// a colour. Two shapes made the reader work out twice what they were
// looking at, and the strip's cards were the larger of the two.
//
// `_LifecycleTile` now serves both: it gained a `stretch` flag for the
// rows (which are Expanded, where a fixed width fights the layout) and a
// `route`, so a figure opens the page that holds it.

class _OnlineMemberTile extends StatelessWidget {
  final ProfileModel profile;
  const _OnlineMemberTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    final hasImage = profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty;
    final isRemote = hasImage && profile.profileImageUrl!.startsWith('http');

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      minVerticalPadding: 0,
      horizontalTitleGap: 12,
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
      // profile.role only has two yard-scoped values, so every admin read as
      // "ADMIN" here regardless of post -- postShortTitle is the officer's
      // actual post (SDDC, DDC, ...), same as the sidebar under their name.
      subtitle: Text(profile.postShortTitle.toUpperCase(),
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
        // ⚠️ Every figure below counts GOODS, and counts them once.
        //
        // Getting there took several passes. Appeals were counted from
        // forfeits alone, missing the detained, abandoned and other goods
        // that raise them too. Tender rows are ATTEMPTS, so a package that
        // failed four times was counted four times. "Sent for destruction"
        // was structurally always 0 -- destruction never arrives through a
        // disposal request -- and has been removed. And "Forwarded" counted
        // 135 goods of which 113 appeared again under At Tender, so the same
        // lot was on the panel twice.
        const _SectionHeader(title: 'Disposal Operations & Lifecycle'),
        const Gap(12),
        Expanded(
          child: async.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            // Quiet — the single top banner owns the retry.
            error: (e, _) => const _QuietPanelError(),
            data: (d) {
              final next = d['nextTenderSaleDate'] as String?;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LifecycleGroup(
                      title: 'Appeal Directorate · goods',
                      icon: Icons.gavel_rounded,
                      tiles: [
                        // ⚠️ Only goods STILL IN A WAREHOUSE. A ruling on
                        // goods that have since left the yard is history --
                        // the directorate ruled, the yard acted, the goods
                        // are gone. 26 held and 77 decided over all time; 15
                        // and 31 are goods the yard is still holding, and
                        // only those are anybody's outstanding work.
                        _LifecycleTile(
                            label: 'On appeal hold',
                            value: '${d['appealHold'] ?? 0}',
                            color: context.colors.heldOrange,
                            icon: Icons.pan_tool_rounded),
                        _LifecycleTile(
                            label: 'Ruling received',
                            value: '${d['appealDecided'] ?? 0}',
                            color: context.colors.accentLightBlue,
                            icon: Icons.how_to_reg_rounded),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Sent to Central Disposal · goods',
                      icon: Icons.local_shipping_rounded,
                      tiles: [
                        _LifecycleTile(
                            label: 'Sent, awaiting valuation',
                            value: '${d['requestedSale'] ?? 0}',
                            color: context.colors.primaryGold,
                            icon: Icons.sell_rounded),
                        // ⚠️ Forwarded and NOT YET PLACED. "Forwarded"
                        // counted all 135 the yard had ever sent on, of which
                        // 113 were already at tender and counted again in the
                        // group below -- the same goods twice, which is why
                        // the panel could not be read. These 22 are the ones
                        // genuinely in flight: Central Disposal has them and
                        // has not put them anywhere.
                        _LifecycleTile(
                            label: 'Forwarded, not yet placed',
                            value: '${d['forwardedNotPlaced'] ?? 0}',
                            color: context.colors.textMuted,
                            icon: Icons.outbox_rounded),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'At Tender · goods',
                      icon: Icons.storefront_rounded,
                      tiles: [
                        // ⚠️ What the TENDER did: sold, unsold, or held
                        // with nobody having written down which. Three
                        // answers to one question, which is why they sit
                        // together -- and why what happened to the goods
                        // AFTERWARDS is a separate group below rather than
                        // more tiles here.
                        //
                        // Each is per PACKAGE on its LATEST round.
                        // tender_sale_items rows are attempts: a package
                        // that fails four times has four of them, so
                        // counting rows said 109 unsold when 27 lots were.
                        // A package that failed twice and then sold is
                        // SOLD; its failures are history, not an outcome.
                        _LifecycleTile(
                            label: 'Sold at tender',
                            value: '${d['tenderSold'] ?? 0}',
                            color: context.colors.successGreen,
                            icon: Icons.gavel_rounded),
                        _LifecycleTile(
                            label: 'Unsold, needs re-tender',
                            value: '${d['tenderUnsold'] ?? 0}',
                            color: context.colors.textMuted,
                            icon: Icons.remove_shopping_cart_rounded),
                        // ⚠️ The sale has been HELD and nobody has
                        // recorded what happened. Not a result -- a job for
                        // an officer, which is why it has its own tile
                        // instead of being folded into unsold.
                        _LifecycleTile(
                            label: 'Sale held, outcome not recorded',
                            value: '${d['tenderUndecided'] ?? 0}',
                            color: context.colors.dangerRed,
                            icon: Icons.hourglass_empty_rounded),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Sold · goods',
                      icon: Icons.sell_rounded,
                      tiles: [
                        // ⚠️ Sold stands ALONE, not among the other
                        // outcomes. It is the outcome the yard is measured
                        // by and the only one with money behind it, and it
                        // is far the largest -- 76 against 39 and 19. Sat
                        // in a row of three it read as one option among
                        // equals.
                        //
                        // Straight off `disposition_rows`, the same view the
                        // Sold Goods page pages through, so a figure here
                        // and a row count there cannot disagree.
                        _SplitTile(
                            label: 'Sold, all rounds',
                            total: (d['outcomeSoldTotal'] ?? 0) as int,
                            delivered: (d['outcomeSoldDelivered'] ?? 0) as int,
                            pending: (d['outcomeSoldPending'] ?? 0) as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting collection',
                            color: context.colors.successGreen,
                            icon: Icons.sell_rounded,
                            route: '/sold-packages'),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Destroyed · goods',
                      icon: Icons.local_fire_department_rounded,
                      tiles: [
                        // ⚠️ ONE tile, split by WHETHER IT HAS BEEN
                        // DESTROYED -- never by delivery. Nothing is handed
                        // over to be burnt: 23 of the 39 carry no delivery
                        // state at all, so a delivered/pending split read
                        // "9 delivered · 7 awaiting" of 39 and left the
                        // reader to wonder about the other 23. Done or not
                        // done is the question this page answers.
                        //
                        // Off `disposition_rows`, the same view
                        // /destroyed-packages pages through, so the tile and
                        // the page it opens cannot disagree. That is also
                        // why it says 17 where the destruction LIST says 16:
                        // one package reached destroyed on a warehouse entry
                        // tagged [FINAL:DESTROYED] with no destruction_items
                        // row behind it at all.
                        _SplitTile(
                            label: 'Destroyed',
                            total: (d['outcomeDestroyedTotal'] ?? 0) as int,
                            delivered: (d['outcomeDestroyedDone'] ?? 0) as int,
                            pending:
                                (d['outcomeDestroyedAwaiting'] ?? 0) as int,
                            deliveredLabel: 'destroyed',
                            pendingLabel: 'awaiting destruction',
                            color: context.colors.dangerRed,
                            icon: Icons.local_fire_department_rounded,
                            route: '/destroyed-packages'),
                      ],
                    ),
                    const Gap(16),
                    _LifecycleGroup(
                      title: 'Top Management rulings · goods',
                      icon: Icons.account_balance_rounded,
                      tiles: [
                        // ⚠️ The rail's "Final Outcomes" section, one tile
                        // per page, in the rail's own order. These are the
                        // DG's rulings on goods nothing could sell.
                        _SplitTile(
                            label: 'Government use',
                            total: (d['proposal_government_use_total'] ?? 0)
                                as int,
                            delivered:
                                (d['proposal_government_use_delivered'] ?? 0)
                                    as int,
                            pending:
                                (d['proposal_government_use_pending'] ?? 0)
                                    as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting',
                            color: context.colors.accentLightBlue,
                            icon: Icons.account_balance_rounded,
                            route: '/government-use-packages'),
                        _SplitTile(
                            label: 'Auction',
                            total: (d['proposal_auction_total'] ?? 0) as int,
                            delivered:
                                (d['proposal_auction_delivered'] ?? 0) as int,
                            pending:
                                (d['proposal_auction_pending'] ?? 0) as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting',
                            color: context.colors.primaryGold,
                            icon: Icons.gavel_rounded,
                            route: '/auction-packages'),
                        _SplitTile(
                            label: 'Re-exported',
                            total: (d['outcomeReexportTotal'] ?? 0) as int,
                            delivered:
                                (d['outcomeReexportDelivered'] ?? 0) as int,
                            pending:
                                (d['outcomeReexportPending'] ?? 0) as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting',
                            color: context.colors.accentLightBlue,
                            icon: Icons.flight_takeoff_rounded,
                            route: '/reexported-packages'),
                        _SplitTile(
                            label: 'Converted',
                            total: (d['proposal_convert_total'] ?? 0) as int,
                            delivered:
                                (d['proposal_convert_delivered'] ?? 0) as int,
                            pending:
                                (d['proposal_convert_pending'] ?? 0) as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting',
                            color: context.colors.heldOrange,
                            icon: Icons.autorenew_rounded,
                            route: '/converted-packages'),
                        _SplitTile(
                            label: 'Removed from premises',
                            total:
                                (d['proposal_remove_from_premises_total'] ?? 0)
                                    as int,
                            delivered: (d[
                                    'proposal_remove_from_premises_delivered'] ??
                                0) as int,
                            pending: (d[
                                    'proposal_remove_from_premises_pending'] ??
                                0) as int,
                            deliveredLabel: 'delivered',
                            pendingLabel: 'awaiting',
                            color: context.colors.textMuted,
                            icon: Icons.logout_rounded,
                            route: '/removed-packages'),
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
        _GroupHeading(title: title, icon: icon),
        const Gap(8),
        Wrap(spacing: 12, runSpacing: 12, children: tiles),
      ],
    );
  }
}

/// The small capitalised heading over a group of tiles.
///
/// ⚠️ One definition, shared by the lifecycle groups and the shortcut
/// rows above them. Two copies of "10.5pt, 0.6 letter-spacing, w800, muted"
/// is two headings that drift apart, and a dashboard whose two halves are
/// labelled in slightly different type reads as two dashboards.
class _GroupHeading extends StatelessWidget {
  final String title;
  final IconData icon;
  const _GroupHeading({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: context.colors.textMuted),
        const Gap(8),
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800,
                color: context.colors.textMuted)),
      ]);
}

/// A single lifecycle metric tile (icon + big number + label).
class _LifecycleTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  /// Where this figure lives in full, if it has a page.
  ///
  /// ⚠️ Optional. A number an officer cannot act on is a number they
  /// have to go and find; a number with nowhere to go should not pretend.
  final String? route;

  /// Let the tile take its width from the row instead of the fixed 168.
  ///
  /// ⚠️ The lifecycle groups WRAP, so their tiles need a fixed width or
  /// the wrap has nothing to measure. The shortcut rows above are Rows of
  /// Expanded, where a fixed width fights the layout — so the same tile
  /// serves both, and the caller says which it is.
  final bool stretch;

  const _LifecycleTile(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon,
      this.route,
      this.stretch = false});

  @override
  Widget build(BuildContext context) {
    final tile = _tile(context);
    if (route == null) return tile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(route!),
        child: tile,
      ),
    );
  }

  Widget _tile(BuildContext context) {
    return Container(
      width: stretch ? null : 168,
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

/// One tile carrying a figure and its DELIVERY split.
///
/// ⚠️ Delivered and not-yet-delivered are two halves of ONE fact, and
/// two tiles said they were two facts. A reader had to notice the numbers
/// added up to the total on a third tile to see the relationship at all --
/// and with sold, destroyed and re-exported each split that way, the panel
/// grew to nine tiles saying what three can.
///
/// The total leads; the split sits under it as "39 delivered · 37 pending".
/// [pendingLabel] names the waiting half, because what a lot is waiting FOR
/// differs by outcome -- collection for a sale, the contractor for a burn.
class _SplitTile extends StatelessWidget {
  final String label;
  final int total;
  final int delivered;
  final int pending;
  final Color color;
  final IconData icon;
  final String deliveredLabel;
  final String pendingLabel;
  final String? route;

  const _SplitTile({
    required this.label,
    required this.total,
    required this.delivered,
    required this.pending,
    required this.color,
    required this.icon,
    this.deliveredLabel = 'delivered',
    this.pendingLabel = 'pending',
    this.route,
  });

  @override
  Widget build(BuildContext context) {
    final tile = _tile(context);
    if (route == null) return tile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
          onTap: () => context.go(route!), child: tile),
    );
  }

  Widget _tile(BuildContext context) {
    final muted = context.colors.textSecondary;
    // ⚠️ Rows with no hand-over step at all are neither half -- an
    // entry tagged final with no tender, destruction or proposal behind it
    // has nobody to collect from. They are in the total and in neither
    // number below it, so the tile says so rather than letting the reader
    // find the arithmetic does not close.
    final noStep = total - delivered - pending;
    return Container(
      width: 232,
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$total',
                        style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.0)),
                    const Gap(6),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const Gap(3),
                Text(
                    noStep > 0
                        ? '$delivered $deliveredLabel · $pending $pendingLabel '
                            '· $noStep n/a'
                        : '$delivered $deliveredLabel · $pending $pendingLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: muted,
                        fontSize: 10.5,
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
    String pretty = '—';
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
// ⚠️ `_WarehouseChargeCard` lived here and is gone.
//
// It was the last card drawn in the old shape, and it packed two different
// figures into one line: "Current W/H Rate · Accrued: LKR 242,3…". The
// accrued total is 242,304,500 — nine digits — so the line it shared with a
// label was always going to end in an ellipsis, and the number an officer
// most wants from it was the part that got cut.
//
// They are two questions: what the rate IS, and what has built up. Two
// tiles, in the same shape as everything else on the page.

/// The per-day rate, as a tile.
class _StorageRateTile extends StatelessWidget {
  final WidgetRef ref;
  const _StorageRateTile({required this.ref});

  @override
  Widget build(BuildContext context) {
    final rate = ref.watch(currentStorageRateProvider);
    return _LifecycleTile(
      stretch: true,
      label: 'W/H rate per day',
      value: rate.maybeWhen(
          data: (r) => 'LKR ${NumberFormat('#,##0').format(r)}',
          orElse: () => '…'),
      color: context.colors.primaryGold,
      icon: Icons.payments_rounded,
    );
  }
}

/// What has accrued on goods still in the yard.
class _AccruedStorageTile extends StatelessWidget {
  final WidgetRef ref;
  const _AccruedStorageTile({required this.ref});

  @override
  Widget build(BuildContext context) {
    final accrued = ref.watch(currentWarehouseChargeProvider);
    return _LifecycleTile(
      stretch: true,
      label: 'Accrued, still held',
      // ⚠️ COMPACT, because the full figure is nine digits and the
      // tile is a fifth of a row. "LKR 242.3M" fits and is read at a
      // glance; "LKR 242,304,500" does not fit and was being shown as
      // "LKR 242,3…", which is not a number at all.
      value: accrued.maybeWhen(
          data: (a) => _compactLkr(a.accrued), orElse: () => '…'),
      color: context.colors.primaryGold,
      icon: Icons.savings_rounded,
    );
  }
}

/// A large rupee figure in as few characters as it can be read in.
///
/// ⚠️ Rounded to one decimal at each step, not truncated: 242,304,500
/// reads "242.3M", and an officer comparing it with yesterday's needs the
/// digit that moves. Below a million it stays fully written out, because
/// there it fits.
String _compactLkr(double v) {
  if (v >= 1000000) return 'LKR ${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return 'LKR ${(v / 1000).toStringAsFixed(1)}K';
  return 'LKR ${NumberFormat('#,##0').format(v)}';
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
            error: (e, _) => const _QuietPanelError(),
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
              error: (e, _) => const _QuietPanelError(),
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
    // Show the ACTUAL item activities, not the generic package status (which is
    // always "held"). A package's items split into dispositions (Detain /
    // Forfeit / Abandoned / Other / …) — surface those instead.
    final statuses = _itemActivityStatuses(p);
    // Representative status drives the leading icon/colour; the chip(s) show the
    // breakdown.
    final primary = statuses.isNotEmpty ? statuses.first : p.status;
    final (icon, color) = _statusVisual(context, primary);
    // ⚠️ "states", not "activities". These are the DISTINCT STATUSES
    // the package's items are in right now -- SR/24/2026 reads "Detain,
    // destroyed" and showed "2 activities", which sounds like two things
    // happened today. One of them may have been recorded months ago; what put
    // the package on this list is that SOMETHING touched it today.
    final subtitle = statuses.length > 1
        ? '${p.consigneeName} · ${statuses.length} states'
        : p.consigneeName;

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
                Text(subtitle,
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
              // One chip per distinct item activity (wrapped so it never
              // overflows); falls back to the package status if no items.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: (statuses.isEmpty ? [p.status] : statuses)
                    .take(3)
                    .map((s) => StatusChip(status: s))
                    .toList(),
              ),
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

  /// The distinct item-level activity statuses in a package, ordered by how
  /// many items carry each (most common first). Empty when the package has no
  /// items (caller falls back to the package status).
  List<String> _itemActivityStatuses(PackageModel p) {
    if (p.items.isEmpty) return const [];
    final counts = <String, int>{};
    for (final it in p.items) {
      final s = it.status.trim();
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
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
