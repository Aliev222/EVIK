import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/features/client/presentation/screens/service_detail_screen.dart';

class ServicesPlaceholderScreen extends StatelessWidget {
  const ServicesPlaceholderScreen({super.key});

  static const List<_ServiceItem> _services = [
    _ServiceItem(
      icon: Icons.tire_repair_rounded,
      asset: 'assets/img/services/tire_service.png',
      label: 'Шиномонтаж',
      subtitle: 'Выездной сервис',
      description:
          'Выездной шиномонтаж прямо на месте поломки. Замена колёс, ремонт проколов, балансировка.',
    ),
    _ServiceItem(
      icon: Icons.battery_charging_full_rounded,
      asset: 'assets/img/services/jump_start.png',
      label: 'Не заводится',
      subtitle: 'Запуск двигателя',
      description:
          'Прикуривание аккумулятора, диагностика на месте, запуск двигателя в любую погоду.',
    ),
    _ServiceItem(
      icon: Icons.bolt_rounded,
      asset: 'assets/img/services/auto_electrician.png',
      label: 'Автоэлектрик',
      subtitle: 'Диагностика и ремонт',
      description:
          'Выездной автоэлектрик: диагностика, ремонт проводки, замена предохранителей.',
    ),
    _ServiceItem(
      icon: Icons.local_gas_station_rounded,
      asset: 'assets/img/services/fuel_delivery.png',
      label: 'Подвоз топлива',
      subtitle: 'Быстрая доставка',
      description:
          'Доставка бензина или дизеля прямо к вашей машине. Быстро и безопасно.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Назад',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Text(
                  'Услуги',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AvroClientColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Помощь на дороге рядом с вами',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AvroClientColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ..._services.map((service) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ServiceCard(service: service),
                )),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final _ServiceItem service;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroClientColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(
                title: service.label,
                subtitle: service.subtitle,
                description: service.description,
                icon: service.icon,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AvroClientColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Image.asset(service.asset, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.label,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AvroClientColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      service.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AvroClientColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AvroClientColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceItem {
  const _ServiceItem({
    required this.icon,
    required this.asset,
    required this.label,
    required this.subtitle,
    required this.description,
  });

  final IconData icon;
  final String asset;
  final String label;
  final String subtitle;
  final String description;
}
