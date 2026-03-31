import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/officer_signup_screen.dart';
import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/admin_signup_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/inspection/inspection_screen.dart';
import '../screens/warehouses/warehouses_screen.dart';
import '../screens/packages/packages_screen.dart';
import '../screens/packages/returned_packages_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../widgets/app_shell.dart';
import '../core/supabase_client.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = supabase.auth.currentUser != null;
      final publicRoutes = ['/', '/login', '/signup', '/admin/login', '/admin/signup'];
      final isPublicPage = publicRoutes.contains(state.matchedLocation);
      if (!isLoggedIn && !isPublicPage) return '/';
      if (isLoggedIn && (state.matchedLocation == '/' || state.matchedLocation == '/login')) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const OfficerSignupScreen()),
      GoRoute(path: '/admin/login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: '/admin/signup', builder: (_, __) => const AdminSignupScreen()),
      GoRoute(path: '/dashboard', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DashboardScreen())),
      GoRoute(path: '/inspection', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const InspectionScreen())),
      GoRoute(path: '/warehouses', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const WarehousesScreen())),
      GoRoute(path: '/packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const PackagesScreen())),
      GoRoute(path: '/returned-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const ReturnedPackagesScreen())),
      GoRoute(path: '/admin', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const AdminDashboardScreen())),
      GoRoute(path: '/admin/panel', pageBuilder: (_, state) {
        final tabStr = state.uri.queryParameters['tab'];
        final tabIndex = int.tryParse(tabStr ?? '0') ?? 0;
        return NoTransitionPage(key: state.pageKey, child: AdminScreen(initialIndex: tabIndex));
      }),
      GoRoute(path: '/profile', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const EditProfileScreen())),
      GoRoute(path: '/reports', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: AppShell(currentRoute: '/reports', child: const ReportsScreen()))),
    ],
  );
});
