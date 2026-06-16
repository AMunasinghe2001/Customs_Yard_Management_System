import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/admin_signup_screen.dart';
import '../screens/disposal/disposal_login_screen.dart';
import '../screens/disposal/disposal_signup_screen.dart';
import '../screens/disposal/disposal_dashboard_screen.dart';
import '../screens/appeal/appeal_login_screen.dart';
import '../screens/appeal/appeal_signup_screen.dart';
import '../screens/appeal/appeal_dashboard_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/inspection/inspection_screen.dart';
import '../screens/warehouses/warehouses_screen.dart';
import '../screens/warehouses/warehouse_capacity_screen.dart';
import '../screens/packages/packages_screen.dart';
import '../screens/packages/returned_packages_screen.dart';
import '../screens/packages/abandoned_packages_screen.dart';
import '../screens/packages/other_packages_screen.dart';
import '../screens/packages/disposition_category_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/forfeited_packages/forfeited_packages_screen.dart';
import '../screens/forfeited_packages/tender_disposal_screen.dart';
import '../widgets/app_shell.dart';
import '../core/supabase_client.dart';
import '../core/providers.dart';
import '../services/services.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final user = supabase.auth.currentUser;
      final isLoggedIn = user != null;
      final publicRoutes = [
        '/',
        '/login',
        '/admin/login',
        '/admin/signup',
        '/disposal/login',
        '/disposal/signup',
        '/appeal/login',
        '/appeal/signup'
      ];
      final isPublicPage = publicRoutes.contains(state.matchedLocation);
      
      if (isLoggedIn) {
        // Run deep verification (email confirmed, active status)
        try {
          await ref.read(authServiceProvider).verifyUserSession();
        } catch (e) {
          // If verification fails (e.g. email not confirmed), redirect to home/login
          return '/';
        }
      }

      if (!isLoggedIn && !isPublicPage) return '/';
      if (isLoggedIn && (state.matchedLocation == '/' || state.matchedLocation == '/login')) {
        final profile = ref.read(currentProfileProvider);
        if (profile?.isDisposal == true) return '/disposal';
        if (profile?.isAppeal == true) return '/appeal';
        if (profile?.isAdmin == true) return '/admin';
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/admin/login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: '/admin/signup', builder: (_, __) => const AdminSignupScreen()),
      GoRoute(path: '/disposal/login', builder: (_, __) => const DisposalLoginScreen()),
      GoRoute(path: '/disposal/signup', builder: (_, __) => const DisposalSignupScreen()),
      GoRoute(path: '/disposal', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DisposalDashboardScreen())),
      GoRoute(path: '/appeal/login', builder: (_, __) => const AppealLoginScreen()),
      GoRoute(path: '/appeal/signup', builder: (_, __) => const AppealSignupScreen()),
      GoRoute(path: '/appeal', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const AppealDashboardScreen())),
      GoRoute(path: '/dashboard', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DashboardScreen())),
      GoRoute(path: '/inspection', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const InspectionScreen())),
      GoRoute(path: '/warehouses', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const WarehousesScreen())),
      GoRoute(path: '/zone-capacity', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const WarehouseCapacityScreen())),
      GoRoute(path: '/packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const PackagesScreen())),
      GoRoute(path: '/returned-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const ReturnedPackagesScreen())),
      GoRoute(path: '/abandoned-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const AbandonedPackagesScreen())),
      GoRoute(path: '/forfeited-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const ForfeitedPackagesScreen())),
      GoRoute(path: '/other-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const OtherPackagesScreen())),
      GoRoute(path: '/sold-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DispositionCategoryScreen(route: '/sold-packages', title: 'Sold Packages', subtitle: 'Goods disposed by sale', countLabel: 'Sold', finalTag: 'SOLD'))),
      GoRoute(path: '/destroyed-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DispositionCategoryScreen(route: '/destroyed-packages', title: 'Destroyed Packages', subtitle: 'Goods that have been destroyed', countLabel: 'Destroyed', finalTag: 'DESTROYED'))),
      GoRoute(path: '/reexported-packages', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const DispositionCategoryScreen(route: '/reexported-packages', title: 'Re-exported Packages', subtitle: 'Goods sent back to country of origin', countLabel: 'Re-exported', finalTag: 'RE-EXPORTED'))),
      GoRoute(path: '/tender-disposals', pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const TenderDisposalScreen())),
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
