import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme.dart';
import '../core/supabase_client.dart';
import '../core/providers.dart';
import '../models/models.dart';
import '../services/services.dart';

class NavItem {
  final String label;
  final IconData icon;
  final String route;
  const NavItem(this.label, this.icon, this.route);
}

const _officerNav = [
  NavItem('Dashboard', Icons.dashboard_rounded, '/dashboard'),
  NavItem('SR Registration', Icons.assignment_outlined, '/inspection'),
  NavItem('Warehouses', Icons.warehouse_rounded, '/warehouses'),
  NavItem('Zone Capacity', Icons.donut_large_rounded, '/zone-capacity'),
  NavItem('Packages', Icons.inventory_2_rounded, '/packages'),
  NavItem('Released Packages', Icons.keyboard_return_rounded, '/returned-packages'),
  NavItem('Abandoned Packages', Icons.inbox_rounded, '/abandoned-packages'),
  NavItem('Forfeited Packages', Icons.gavel_rounded, '/forfeited-packages'),
  NavItem('Other Packages', Icons.label_important_rounded, '/other-packages'),
  NavItem('Sold Packages', Icons.sell_rounded, '/sold-packages'),
  NavItem('Destroyed Packages', Icons.delete_forever_rounded, '/destroyed-packages'),
  NavItem('Re-exported Packages', Icons.flight_takeoff_rounded, '/reexported-packages'),
  NavItem('Tender Sale', Icons.assignment_ind_rounded, '/tender-disposals'),
  NavItem('Destruction Sale', Icons.local_fire_department_rounded, '/destruction-disposals'),
  NavItem('Reports', Icons.summarize_rounded, '/reports'),
];

const _adminNav = [
  NavItem('Dashboard', Icons.dashboard_rounded, '/admin'),
  NavItem('SR Registration', Icons.assignment_outlined, '/inspection'),
  NavItem('Warehouses', Icons.warehouse_rounded, '/warehouses'),
  NavItem('Zone Capacity', Icons.donut_large_rounded, '/zone-capacity'),
  NavItem('Packages', Icons.inventory_2_rounded, '/packages'),
  NavItem('Released Packages', Icons.keyboard_return_rounded, '/returned-packages'),
  NavItem('Abandoned Packages', Icons.inbox_rounded, '/abandoned-packages'),
  NavItem('Forfeited Packages', Icons.gavel_rounded, '/forfeited-packages'),
  NavItem('Other Packages', Icons.label_important_rounded, '/other-packages'),
  NavItem('Sold Packages', Icons.sell_rounded, '/sold-packages'),
  NavItem('Destroyed Packages', Icons.delete_forever_rounded, '/destroyed-packages'),
  NavItem('Re-exported Packages', Icons.flight_takeoff_rounded, '/reexported-packages'),
  NavItem('Tender Sale', Icons.assignment_ind_rounded, '/tender-disposals'),
  NavItem('Destruction Sale', Icons.local_fire_department_rounded, '/destruction-disposals'),
  NavItem('Reports', Icons.summarize_rounded, '/reports'),
  NavItem('Admin Panel', Icons.admin_panel_settings_rounded, '/admin/panel'),
];

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;
  const AppShell({super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _heartbeatTimer;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final navItems = profile?.isAdmin == true ? _adminNav : _officerNav;
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
                colors: [context.colors.customsBlue, context.colors.customsBlueDark],
              ),
              border: Border(right: BorderSide(color: context.colors.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo section with SVG
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  decoration: BoxDecoration(
                    border: const Border(bottom: BorderSide(color: Colors.white10)),
                    color: Colors.white.withOpacity(0.05),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SvgPicture.asset(
                          'Sri_Lanka_Customs_logo.svg',
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SL Customs',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                            Text('SR Management System',
                                style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: navItems.map((item) {
                      final isActive = item.route == '/admin' 
                          ? widget.currentRoute == '/admin' 
                          : (widget.currentRoute == item.route || (widget.currentRoute.startsWith(item.route) && item.route.length > 1));
                      return _NavTile(item: item, isActive: isActive);
                    }).toList(),
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
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        Text(
                            // Admins are the yard's DC / SDDC officers — show
                            // that title instead of the raw 'ADMIN' role.
                            profile.isAdmin
                                ? 'DC / SDDC'
                                : profile.role.toUpperCase(),
                            style: TextStyle(color: context.colors.primaryGold, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          Text('Salary No: ${profile.badgeNumber}',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 16),
                          label: Text(isDark ? 'Light Mode' : 'Dark Mode', style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () {
                            ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.person_rounded, size: 16),
                          label: const Text('Profile', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.25)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () => context.go('/profile'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Sign Out', style: TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.dangerRed,
                            side: BorderSide(color: context.colors.dangerRed),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            await ref.read(authServiceProvider).signOut();
                            ref.read(currentProfileProvider.notifier).state = null;
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

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool isActive;
  const _NavTile({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go(item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isActive ? context.colors.primaryGold.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isActive ? Border.all(color: context.colors.primaryGold.withOpacity(0.3)) : null,
            ),
            child: Row(
              children: [
                // Sidebar is always dark navy — use light colors for contrast
                // in both light and dark themes.
                Icon(item.icon,
                    color: isActive
                        ? context.colors.primaryGold
                        : Colors.white.withOpacity(0.85),
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: isActive
                            ? context.colors.primaryGold
                            : Colors.white.withOpacity(0.85),
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
