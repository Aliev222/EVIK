import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/app_theme.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'active_order_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_orders_history_screen.dart';
import 'driver_profile_screen.dart';
import 'new_driver_home_screen.dart';

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
    final hasActiveOrder = driverState.workState.hasActiveOrder;

    return Theme(
      data: AppTheme.driver(),
      child: Scaffold(
      extendBody: true,
      body: RepaintBoundary(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            RepaintBoundary(
              child: hasActiveOrder
                  ? const ActiveOrderScreen()
                  : const NewDriverHomeScreen(),
            ),
            RepaintBoundary(
              child: DriverOrdersHistoryScreen(
                onGoHome: () => setState(() => _currentIndex = 0),
              ),
            ),
            const RepaintBoundary(child: DriverEarningsScreen()),
            const RepaintBoundary(child: DriverProfileScreen()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(hasActiveOrder),
    ),
    );
  }

  Widget _buildBottomNavigation(bool hasActiveOrder) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AvroDriverColors.navBar,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
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
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isActive ? activeIcon : icon,
                      color: isActive
                          ? AvroDriverColors.accent
                          : AvroDriverColors.grayHint,
                      size: 24,
                    ),
                    if (badge != null)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AvroDriverColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: AvroDriverColors.textPrimary,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color:
                        isActive ? AvroDriverColors.accent : AvroDriverColors.grayHint,
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
