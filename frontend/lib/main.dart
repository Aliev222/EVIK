import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/error/global_error_handler.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/performance/frame_timing_monitor.dart';
import 'core/performance/rebuild_tracker.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/entities/user.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/sms_verification_screen.dart';
import 'features/driver/presentation/driver_screen.dart';
import 'features/client/presentation/screens/client_app_shell.dart';
import 'features/onboarding/presentation/screens/role_selection_screen.dart';
import 'shared/widgets/offline_sos_screen.dart';
import 'features/client/presentation/screens/pickup_location_screen.dart';
import 'features/client/presentation/screens/destination_location_screen.dart';
import 'features/client/presentation/screens/vehicle_selection_screen.dart';
import 'features/client/presentation/screens/tow_truck_selection_screen.dart';
import 'features/client/presentation/screens/driver_search_screen.dart';
import 'features/client/presentation/screens/driver_info_screen.dart';
import 'features/client/presentation/screens/tracking_screen.dart';
// TODO: remove when review screen is confirmed
// import 'features/client/presentation/screens/order_completion_screen.dart';
import 'features/client/presentation/screens/order_review_screen.dart';
import 'features/order/screens/payment_confirmation_screen.dart';
import 'features/client/presentation/screens/driver_rating_screen.dart';
import 'features/driver/presentation/screens/active_order_screen.dart';
import 'features/order/domain/entities/order.dart';
import 'features/order/presentation/providers/order_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase not configured for this platform — app works without it
  }

  // Initialize global error handler
  GlobalErrorHandler.initialize();

  const enablePerformanceMonitor = bool.fromEnvironment(
    'EVIK_ENABLE_PERF_MONITOR',
    defaultValue: false,
  );
  if (kDebugMode && enablePerformanceMonitor) {
    FrameTimingMonitor.initialize();
    RebuildTracker.initialize();
  }

  PushNotificationService.instance
      .setRouteHandler(EvikApp.navigateFromNotification);
  PushNotificationService.instance
      .setCurrentRouteResolver(EvikApp.currentRoute);
  await PushNotificationService.instance.initialize();

  runApp(
    ProviderScope(
      overrides: buildAppOverrides(),
      child: const EvikApp(),
    ),
  );
}

class EvikApp extends StatelessWidget {
  const EvikApp({super.key});

  static void navigateFromNotification(String route) {
    _router.go(route);
  }

  static String? currentRoute() {
    return _router.routerDelegate.currentConfiguration.uri.toString();
  }

  static final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _LaunchScreen()),
      GoRoute(
          path: '/order/pickup',
          builder: (_, __) => const PickupLocationScreen()),
      GoRoute(
          path: '/order/destination',
          builder: (_, __) => const DestinationLocationScreen()),
      GoRoute(
          path: '/order/vehicle',
          builder: (_, __) => const VehicleSelectionScreen()),
      GoRoute(
          path: '/order/tow-truck',
          builder: (_, __) => const TowTruckSelectionScreen()),
      GoRoute(
          path: '/order/search',
          builder: (_, __) => const DriverSearchScreen()),
      GoRoute(
          path: '/order/driver-info',
          builder: (_, __) => const DriverInfoScreen()),
      GoRoute(
          path: '/order/tracking', builder: (_, __) => const TrackingScreen()),
      GoRoute(
          path: '/order/payment-confirmation',
          builder: (_, __) => const PaymentConfirmationScreen()),
      // TODO: remove when review screen is confirmed
      // GoRoute(
      //     path: '/order/completion',
      //     builder: (_, __) => const OrderCompletionScreen()),
      GoRoute(
          path: '/order/review/:orderId',
          builder: (_, state) => OrderReviewScreen(
                orderId: state.pathParameters['orderId']!,
              )),
      GoRoute(
          path: '/order/rating',
          builder: (_, __) => const DriverRatingScreen()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Авро',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: _router,
    );
  }
}

class _LaunchScreen extends StatefulWidget {
  const _LaunchScreen();

