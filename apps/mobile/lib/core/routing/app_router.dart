import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_provider.dart';
import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/booking/booking_wizard_screen.dart';
import '../../features/booking/booking_history_screen.dart';
import '../../features/guide/guide_group_screen.dart';
import '../../features/guide/guide_home_screen.dart';
import '../../features/groups/group_dashboard_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/language_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/support/support_screen.dart';
import '../../features/themes/theme_detail_screen.dart';
import '../../features/themes/theme_list_screen.dart';
import '../../features/trip/memory_album_screen.dart';
import '../../features/trip/service_request_screen.dart';
import '../../features/trip/sos_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final public = loc == '/splash' ||
          loc == '/auth' ||
          loc == '/language' ||
          loc == '/onboarding';
      if (!session.isLoggedIn && !public) {
        return '/auth';
      }
      if (session.isLoggedIn && loc == '/auth') {
        if (session.isAdmin) return '/admin';
        return session.isGuide ? '/g/home' : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/language', builder: (context, state) => const LanguageScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (context, state) => const SignInScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/themes', builder: (context, state) => const ThemeListScreen()),
      GoRoute(
        path: '/themes/:slug',
        builder: (context, state) =>
            ThemeDetailScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/themes/:slug/book',
        builder: (context, state) =>
            BookingWizardScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/groups/:groupId',
        builder: (context, state) =>
            GroupDashboardScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/groups/:groupId/request',
        builder: (context, state) =>
            ServiceRequestScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/groups/:groupId/sos',
        builder: (context, state) =>
            SosScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/groups/:groupId/memory',
        builder: (context, state) =>
            MemoryAlbumScreen(groupId: state.pathParameters['groupId']!),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/support', builder: (context, state) => const SupportScreen()),
      GoRoute(path: '/bookings', builder: (context, state) => const BookingHistoryScreen()),
      GoRoute(path: '/donations', builder: (context, state) => const SupportScreen()),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(path: '/g/home', builder: (context, state) => const GuideHomeScreen()),
      GoRoute(
        path: '/g/groups/:groupId',
        builder: (context, state) =>
            GuideGroupScreen(groupId: state.pathParameters['groupId']!),
      ),
    ],
  );

  ref.listen<SessionState>(sessionProvider, (previous, next) {
    router.refresh();
  });

  return router;
});
