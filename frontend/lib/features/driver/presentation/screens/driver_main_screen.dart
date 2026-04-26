import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../domain/entities/driver_work_state.dart';
import '../providers/new_driver_provider.dart';
import 'new_driver_home_screen.dart';
import 'active_order_screen.dart';
import 'driver_orders_history_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_profile_screen.dart';

class DriverMainScreen extends ConsumerStatefulWidget {
  const DriverMainScreen({super.key});

  @override
  ConsumerState<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends ConsumerState<DriverMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);

    // Если есть активный заказ, показываем экран активного заказа вместо главной
    final hasActiveOrder = driverState.workState.hasActiveOrder;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          hasActiveOrder
              ? const ActiveOrderScreen()
              : const NewDriverHomeScreen(),
          DriverOrdersHistoryScreen(
            onGoHome: () => setState(() => _currentIndex = 0),
          ),
          const DriverEarningsScreen(),
          const DriverProfileScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(hasActiveOrder),
    );
  }

  Widget _buildBottomNavigation(bool hasActiveOrder) {
    return Container(
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: hasActiveOrder ? Icons.drive_eta : Icons.home_outlined,
                activeIcon: hasActiveOrder ? Icons.drive_eta : Icons.home,
                label: hasActiveOrder ? 'Заказ' : 'Главная',
                index: 0,
                isActive: _currentIndex == 0,
                badge: hasActiveOrder ? '1' : null,
              ),
              _buildNavItem(
                icon: Icons.history_outlined,
                activeIcon: Icons.history,
                label: 'Заказы',
                index: 1,
                isActive: _currentIndex == 1,
              ),
              _buildNavItem(
                icon: Icons.attach_money,
                activeIcon: Icons.monetization_on,
                label: 'Доходы',
                index: 2,
                isActive: _currentIndex == 2,
              ),
              _buildNavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Профиль',
                index: 3,
                isActive: _currentIndex == 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required bool isActive,
    String? badge,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _currentIndex = index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Icon(
                      isActive ? activeIcon : icon,
                      color: isActive
                          ? EvikColors.accentOrange
                          : EvikColors.gray600,
                      size: 24,
                    ),
                    if (badge != null)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: EvikColors.errorRed,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: EvikColors.primaryWhite,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color:
                        isActive ? EvikColors.accentOrange : EvikColors.gray600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
