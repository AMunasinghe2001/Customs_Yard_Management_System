import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme.dart';
import '../core/db_client.dart';
import '../core/providers.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'update_available_button.dart';
import 'app_dialog.dart';
import 'developer_support_dialog.dart';

class NavItem {
  final String label;
  final IconData icon;
  final String route;
  const NavItem(this.label, this.icon, this.route);
}

/// A captioned run of nav items.
///
/// The rail is over twenty entries long. Ungrouped, finding "Converted Goods"
/// meant reading every label from the top -- so the items are grouped by the
/// stage of the yard's work they belong to, and each group is captioned.
class NavSection {
  final String title;
  final List<NavItem> items;
  const NavSection(this.title, this.items);
}

// ── The sections, in the order the work actually happens ──────────────────
// Goods arrive, are held, get a disposition, are disposed of, and finally
// reach an outcome. Reading the rail top to bottom now follows that path.

const _navRegister = [
  NavItem('SR Registration', Icons.assignment_outlined, '/inspection'),
  NavItem('Old Entries', Icons.history_edu_rounded, '/old-entries'),
  NavItem('Goods History', Icons.inventory_2_rounded, '/packages'),
];

const _navStorage = [
  NavItem('Warehouses', Icons.warehouse_rounded, '/warehouses'),
  NavItem('Zone Capacity', Icons.donut_large_rounded, '/zone-capacity'),
];

/// What the goods are held AS, while the yard decides.
const _navHolding = [
  NavItem('Detained Goods', Icons.gpp_maybe_rounded, '/detained-packages'),
  NavItem('Abandoned Goods', Icons.inbox_rounded, '/abandoned-packages'),
  NavItem('Forfeited Goods', Icons.gavel_rounded, '/forfeited-packages'),
  NavItem('Other Goods', Icons.label_important_rounded, '/other-packages'),
  // Perishable goods never reach a warehouse, so they appear on no
  // disposition page -- this is the only place they are listed.
  NavItem('Perishable Goods', Icons.eco_rounded, '/perishable-goods'),
];

/// How they LEFT.
///
/// ⚠️ Re-exported belongs HERE, not in Final Outcomes, even though Top
/// Management can now send goods to it. This group answers "where did the
/// goods go", and re-exported goods left the country whichever route decided
/// it; Final Outcomes answers "what did Top Management rule about goods
/// nothing could sell", and its four pages have exactly one origin each. The
/// Re-exported table carries a Decided By column instead, because the split
/// is between ROWS on that page, not between pages.
///
/// (Unsold Goods sits here too, though the goods have not left: they are out
/// of the tender process and waiting on Top Management. It reads oddly under
/// "Disposed" -- worth a decision, but moving it is the officers' call, not
/// one to make from here.)
const _navDisposed = [
  NavItem(
      'Released Goods', Icons.keyboard_return_rounded, '/returned-packages'),
  NavItem('Sold Goods', Icons.sell_rounded, '/sold-packages'),
  NavItem('Unsold Goods', Icons.rule_folder_rounded, '/unsold-packages'),
  NavItem(
      'Destroyed Goods', Icons.delete_forever_rounded, '/destroyed-packages'),
  NavItem('Re-exported Goods', Icons.flight_takeoff_rounded,
      '/reexported-packages'),
];

/// The Top Management Directorate's outcomes for goods nothing could sell.
const _navOutcomes = [
  NavItem('Government Use', Icons.account_balance_rounded,
      '/government-use-packages'),
  NavItem('Auction Goods', Icons.gavel_rounded, '/auction-packages'),
  NavItem('Converted Goods', Icons.autorenew_rounded, '/converted-packages'),
  NavItem('Removed from Premises', Icons.logout_rounded, '/removed-packages'),
];

const _navReporting = [
  NavItem('Tender Sale', Icons.assignment_ind_rounded, '/tender-disposals'),
  NavItem('Reports', Icons.summarize_rounded, '/reports'),
];

