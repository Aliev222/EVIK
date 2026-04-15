import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_screen.dart';

void main() {
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

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Image(
            image: AssetImage('assets/img/startevik.png'),
            width: 300,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}
