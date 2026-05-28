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
  NavItem('Packages', Icons.inventory_2_rounded, '/packages'),
  NavItem('Released Packages', Icons.keyboard_return_rounded, '/returned-packages'),
  NavItem('Forfeited Packages', Icons.gavel_rounded, '/forfeited-packages'),
  NavItem('Tender Disposals', Icons.assignment_ind_rounded, '/tender-disposals'),
  NavItem('Reports', Icons.summarize_rounded, '/reports'),
];

const _adminNav = [
  NavItem('Dashboard', Icons.dashboard_rounded, '/admin'),
  NavItem('SR Registration', Icons.assignment_outlined, '/inspection'),
  NavItem('Warehouses', Icons.warehouse_rounded, '/warehouses'),
  NavItem('Packages', Icons.inventory_2_rounded, '/packages'),
  NavItem('Released Packages', Icons.keyboard_return_rounded, '/returned-packages'),
  NavItem('Forfeited Packages', Icons.gavel_rounded, '/forfeited-packages'),
  NavItem('Tender Disposals', Icons.assignment_ind_rounded, '/tender-disposals'),
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

    // Start heartbeat: update status every 2 minutes
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
                            Text('SR Management System\nGrey Line 1',
                                style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.2)),
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
                            style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        Text(profile.role.toUpperCase(),
                            style: TextStyle(color: context.colors.primaryGold, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          Text('Salary No: ${profile.badgeNumber}',
                              style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 16),
                          label: Text(isDark ? 'Light Mode' : 'Dark Mode', style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.textPrimary,
                            side: BorderSide(color: context.colors.borderColor),
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
                            foregroundColor: context.colors.textPrimary,
                            side: BorderSide(color: context.colors.borderColor),
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
                Icon(item.icon,
                    color: isActive ? context.colors.primaryGold : context.colors.textSecondary, size: 20),
                const SizedBox(width: 12),
                Text(item.label,
                    style: TextStyle(
                      color: isActive ? context.colors.primaryGold : context.colors.textSecondary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
