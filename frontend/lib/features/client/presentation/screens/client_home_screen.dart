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
      body: Container(
        color: EvikColors.primaryWhite,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  onNotificationsPressed: () =>
                      _showComingSoon('Уведомления — скоро будет доступно'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: _SosSlider(
                    onConfirmed: () =>
                        _showComingSoon('SOS — скоро будет доступно'),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  flex: 4,
                  fit: FlexFit.tight,
                  child: _LocationMapCard(
                    lat: lat,
                    lng: lng,
                    address: address,
                    isLoading: isLoading,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  flex: 4,
                  fit: FlexFit.tight,
                  child: _QuickServicesGrid(
                    onServiceTap: () =>
                        _showComingSoon('Скоро будет доступно'),
                  ),
                ),
                const SizedBox(height: 8),
                _CallTowTruckButton(onPressed: _openPickupSelection),
              ],
            ),
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
    return Container(
      height: 64,
      width: double.infinity,
      decoration: BoxDecoration(
        color: EvikColors.accentOrangeAction,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
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
    _QuickService(
      icon: Icons.tire_repair_rounded,
      label: 'Шиномонтаж',
      subtitle: 'Выездной сервис',
    ),
    _QuickService(
      icon: Icons.battery_charging_full_rounded,
      label: 'Не заводится',
      subtitle: 'Запуск двигателя',
    ),
    _QuickService(
      icon: Icons.bolt_rounded,
      label: 'Автоэлектрик',
      subtitle: 'Диагностика и ремонт',
    ),
    _QuickService(
      icon: Icons.local_gas_station_rounded,
      label: 'Подвоз топлива',
      subtitle: 'Быстрая доставка',
    ),
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
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
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
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickService {
  const _QuickService({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String subtitle;
}

class _QuickServiceCard extends StatelessWidget {
  const _QuickServiceCard({required this.service, required this.onTap});

  final _QuickService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EvikColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EvikColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  service.icon,
                  size: 24,
                  color: EvikColors.accentOrange,
                ),
                const SizedBox(height: 8),
                Text(
                  service.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EvikColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  service.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: EvikColors.textHint,
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

class _LocationMapCard extends StatelessWidget {
  const _LocationMapCard({
    required this.lat,
    required this.lng,
    required this.address,
    required this.isLoading,
  });

  static const double _overlayHeight = 70;

  final double lat;
  final double lng;
  final String address;
  final bool isLoading;

  String get _city {
    final parts = address.split(',');
    if (parts.length < 2) return 'Москва';
    return parts.last.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            EvikOsmMapView(
              key: const ValueKey('client_home_map'),
              initialLat: lat,
              initialLng: lng,
              initialZoom: 15,
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: Container(
                  height: _overlayHeight,
                  color: EvikColors.primaryWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLoading ? 'Определяем адрес...' : address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: EvikColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: EvikColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: EvikColors.textSecondary,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosSlider extends StatefulWidget {
  const _SosSlider({required this.onConfirmed});

  final VoidCallback onConfirmed;

  @override
  State<_SosSlider> createState() => _SosSliderState();
}

class _SosSliderState extends State<_SosSlider>
    with SingleTickerProviderStateMixin {
  static const double _thumbSize = 36;
  // Минимальная область нажатия 44×44 при визуальном размере 36
  static const double _hitSize = 44;
  static const double _thumbPadding = 8;
  static const double _completeThreshold = 0.85;

  late final AnimationController _snapController;
  double _dragPixels = 0;
  double _trackWidth = 0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double get _maxDrag =>
      (_trackWidth - _hitSize - _thumbPadding * 2).clamp(0, double.infinity);

  void _onDragUpdate(DragUpdateDetails details) {
    final maxDrag = _maxDrag;
    if (maxDrag <= 0) return;
    setState(() {
      _dragPixels = (_dragPixels + details.delta.dx).clamp(0, maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final maxDrag = _maxDrag;
    if (maxDrag <= 0) return;
    final completed = _dragPixels >= maxDrag * _completeThreshold;
    if (completed) {
      _snapTo(maxDrag, onDone: () {
        widget.onConfirmed();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _snapTo(0);
        });
      });
    } else {
      _snapTo(0);
    }
  }

  void _snapTo(double target, {VoidCallback? onDone}) {
    final animation = Tween<double>(begin: _dragPixels, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    void listener() {
      setState(() => _dragPixels = animation.value);
    }

    animation.addListener(listener);
    _snapController
      ..reset()
      ..forward().whenCompleteOrCancel(() {
        animation.removeListener(listener);
        onDone?.call();
      });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        final maxDrag = _maxDrag;
        final progress = maxDrag > 0 ? (_dragPixels / maxDrag).clamp(0.0, 1.0) : 0.0;
        return Container(
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0E8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EvikColors.accentOrange, width: 1),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text(
                    'Потяните для вызова SOS',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: EvikColors.accentOrange,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _thumbPadding,
                  vertical: 4,
                ),
                child: Transform.translate(
                  offset: Offset(_dragPixels, 0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: SizedBox(
                      width: _hitSize,
                      height: _hitSize,
                      child: Center(
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: const BoxDecoration(
                            color: EvikColors.accentOrangeAction,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: EvikColors.primaryWhite,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
