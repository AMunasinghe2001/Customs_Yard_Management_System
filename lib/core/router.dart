import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/yard_access_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/admin/admin_login_screen.dart';
import '../screens/admin/admin_signup_screen.dart';
import '../screens/disposal/disposal_login_screen.dart';
import '../screens/disposal/disposal_signup_screen.dart';
import '../screens/disposal/disposal_dashboard_screen.dart';
import '../screens/appeal/appeal_login_screen.dart';
import '../screens/appeal/appeal_signup_screen.dart';
import '../screens/appeal/appeal_dashboard_screen.dart';
import '../screens/valuation/valuation_login_screen.dart';
import '../screens/valuation/valuation_signup_screen.dart';
import '../screens/valuation/valuation_dashboard_screen.dart';
import '../screens/executive/executive_login_screen.dart';
import '../screens/executive/executive_signup_screen.dart';
import '../screens/executive/executive_dashboard_screen.dart';
import '../screens/ict/ict_login_screen.dart';
import '../screens/ict/ict_signup_screen.dart';
import '../screens/ict/ict_dashboard_screen.dart';
import '../screens/inspection/inspection_screen.dart';
import '../screens/warehouses/warehouses_screen.dart';
import '../screens/warehouses/warehouse_capacity_screen.dart';
import '../screens/packages/packages_screen.dart';
import '../screens/packages/returned_packages_screen.dart';
import '../screens/packages/abandoned_packages_screen.dart';
import '../screens/packages/detained_packages_screen.dart';
import '../screens/packages/other_packages_screen.dart';
import '../screens/packages/perishable_goods_screen.dart';
import '../screens/packages/old_entries_screen.dart';
import '../screens/packages/disposition_category_screen.dart';
import '../screens/packages/unsold_packages_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/forfeited_packages/forfeited_packages_screen.dart';
import '../screens/forfeited_packages/tender_disposal_screen.dart';
import '../screens/forfeited_packages/destruction_disposal_screen.dart';
import '../widgets/app_shell.dart';
import '../core/supabase_client.dart';
import '../core/providers.dart';
import '../services/services.dart';
import 'app_log.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final user = supabase.auth.currentUser;
      final isLoggedIn = user != null;
      AppLog.debug(
          'redirect matched=${state.matchedLocation} loggedIn=$isLoggedIn '
          'profileAdmin=${ref.read(currentProfileProvider)?.isAdmin}',
          tag: 'router');
      final publicRoutes = [
        '/',
        '/yard-access',
        '/login',
        '/admin/login',
        '/admin/signup',
        '/disposal/login',
        '/disposal/signup',
        '/appeal/login',
        '/appeal/signup',
        '/valuation/login',
        '/valuation/signup',
        '/executive/login',
        '/executive/signup',
        '/ict/login',
        '/ict/signup'
      ];
      final isPublicPage = publicRoutes.contains(state.matchedLocation);

      if (isLoggedIn) {
        // Run deep verification (email confirmed, active status)
        try {
          await ref.read(authServiceProvider).verifyUserSession();
        } catch (e) {
          AppLog.warn('session verification failed; redirecting to /',
              error: e, tag: 'router');
          // If verification fails (e.g. email not confirmed), redirect to home/login
          return '/';
        }
      }

      if (!isLoggedIn && !isPublicPage) return '/';
      if (isLoggedIn &&
          (state.matchedLocation == '/' || state.matchedLocation == '/login')) {
        final profile = ref.read(currentProfileProvider);
        if (profile?.isIct == true) return '/ict';
        if (profile?.isDisposal == true) return '/disposal';
        if (profile?.isAppeal == true) return '/appeal';
        if (profile?.isValuation == true) return '/valuation';
        if (profile?.isExecutive == true) return '/executive';
        if (profile?.isAdmin == true) return '/admin';
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/yard-access', builder: (_, __) => const YardAccessScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/admin/login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(
          path: '/admin/signup', builder: (_, __) => const AdminSignupScreen()),
      GoRoute(
          path: '/ict/login', builder: (_, __) => const IctLoginScreen()),
      GoRoute(
          path: '/ict/signup', builder: (_, __) => const IctSignupScreen()),
      GoRoute(
          path: '/ict',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const IctDashboardScreen())),
      GoRoute(
          path: '/disposal/login',
          builder: (_, __) => const DisposalLoginScreen()),
      GoRoute(
          path: '/disposal/signup',
          builder: (_, __) => const DisposalSignupScreen()),
      GoRoute(
          path: '/disposal',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const DisposalDashboardScreen())),
      GoRoute(
          path: '/valuation/login',
          builder: (_, __) => const ValuationLoginScreen()),
      GoRoute(
          path: '/valuation/signup',
          builder: (_, __) => const ValuationSignupScreen()),
      GoRoute(
          path: '/valuation',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const ValuationDashboardScreen())),
      GoRoute(
          path: '/executive/login',
          builder: (_, __) => const ExecutiveLoginScreen()),
      GoRoute(
          path: '/executive/signup',
          builder: (_, __) => const ExecutiveSignupScreen()),
      GoRoute(
          path: '/executive',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const ExecutiveDashboardScreen())),
      GoRoute(
          path: '/appeal/login', builder: (_, __) => const AppealLoginScreen()),
      GoRoute(
          path: '/appeal/signup',
          builder: (_, __) => const AppealSignupScreen()),
      GoRoute(
          path: '/appeal',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const AppealDashboardScreen())),
      // Officers land here — same dashboard as admins (one shared dashboard),
      // just with the '/dashboard' nav item highlighted.
      GoRoute(
          path: '/dashboard',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const AdminDashboardScreen(currentRoute: '/dashboard'))),
      GoRoute(
          path: '/inspection',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const InspectionScreen())),
      GoRoute(
          path: '/warehouses',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const WarehousesScreen())),
      GoRoute(
          path: '/zone-capacity',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const WarehouseCapacityScreen())),
      GoRoute(
          path: '/packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const PackagesScreen())),
      GoRoute(
          path: '/old-entries',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const OldEntriesScreen())),
      GoRoute(
          path: '/returned-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const ReturnedPackagesScreen())),
      GoRoute(
          path: '/abandoned-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const AbandonedPackagesScreen())),
      GoRoute(
          path: '/forfeited-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const ForfeitedPackagesScreen())),
      GoRoute(
          path: '/detained-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const DetainedPackagesScreen())),
      GoRoute(
          path: '/perishable-goods',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const PerishableGoodsScreen())),
      GoRoute(
          path: '/other-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const OtherPackagesScreen())),
      GoRoute(
          path: '/sold-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DispositionCategoryScreen(
                  route: '/sold-packages',
                  title: 'Sold Goods',
                  subtitle: 'Goods disposed by sale',
                  countLabel: 'Sold',
                  finalTag: 'SOLD'))),
      GoRoute(
          path: '/unsold-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const UnsoldPackagesScreen())),
      // ── The Top Management Directorate's outcomes, one page each ──
      //  Same screen as Unsold Goods, narrowed to a single decided outcome.
      GoRoute(
          path: '/government-use-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const UnsoldPackagesScreen(
                  route: '/government-use-packages',
                  title: 'Government Use Goods',
                  subtitle: 'Unsold goods taken into government service',
                  countLabel: 'For Government Use',
                  proposalFilter: 'government_use'))),
      GoRoute(
          path: '/auction-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const UnsoldPackagesScreen(
                  route: '/auction-packages',
                  title: 'Auction Goods',
                  subtitle: 'Unsold goods sent to public auction',
                  countLabel: 'For Auction',
                  proposalFilter: 'auction'))),
      GoRoute(
          path: '/re-export-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const UnsoldPackagesScreen(
                  route: '/re-export-packages',
                  title: 'Re-export Goods',
                  subtitle: 'Unsold goods sent back out of the country',
                  countLabel: 'For Re-export',
                  proposalFilter: 're_export'))),
      GoRoute(
          path: '/converted-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const UnsoldPackagesScreen(
                  route: '/converted-packages',
                  title: 'Converted Goods',
                  subtitle: 'Unsold goods converted to another use or form',
                  countLabel: 'Converted',
                  proposalFilter: 'convert'))),
      GoRoute(
          path: '/removed-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const UnsoldPackagesScreen(
                  route: '/removed-packages',
                  title: 'Removed from the Premises',
                  subtitle: 'Unsold goods removed from the yard',
                  countLabel: 'Removed',
                  proposalFilter: 'remove_from_premises'))),
      GoRoute(
          path: '/destroyed-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DispositionCategoryScreen(
                  route: '/destroyed-packages',
                  title: 'Destroyed Goods',
                  subtitle: 'Goods that have been destroyed',
                  countLabel: 'Destroyed',
                  finalTag: 'DESTROYED'))),
      GoRoute(
          path: '/reexported-packages',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: const DispositionCategoryScreen(
                  route: '/reexported-packages',
                  title: 'Re-exported Goods',
                  subtitle: 'Goods sent back to country of origin',
                  countLabel: 'Re-exported',
                  finalTag: 'RE-EXPORTED'))),
      GoRoute(
          path: '/tender-disposals',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const TenderDisposalScreen())),
      GoRoute(
          path: '/destruction-disposals',
          redirect: (_, __) => '/destroyed-packages'),
      GoRoute(
          path: '/admin',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const AdminDashboardScreen())),
      GoRoute(
          path: '/admin/panel',
          pageBuilder: (_, state) {
            final tabStr = state.uri.queryParameters['tab'];
            final tabIndex = int.tryParse(tabStr ?? '0') ?? 0;
            return NoTransitionPage(
                key: state.pageKey, child: AdminScreen(initialIndex: tabIndex));
          }),
      GoRoute(
          path: '/profile',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey, child: const EditProfileScreen())),
      GoRoute(
          path: '/reports',
          pageBuilder: (_, state) => NoTransitionPage(
              key: state.pageKey,
              child: AppShell(
                  currentRoute: '/reports', child: const ReportsScreen()))),
    ],
  );
});
