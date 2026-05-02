import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import 'core/bootstrap/app_bootstrap.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();
  AndroidYandexMap.useAndroidViewSurface = false;

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EVIK',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: const _LaunchScreen(),
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
        const AssetImage('assets/img/startevik.png'),
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
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
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

    // Start animations
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _logoController.forward();
    });

    Future.delayed(const Duration(milliseconds: 950), () {
      if (mounted) _textController.forward();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
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
                // Logo
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _logoScale.value,
                      child: Opacity(
                        opacity: _logoOpacity.value,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 40,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            color: Colors.white,
                            size: 34,
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
                        'EVIK',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.05,
                          height: 1,
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
                          'СЕРВИС ЭВАКУАТОРОВ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.2,
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
    final authState = ref.watch(authProvider);
    final currentUser = ref.watch(currentUserProvider);
    final selectedRole = ref.watch(selectedOnboardingRoleProvider);

    if (authState.isAuthenticated && currentUser != null) {
      if (currentUser.role == UserRole.driver) {
        // ЗАГЛУШКА: пропускаем модерацию документов для тестирования
        // В реальном приложении здесь была бы проверка статуса модерации
        return const DriverScreen(); // Водительский интерфейс
      }

      return const ClientAppShell(); // Клиентский интерфейс
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
