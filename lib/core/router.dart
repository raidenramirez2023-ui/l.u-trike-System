import 'package:go_router/go_router.dart';

import '../data/auth_controller.dart';
import '../data/models.dart';
import '../features/admin/admin_dashboard.dart';
import '../features/auth/auth_pages.dart';
import '../features/driver/driver_dashboard.dart';
import '../features/student/student_dashboard.dart';
import 'env.dart';

GoRouter buildRouter() {
  final auth = AuthController.instance;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      if (!Env.isConfigured) {
        if (state.matchedLocation != '/setup') return '/setup';
        return null;
      }

      if (auth.loading) {
        if (state.matchedLocation != '/splash') return '/splash';
        return null;
      }

      if (auth.passwordRecovery) {
        if (state.matchedLocation != '/reset-password') return '/reset-password';
        return null;
      }

      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/' ||
          loc.startsWith('/login') ||
          loc.startsWith('/register') ||
          loc == '/forgot-password' ||
          loc == '/setup' ||
          loc == '/splash';

      if (!auth.signedIn) {
        // QR Code deep link `/t/:code`: allow redirecting back to terminal after signing in
        if (loc.startsWith('/t/')) {
          return '/login/student?next=${Uri.encodeComponent(loc)}';
        }
        if (!isAuthRoute) return '/';
        return null;
      }

      // User is signed in. Check account status.
      final p = auth.profile;
      if (p == null || p.status != AccountStatus.active) {
        if (loc != '/account-status') return '/account-status';
        return null;
      }

      // Active user trying to view auth pages -> redirect to role dashboard
      if (isAuthRoute || loc == '/account-status') {
        return switch (p.role) {
          UserRole.student => '/student',
          UserRole.driver => '/driver',
          UserRole.admin => '/admin',
        };
      }

      // Guard role boundaries (e.g. students cannot open /driver or /admin)
      if (loc.startsWith('/driver') && p.role != UserRole.driver) return '/';
      if (loc.startsWith('/admin') && p.role != UserRole.admin) return '/';
      if (loc.startsWith('/student') && p.role != UserRole.student) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupRequiredPage()),
      GoRoute(path: '/', builder: (_, _) => const LandingPage()),

      // Auth portals
      GoRoute(
        path: '/login/:role',
        builder: (_, state) {
          final r = roleFrom(state.pathParameters['role'] ?? 'student');
          final next = state.uri.queryParameters['next'];
          return LoginPage(portal: r, next: next);
        },
      ),
      GoRoute(path: '/register/student', builder: (_, _) => const StudentRegisterPage()),
      GoRoute(path: '/register/driver', builder: (_, _) => const DriverRegisterPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordPage()),
      GoRoute(path: '/account-status', builder: (_, _) => const AccountStatusPage()),

      // Role Dashboards
      GoRoute(path: '/student', builder: (_, _) => const StudentDashboardPage()),
      // QR Code access deep link: /t/MAIN or /t/GATE1
      GoRoute(
        path: '/t/:code',
        builder: (_, state) => StudentDashboardPage(terminalCode: state.pathParameters['code']),
      ),
      GoRoute(path: '/driver', builder: (_, _) => const DriverDashboardPage()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardPage()),
    ],
  );
}
