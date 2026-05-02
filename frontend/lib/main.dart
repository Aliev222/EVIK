import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/constants/app_constants.dart';
import 'core/error/global_error_handler.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/evik_tokens.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();
  AndroidYandexMap.useAndroidViewSurface = false;

  // Debug info removed for clean testing

  // Initialize global error handler
  GlobalErrorHandler.initialize();

  runApp(
    ProviderScope(
      overrides: buildAppOverrides(),
      child: const EvikApp(),
    ),
  );
}

class EvikApp extends StatelessWidget {
  const EvikApp({super.key});

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
  bool _didPrepareSplash = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrepareSplash) return;
    _didPrepareSplash = true;
    _prepareSplash();
  }

  Future<void> _prepareSplash() async {
    if (_didShowLaunchSplash) {
      WidgetsBinding.instance.allowFirstFrame();
      return;
    }

    try {
      await precacheImage(
        const AssetImage('assets/img/load.png'),
        context,
      );
    } finally {
      WidgetsBinding.instance.allowFirstFrame();
    }

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    _didShowLaunchSplash = true;
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: EvikDurations.slow,
      switchInCurve: EvikCurves.enter,
      switchOutCurve: EvikCurves.exit,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: _showSplash
          ? const _SplashScreen(key: ValueKey<String>('launch-splash'))
          : const _AppRouter(key: ValueKey<String>('app-router')),
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
                                    alpha: 0.4 * _blinkOpacity.value),
                                blurRadius: 120,
                                offset: const Offset(0, 40),
                                spreadRadius: 20,
                              ),
                              BoxShadow(
                                color: const Color(0xFFFF6B35).withValues(
                                    alpha: 0.2 * _blinkOpacity.value),
                                blurRadius: 240,
                                offset: const Offset(0, 0),
                                spreadRadius: 60,
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
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 24.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x + 1, y + 1), 1, paint);
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

class _AppRouter extends ConsumerWidget {
  const _AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Быстрый режим тестирования - пропуск авторизации
    if (AppConstants.skipAuth) {
      final selectedRole = ref.watch(selectedOnboardingRoleProvider);

      if (selectedRole == UserRole.driver) {
        return const DriverScreen(); // Водительский интерфейс
      } else if (selectedRole == UserRole.client) {
        return const ClientAppShell(); // Клиентский интерфейс
      }

      // Показать выбор роли для тестирования
      return const RoleSelectionScreen();
    }

    // Обычная логика авторизации
    final authState = ref.watch(authProvider);
    final currentUser = ref.watch(currentUserProvider);
    final selectedRole = ref.watch(selectedOnboardingRoleProvider);

    if (authState.isAuthenticated && currentUser != null) {
      if (currentUser.role == UserRole.driver) {
        return const DriverScreen();
      }
      return const ClientAppShell();
    }

    if (authState.isCodeSent) {
      return const SmsVerificationScreen();
    }

    if (selectedRole == null) {
      return const RoleSelectionScreen();
    }

    return AuthScreen(initialRole: selectedRole);
  }
}
