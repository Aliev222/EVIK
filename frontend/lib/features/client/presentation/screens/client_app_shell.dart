import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/connectivity_provider.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/core/theme/app_theme.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/client_bottom_nav.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/services_placeholder_screen.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/shared/widgets/offline_sos_screen.dart';
import 'client_history_screen.dart';
import 'client_home_screen.dart';
import 'client_profile_screen.dart';

class ClientAppShell extends ConsumerStatefulWidget {
  const ClientAppShell({super.key});

  @override
  ConsumerState<ClientAppShell> createState() => _ClientAppShellState();
}

class _ClientAppShellState extends ConsumerState<ClientAppShell> {
  ClientTab _activeTab = ClientTab.home;

  void _switchToTab(ClientTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    final wsStatus = ref.watch(webSocketStatusProvider).valueOrNull;
    final offline = !isOnline;
    final showBanner =
        offline ||
        (wsStatus != null && wsStatus != WebSocketConnectionStatus.connected);

    return Theme(
      data: AppTheme.client(),
      child: Scaffold(
      body: Column(
        children: [
          if (showBanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              color: AvroClientColors.accent,
              child: Text(
                offline
                    ? 'Нет подключения к интернету'
                    : wsStatus == WebSocketConnectionStatus.connecting
                        ? 'Подключаемся...'
                        : 'Нет соединения',
                style: TextStyle(color: AvroClientColors.background, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: RepaintBoundary(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: RepaintBoundary(child: _buildCurrentScreen()),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClientBottomNav(
        activeTab: _activeTab,
        onTabChanged: _switchToTab,
        onSosActivated: _openSos,
      ),
    ),
    );
  }

  void _openSos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OfflineSosScreen(isSosOnly: true),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_activeTab) {
      case ClientTab.home:
        return ClientHomeScreen(
          key: const ValueKey(ClientTab.home),
          onProfilePressed: () => _switchToTab(ClientTab.profile),
        );
      case ClientTab.services:
        return const ServicesPlaceholderScreen(
          key: ValueKey(ClientTab.services),
        );
      case ClientTab.history:
        return ClientHistoryScreen(
          key: const ValueKey(ClientTab.history),
          onSwitchToHome: () => _switchToTab(ClientTab.home),
        );
      case ClientTab.profile:
        return const ClientProfileScreen(key: ValueKey(ClientTab.profile));
    }
  }
}
