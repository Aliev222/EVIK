import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/api_client_stub.dart'
    if (dart.library.io) 'core/network/api_client_io.dart'
    as platform_api;
import 'features/auth/domain/entities/user.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/driver/presentation/driver_screen.dart';
import 'features/client/presentation/screens/client_app_shell.dart';
import 'features/onboarding/presentation/screens/role_selection_screen.dart';

void main() {
  runApp(
    ProviderScope(
      child: const TestApp(),
    ),
  );
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Авро (Test)',
      theme: ThemeData.light(),
      debugShowCheckedModeBanner: false,
      home: const _TestRouter(),
    );
  }
}

class _TestRouter extends ConsumerStatefulWidget {
  const _TestRouter();

  @override
  ConsumerState<_TestRouter> createState() => _TestRouterState();
}

class _TestRouterState extends ConsumerState<_TestRouter> {
  bool _isRegistering = false;
  String? _registerError;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(selectedOnboardingRoleProvider);
    final authState = ref.watch(authProvider);

    if (_isRegistering) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Вход...'),
            ],
          ),
        ),
      );
    }

    if (_registerError != null) {
      return Scaffold(
        body: Center(
          child: Text('Ошибка: $_registerError'),
        ),
      );
    }

    if (authState.isAuthenticated && authState.user != null) {
      switch (authState.user!.role) {
        case UserRole.driver:
          return const DriverScreen();
        case UserRole.client:
          return const ClientAppShell();
        default:
          return const RoleSelectionScreen();
      }
    }

    if (role == null) {
      return const RoleSelectionScreen();
    }

    _autoRegister(role);
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Вход...'),
          ],
        ),
      ),
    );
  }

  void _autoRegister(UserRole role) {
    if (_isRegistering) return;
    setState(() => _isRegistering = true);

    final random = DateTime.now().millisecondsSinceEpoch;
    final phone = '+7999${random.toString().padLeft(10, '0')}';
    final apiClient = platform_api.createPlatformApiClient();

    apiClient.post('/api/v1/auth/register', {
      'phone': phone,
      'password': 'test1234',
      'role': role.name,
      'full_name': 'Тест ${role.name}',
    }).then((json) {
      if (!mounted) return;
      final tokens = json['tokens'] as Map<String, dynamic>;
      final token = tokens['access_token'] as String;
      final userJson = json['user'] as Map<String, dynamic>;
      final userId = userJson['id'] as String;

      final now = DateTime.now();
      ref.read(authProvider.notifier).state = AuthState(
        user: User(
          id: userId,
          phone: phone,
          role: role,
          fullName: 'Тест ${role.name}',
          isActive: true,
          createdAt: now,
          lastSeen: now,
        ),
        accessToken: token,
        isRestoring: false,
      );
      setState(() {
        _isRegistering = false;
      });
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() {
        _isRegistering = false;
        _registerError = error.toString();
      });
    });
  }
}
