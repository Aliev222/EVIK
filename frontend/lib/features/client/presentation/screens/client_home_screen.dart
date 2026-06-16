import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({
    super.key,
    this.onProfilePressed,
  });

  final VoidCallback? onProfilePressed;

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  void _openPickupSelection() {
    ref.read(orderFlowProvider.notifier).startOrderFlow();
    context.push('/order/pickup');
  }

  void _showComingSoon(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: EvikColors.primaryWhite,
            ),
          ),
          backgroundColor: EvikColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final location =
        ref.watch(orderFlowProvider.select((state) => state.pickupLocation));
    final isLoading =
        ref.watch(orderFlowProvider.select((state) => state.isLoading));
    final address = _cleanAddress(location?.displayAddress);
    final lat = location?.latitude ?? AppConstants.moscowLat;
    final lng = location?.longitude ?? AppConstants.moscowLng;

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                onNotificationsPressed: () =>
                    _showComingSoon('Уведомления — скоро будет доступно'),
              ),
              const SizedBox(height: 24),
              Text(
                'Чем помочь?',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: EvikColors.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Мы рядом и готовы помочь',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: EvikColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              _CallTowTruckButton(onPressed: _openPickupSelection),
              const SizedBox(height: 24),
              _QuickServicesGrid(
                onServiceTap: () => _showComingSoon('Скоро будет доступно'),
              ),
              const SizedBox(height: 24),
              _LocationMapCard(
                lat: lat,
                lng: lng,
                address: address,
                isLoading: isLoading,
              ),
              const SizedBox(height: 16),
              _SosCard(
                onPressed: () => _showComingSoon('SOS — скоро будет доступно'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cleanAddress(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return 'Москва, ЦАО';
    if (text.contains('Р') || text.contains('СЃ')) return 'Москва, ЦАО';
    if (text == 'Адрес не указан') return 'Москва, ЦАО';
    return text;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNotificationsPressed});

  final VoidCallback onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: EvikColors.accentOrange,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            color: EvikColors.primaryWhite,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Авро',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: EvikColors.textPrimary,
          ),
        ),
        const Spacer(),
        Material(
          color: EvikColors.cardBackground,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onNotificationsPressed,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.notifications_none_rounded,
                color: EvikColors.textPrimary,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallTowTruckButton extends StatelessWidget {
  const _CallTowTruckButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: Material(
        color: EvikColors.accentOrange,
        borderRadius: BorderRadius.circular(18),
        elevation: 8,
        shadowColor: EvikColors.accentOrange.withValues(alpha: 0.32),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping_rounded,
                  color: EvikColors.primaryWhite,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Вызвать эвакуатор',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: EvikColors.primaryWhite,
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: EvikColors.primaryWhite.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: EvikColors.primaryWhite,
                    size: 22,
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

class _QuickServicesGrid extends StatelessWidget {
  const _QuickServicesGrid({required this.onServiceTap});

  final VoidCallback onServiceTap;

  static const List<_QuickService> _services = <_QuickService>[
    _QuickService(icon: Icons.tire_repair_rounded, label: 'Шиномонтаж'),
    _QuickService(
        icon: Icons.battery_charging_full_rounded, label: 'Не заводится'),
    _QuickService(icon: Icons.bolt_rounded, label: 'Автоэлектрик'),
    _QuickService(
        icon: Icons.local_gas_station_rounded, label: 'Подвоз топлива'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Быстрые услуги',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: EvikColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickServiceCard(
                service: _services[0],
                onTap: onServiceTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickServiceCard(
                service: _services[1],
                onTap: onServiceTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickServiceCard(
                service: _services[2],
                onTap: onServiceTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickServiceCard(
                service: _services[3],
                onTap: onServiceTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickService {
  const _QuickService({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _QuickServiceCard extends StatelessWidget {
  const _QuickServiceCard({required this.service, required this.onTap});

  final _QuickService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: EvikColors.primaryWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  service.icon,
                  color: EvikColors.accentOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  service.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: EvikColors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationMapCard extends StatelessWidget {
  const _LocationMapCard({
    required this.lat,
    required this.lng,
    required this.address,
    required this.isLoading,
  });

  final double lat;
  final double lng;
  final String address;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: EvikOsmMapView(
              key: const ValueKey('client_home_map'),
              initialLat: lat,
              initialLng: lng,
              initialZoom: 15.5,
              showControls: false,
              showLocationButton: false,
              showUserLocation: false,
              fitToMarkers: false,
              markers: [
                EvikMapMarker(
                  lat: lat,
                  lng: lng,
                  title: address,
                  color: EvikColors.accentOrange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              color: EvikColors.accentOrange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ваше местоположение',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: EvikColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLoading ? 'Определяем адрес...' : address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: EvikColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SosCard extends StatelessWidget {
  const _SosCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.sosRed,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: EvikColors.primaryWhite.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: EvikColors.primaryWhite,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Нужна срочная помощь?',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: EvikColors.primaryWhite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Перейти в Авро SOS',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: EvikColors.primaryWhite.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: EvikColors.primaryWhite,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
