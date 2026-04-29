import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/client_bottom_nav.dart';
import 'client_history_screen.dart';
import 'client_home_screen.dart';
import 'client_profile_screen.dart';
import 'client_wallet_screen.dart';

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
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _buildCurrentScreen(),
      ),
      bottomNavigationBar: ClientBottomNav(
        activeTab: _activeTab,
        onTabChanged: _switchToTab,
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
      case ClientTab.history:
        return ClientHistoryScreen(
          key: const ValueKey(ClientTab.history),
          onSwitchToHome: () => _switchToTab(ClientTab.home),
        );
      case ClientTab.wallet:
        return const ClientWalletScreen(key: ValueKey(ClientTab.wallet));
      case ClientTab.profile:
        return const ClientProfileScreen(key: ValueKey(ClientTab.profile));
    }
  }
}