/// The officer's rail. ⚠️ The admin rail differs only in its Dashboard route
/// and its extra Admin Panel entry, so both are built from ONE definition --
/// the two hand-maintained copies had already drifted once.
List<NavSection> navSectionsFor({required bool isAdmin}) => [
      NavSection('', [
        NavItem('Dashboard', Icons.dashboard_rounded,
            isAdmin ? '/admin' : '/dashboard'),
      ]),
      const NavSection('Register', _navRegister),
      const NavSection('Storage', _navStorage),
      const NavSection('Held Goods', _navHolding),
      const NavSection('Disposed', _navDisposed),
      const NavSection('Final Outcomes', _navOutcomes),
      NavSection('Reporting', [
        ..._navReporting,
        if (isAdmin)
          const NavItem(
              // ⚠️ "Yard Administration", not "Admin Panel". The ICT
              // portal is THE Admin Panel — it provisions accounts and
              // configures the system for every yard. This page configures
              // ONE yard's storage and reads its records, and giving the
              // two the same name made a yard page look like the
              // system-wide one.
              'Yard Administration',
              Icons.admin_panel_settings_rounded,
              '/admin/panel'),
      ]),
    ];

/// A small caption above a run of nav items.
///
/// Deliberately quiet -- it labels the group without competing with the items
/// themselves, which are what people actually click.
class _NavSectionHeading extends StatelessWidget {
  final String title;
  const _NavSectionHeading(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.38),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Where the nav rail is scrolled to, kept OUTSIDE the widget tree.
///
/// Every screen wraps itself in its own [AppShell], so navigating disposes one
/// shell and builds another. A ScrollController held in State is therefore
/// born at offset 0 on every navigation — which is why clicking a nav item far
/// down the rail jumped the rail back to the top the instant the page opened,
/// hiding the very item that had just been selected.
///
/// A single module-level offset survives that rebuild, so the rail stays
/// exactly where the officer left it.
double _navScrollOffset = 0;

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;
  const AppShell({super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _heartbeatTimer;

  /// Restores the rail to wherever the previous shell left it, and keeps
  /// [_navScrollOffset] up to date as the officer scrolls.
  late final ScrollController _navScrollCtrl =
      ScrollController(initialScrollOffset: _navScrollOffset)
        ..addListener(_rememberNavScroll);

  void _rememberNavScroll() {
    if (_navScrollCtrl.hasClients) {
      _navScrollOffset = _navScrollCtrl.offset;
    }
  }

  @override
  void initState() {
    super.initState();

    // Heartbeat every 2 minutes. Clean sign-out / window-close already null
    // last_seen for INSTANT offline, so the heartbeat only exists to catch
    // crashes/task-kills — it doesn't need to be frequent. Keeping it at 2 min
    // (not seconds) cuts profile writes + realtime fan-out ~3x at 300 users.
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        ref.read(authServiceProvider).updateHeartbeat();
      }
    });

