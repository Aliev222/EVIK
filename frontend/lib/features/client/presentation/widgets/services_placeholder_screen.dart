import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/client/presentation/screens/service_detail_screen.dart';

class ServicesPlaceholderScreen extends StatelessWidget {
  const ServicesPlaceholderScreen({super.key});

  static const List<_ServiceItem> _services = [
    _ServiceItem(
      icon: Icons.tire_repair_rounded,
      label: 'Шиномонтаж',
      subtitle: 'Выездной сервис',
      description: 'Выездной шиномонтаж прямо на месте поломки. Замена колёс, ремонт проколов, балансировка.',
    ),
    _ServiceItem(
      icon: Icons.battery_charging_full_rounded,
      label: 'Не заводится',
      subtitle: 'Запуск двигателя',
      description: 'Прикуривание аккумулятора, диагностика на месте, запуск двигателя в любую погоду.',
    ),
    _ServiceItem(
      icon: Icons.bolt_rounded,
      label: 'Автоэлектрик',
      subtitle: 'Диагностика и ремонт',
      description: 'Выездной автоэлектрик: диагностика, ремонт проводки, замена предохранителей.',
    ),
    _ServiceItem(
      icon: Icons.local_gas_station_rounded,
      label: 'Подвоз топлива',
      subtitle: 'Быстрая доставка',
      description: 'Доставка бензина или дизеля прямо к вашей машине. Быстро и безопасно.',
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
            Text(
              'Услуги',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AvroClientColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Дополнительные услуги на дороге',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AvroClientColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            const _RoadmapAnnouncement(),
            const SizedBox(height: 20),
            ..._services.map((service) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ServiceCard(service: service),
            )),
            const SizedBox(height: 12),
            _PartnerSection(),
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
                child: Icon(service.icon, size: 28, color: AvroClientColors.accent),
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
              const Icon(Icons.chevron_right_rounded, color: AvroClientColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerSection extends StatelessWidget {
  const _PartnerSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: Column(
        children: [
          Icon(Icons.handshake_rounded, size: 48, color: AvroClientColors.accent),
          const SizedBox(height: 12),
          Text(
            'Вы мастер или владелец СТО?',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AvroClientColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Разместите свои услуги в Авро',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AvroClientColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => launchUrl(Uri.parse('https://t.me/avro_partners')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AvroClientColors.accent,
                foregroundColor: AvroClientColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                'Стать партнёром',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapAnnouncement extends StatelessWidget {
  const _RoadmapAnnouncement();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroClientColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AvroClientColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AvroClientColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.handshake_rounded,
              color: AvroClientColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Скоро — партнёры вашего города',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AvroClientColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AvroClientColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'скоро',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AvroClientColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Автосервисы, шиномонтаж, выездные мастера и доставка '
                  'топлива. Мы подключаем их к Авро — заказ будет '
                  'оформляться в пару нажатий.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AvroClientColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceItem {
  const _ServiceItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String description;
}
