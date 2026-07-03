import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

enum ClientTab { home, services, history, profile }

class ClientBottomNav extends StatelessWidget {
  const ClientBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  final ClientTab activeTab;
  final ValueChanged<ClientTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            _NavItem(
              tab: ClientTab.home,
              activeTab: activeTab,
              icon: Icons.home_rounded,
              label: 'Главная',
              onTap: onTabChanged,
            ),
            _NavItem(
              tab: ClientTab.services,
              activeTab: activeTab,
              icon: Icons.grid_view_rounded,
              label: 'Услуги',
              onTap: onTabChanged,
            ),
            _NavItem(
              tab: ClientTab.history,
              activeTab: activeTab,
              icon: Icons.receipt_long_rounded,
              label: 'Заказы',
              onTap: onTabChanged,
            ),
            _NavItem(
              tab: ClientTab.profile,
              activeTab: activeTab,
              icon: Icons.person_rounded,
              label: 'Профиль',
              onTap: onTabChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.activeTab,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final ClientTab tab;
  final ClientTab activeTab;
  final IconData icon;
  final String label;
  final ValueChanged<ClientTab> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = tab == activeTab;
    final color = isActive ? AvroClientColors.accent : AvroClientColors.textSecondary;

    return Expanded(
      child: SizedBox(
        height: 72,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(tab);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 23, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
