import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/evik_tokens.dart';
import 'features/home/presentation/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();

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
  bool _showSplash = true;
  bool _didPrepareSplash = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrepareSplash) return;
    _didPrepareSplash = true;
    _prepareSplash();
  }

  Future<void> _prepareSplash() async {
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
          : const HomeScreen(key: ValueKey<String>('home-screen')),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return const SizedBox.expand(
            child: Image(
              image: AssetImage('assets/img/startevik.png'),
              fit: BoxFit.fitHeight,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
            ),
          );
        },
      ),
    );
  }
}