  @override
  State<_LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<_LaunchScreen> {
  static bool _didShowLaunchSplash = false;

  late bool _showSplash = !_didShowLaunchSplash;

  @override
  void initState() {
    super.initState();
    if (_showSplash) {
      _finishSplash();
    }
  }

  Future<void> _finishSplash() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _didShowLaunchSplash = true;
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: _showSplash
            ? const _SplashScreen(key: ValueKey<String>('launch-splash'))
            : const _AppRouter(key: ValueKey<String>('app-router')),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/img/load.png',
              width: 160,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            Text(
              'Авро',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0B1220),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const bool _skipAuthForDevelopment = bool.fromEnvironment(
  'EVIK_SKIP_AUTH',
  defaultValue: false,
);

class _AppRouter extends ConsumerStatefulWidget {
  const _AppRouter({super.key});

  @override
  ConsumerState<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<_AppRouter> {
  // Guards against repeated GoRouter navigation when bootstrap re-emits.
  String? _redirectedForOrderId;

  @override
  Widget build(BuildContext context) {
    // Dev bypass: skip onboarding/auth and land directly on the client main
    // screen. Enabled via --dart-define=EVIK_SKIP_AUTH=true.
    if (_skipAuthForDevelopment) {
      return _homeFor(UserRole.client);
    }

    // Обычная логика авторизации
    final authState = ref.watch(authProvider);
    final currentUser = ref.watch(currentUserProvider);
    final selectedRole = ref.watch(selectedOnboardingRoleProvider);

    // Hold on the splash while persisted session is being restored,
    // so a signed-in user never briefly sees the auth screen.
    if (authState.isRestoring) {
      return const _SplashScreen(key: ValueKey<String>('restore-splash'));
    }

    if (authState.hadPersistedSession && !authState.isAuthenticated) {
      return const OfflineSosScreen();
    }

    if (authState.isAuthenticated && currentUser != null) {
      // Bootstrap fetch of any non-terminal order so the router can
      // resume the user where they left off after an app restart.
      final bootstrap = ref.watch(activeOrderBootstrapProvider);
      return bootstrap.when(
        loading: () =>
            const _SplashScreen(key: ValueKey<String>('bootstrap-splash')),
        // Errors are non-fatal — fall through to the default home shell
        // so a transient network failure never traps the user on a splash.
        error: (_, __) => _homeFor(currentUser.role),
        data: (order) => _routeForRestoredOrder(currentUser.role, order),
      );
    }

    if (authState.isCodeSent) {
      return const SmsVerificationScreen();
    }

    if (selectedRole == null) {
      return const RoleSelectionScreen();
    }

    return AuthScreen(initialRole: selectedRole);
  }

  Widget _routeForRestoredOrder(UserRole role, Order? order) {
    if (order == null) {
      _redirectedForOrderId = null;
      return _homeFor(role);
    }

    if (role == UserRole.driver) {
      // Driver active-order UI is owned by ActiveOrderScreen and reads its
      // state from newDriverProvider — surface it directly here so the
      // driver lands on the active order instead of the home dashboard.
      return Theme(
        data: AppTheme.driver(),
        child: const ActiveOrderScreen(),
      );
    }

    // Client: GoRouter owns the order flow routes, so push via go() and
    // render a splash this frame to avoid a flash of ClientAppShell.
    final target = switch (order.status) {
      OrderStatus.searching => '/order/search',
      OrderStatus.assigned ||
      OrderStatus.onWay ||
      OrderStatus.arrived ||
      OrderStatus.evacuating =>
        '/order/tracking',
      OrderStatus.awaitingPayment => '/order/payment-confirmation',
      OrderStatus.completed || OrderStatus.cancelled => null,
    };

    if (target == null) {
      return _homeFor(role);
    }

    if (_redirectedForOrderId != order.id) {
      _redirectedForOrderId = order.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        EvikApp._router.go(target);
      });
    }
    return const _SplashScreen(key: ValueKey<String>('redirect-splash'));
  }

  Widget _homeFor(UserRole role) {
    if (role == UserRole.driver) {
      return const DriverScreen();
    }
    return const ClientAppShell();
  }
}