    // Initial heartbeat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authServiceProvider).updateHeartbeat();
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _navScrollCtrl.removeListener(_rememberNavScroll);
    _navScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final navSections = navSectionsFor(isAdmin: profile?.isAdmin == true);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Row(
        children: [
          Container(
            width: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  context.colors.customsBlue,
                  context.colors.customsBlueDark
                ],
              ),
              border:
                  Border(right: BorderSide(color: context.colors.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo section with SVG
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  decoration: BoxDecoration(
                    border:
                        const Border(bottom: BorderSide(color: Colors.white10)),
                    color: Colors.white.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SvgPicture.asset(
                          'Sri_Lanka_Customs_logo.svg',
                          colorFilter: const ColorFilter.mode(
                              Colors.white, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SL Customs',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                            Text('SR Management System',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    height: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    controller: _navScrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final section in navSections) ...[
                        if (section.title.isNotEmpty)
                          _NavSectionHeading(section.title),
                        for (final item in section.items)
                          _NavTile(
                            item: item,
                            // ⚠️ '/admin' must match EXACTLY. Every other route
                            // matches by prefix, but '/admin' is a prefix of
                            // '/admin/panel', so a prefix test would light up
                            // Dashboard while the Admin Panel is open.
                            isActive: item.route == '/admin'
                                ? widget.currentRoute == '/admin'
                                : (widget.currentRoute == item.route ||
                                    (widget.currentRoute
                                            .startsWith(item.route) &&
                                        item.route.length > 1)),
                          ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.colors.borderColor),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile != null) ...[
                        Text(profile.fullName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        Text(
                            // ⚠️ The officer's POST, not their permission
                            // level.
                            //
                            // This showed "SDDC / DDC" for every admin and the
                            // raw role for everyone else -- so a Deputy
                            // Director of Customs and a Senior Deputy Director
                            // read identically, and an officer read "OFFICER".
                            // `role` has only two yard values; which post an
                            // officer actually holds is `job_role`, set by ICT
                            // at provisioning.
                            //
                            // postShortTitle falls back to exactly the old
                            // text for an account provisioned before ICT
                            // recorded a post, so nothing regresses.
                            profile.postShortTitle.toUpperCase(),
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                        Text('Salary No: ${profile.badgeNumber}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11)),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(
                              isDark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              size: 16),
                          label: Text(isDark ? 'Light Mode' : 'Dark Mode',
                              style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () {
                            ref.read(themeModeProvider.notifier).state =
                                isDark ? ThemeMode.light : ThemeMode.dark;
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.person_rounded, size: 16),
                          label: const Text('Profile',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => context.go('/profile'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.support_agent_rounded, size: 16),
                          label: const Text('Contact Developer',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.primaryGold,
                            side: BorderSide(
                                color: context.colors.primaryGold.withOpacity(0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => showAppDialog(
                            context: context,
                            builder: (_) => const DeveloperSupportDialog(
                              portalName: 'Customs Yard',
                            ),
                          ),
                        ),
                      ),
                      // ⚠️ Shown ONLY when there is an update.
                      //
                      // This was a permanent "Check for Updates"
                      // button, which is a question almost nobody wants
                      // to ask: nearly every press answered "nothing
                      // new", so it was noise on every screen for the
                      // sake of the rare day it had news. The app
                      // already knows the answer from the start-up
                      // check, so it offers the ACTION instead.
                      UpdateAvailableButton(
                        trailing: const SizedBox(height: 8),
                        builder: (ctx, update, onPressed) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: const Icon(Icons.download_rounded,
                                  size: 16),
                              label: Text(updateButtonLabel(update),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                // Gold on navy, matching the strip:
                                // nothing is wrong, there is simply
                                // something newer.
                                backgroundColor:
                                    updateButtonAccent(ctx),
                                foregroundColor: ctx.colors.primaryNavy,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                              ),
                              onPressed: onPressed,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Sign Out',
                              style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.dangerRed,
                            side: BorderSide(color: context.colors.dangerRed),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            await ref.read(authServiceProvider).signOut();
                            ref.read(currentProfileProvider.notifier).state =
                                null;
                            if (context.mounted) context.go('/');
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  final NavItem item;
  final bool isActive;
  const _NavTile({required this.item, required this.isActive});

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  /// ⚠️ Tracked explicitly. An InkWell's own hover highlight is a faint
  /// overlay that all but vanishes against the dark navy rail, so pointing at
  /// an item gave almost no feedback -- on a rail this long you could not tell
  /// which row you were about to click.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isActive = widget.isActive;
    final gold = context.colors.primaryGold;
    // Active wins over hover: a row that is already open should not change
    // appearance just because the pointer crosses it.
    final tint = isActive
        ? gold
        : (_hovered ? gold.withOpacity(0.85) : Colors.white.withOpacity(0.85));

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.go(item.route),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isActive
                    ? gold.withOpacity(0.15)
                    : (_hovered
                        ? Colors.white.withOpacity(0.07)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? gold.withOpacity(0.3)
                      : (_hovered
                          ? gold.withOpacity(0.25)
                          : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  // Sidebar is always dark navy — use light colors for contrast
                  // in both light and dark themes.
                  Icon(item.icon, color: tint, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.label,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: tint,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        )),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
