import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/constants/app_constants.dart';
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
import 'features/client/presentation/screens/pickup_location_screen.dart';
import 'features/client/presentation/screens/destination_location_screen.dart';
import 'features/client/presentation/screens/vehicle_selection_screen.dart';
import 'features/client/presentation/screens/tow_truck_selection_screen.dart';
import 'features/client/presentation/screens/driver_search_screen.dart';
import 'features/client/presentation/screens/driver_info_screen.dart';
import 'features/client/presentation/screens/tracking_screen.dart';
import 'features/client/presentation/screens/order_completion_screen.dart';
import 'features/client/presentation/screens/driver_rating_screen.dart';
import 'features/driver/presentation/screens/active_order_screen.dart';
import 'features/order/domain/entities/order.dart';
import 'features/order/presentation/providers/order_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

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
          path: '/order/completion',
          builder: (_, __) => const OrderCompletionScreen()),
      GoRoute(
          path: '/order/rating',
          builder: (_, __) => const DriverRatingScreen()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tow Truck',
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

class _SplashScreen extends StatefulWidget {
  const _SplashScreen({super.key});

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _blinkController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _blinkOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _logoScale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: const Cubic(0.16, 1, 0.3, 1),
    ));

    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    ));

    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_textController);

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOut,
    ));

    _blinkOpacity = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _logoController.forward();
    });

    Future.delayed(const Duration(milliseconds: 950), () {
      if (mounted) {
        _textController.forward();
        _blinkController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // Subtle dot grid background
          Positioned.fill(
            child: CustomPaint(
              painter: _DotGridPainter(),
            ),
          ),

          // Warm glow effect
          AnimatedBuilder(
            animation: _logoController,
            builder: (context, child) {
              return Positioned(
                right: -80,
                top: -80,
                child: Transform.scale(
                  scale: _logoScale.value,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF6B35).withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with blinking effect
                AnimatedBuilder(
                  animation:
                      Listenable.merge([_logoController, _blinkController]),
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _logoScale.value,
                      child: Opacity(
                        opacity: _logoOpacity.value * _blinkOpacity.value,
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B35).withValues(
                                    alpha: 0.25 * _blinkOpacity.value),
                                blurRadius: 60,
                                offset: const Offset(0, 20),
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/img/load.png',
                            width: 240,
                            height: 240,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 14),

                // EVIK text
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: const Text(
                        'TOW TRUCK',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.5,
                          height: 1.1,
                          fontFamily: 'Inter',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Bottom tagline and progress
          Positioned(
            bottom: 88,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _textController,
              builder: (context, child) {
                return SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: const Column(
                      children: [
                        Text(
                          'TOWING SERVICE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 20),
                        _ProgressBar(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    const spacing = 32.0;
    final maxDots = ((size.width / spacing) * (size.height / spacing)).round();
    if (maxDots > 100) return; // Skip if too many dots

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x + 1, y + 1), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar();

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _progress = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(1),
        ),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35),
                borderRadius: BorderRadius.circular(1),
              ),
              width: 44 * _progress.value,
              height: 2,
            );
          },
        ),
      ),
    );
  }
}

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
    // Быстрый режим тестирования - пропуск авторизации
    if (AppConstants.skipAuth) {
      final selectedRole = ref.watch(selectedOnboardingRoleProvider);
      final authState = ref.watch(authProvider);
      final currentUser = ref.watch(currentUserProvider);

      if (selectedRole == null) {
        return const RoleSelectionScreen();
      }

      final hasActiveTestSession = currentUser?.role == selectedRole &&
          authState.accessToken != null &&
          authState.accessToken!.isNotEmpty;
      if (!hasActiveTestSession) {
        if (!authState.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(authProvider.notifier).signInForTesting(selectedRole);
          });
        }
        return _TestAuthScreen(
          errorMessage: authState.errorMessage,
          onRetry: () =>
              ref.read(authProvider.notifier).signInForTesting(selectedRole),
        );
      }

      if (selectedRole == UserRole.driver) {
        return const DriverScreen();
      }
      return const ClientAppShell();
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
      return const ActiveOrderScreen();
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

class _TestAuthScreen extends StatelessWidget {
  const _TestAuthScreen({
    this.errorMessage,
    required this.onRetry,
  });

  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Готовим тестовый профиль',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ] else ...[
                  Text(
                    'Не удалось войти в тестовый профиль',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Повторить'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
