import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/shared/providers/service_area_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/pulsing_location_dot.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/service_detail_screen.dart';
import 'package:tow_truck_frontend/shared/widgets/feature_announcement_sheet.dart';

enum _LocationState { initial, determining, unavailable, available }

String _cityOf(String address) {
  final parts = address.split(',');
  if (parts.length < 2) return 'Махачкала';
  final city = parts.last.trim();
  return city.isEmpty ? 'Махачкала' : city;
}

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({
    super.key,
    this.onProfilePressed,
  });

  final VoidCallback? onProfilePressed;

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen>
    with WidgetsBindingObserver {
  _LocationState _locationState = _LocationState.initial;
  bool _detectionAttempted = false;
  bool _addressDetectionInFlight = false;
  double? _lastPositionLat;
  double? _lastPositionLng;

  /// Visible gap between the services card's bottom edge and the top edge of
  /// the bottom nav pill. Measured empirically in the real composition
  /// (ClientAppShell Scaffold + extendBody + ClientBottomNav): the body is
  /// laid out behind the navbar with its own bottom padding removed, and
  /// `Positioned.bottom` in this home Stack is measured from that extended
  /// body bottom, so the gap equals this constant exactly (verified on
  /// padding.bottom = 0 and = 34). The card and the nav pill share no
  /// coordinate math — the constant IS the visible gap.
  static const double _servicesCardBottomGap = 15;
  static const double _servicesCardHeight = 160;
  static const double _myLocationButtonGap = 12;
  static const double _myLocationButtonSize = 48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Soft refresh on app resume: reverse-geocodes the last known position
  /// again (no new GPS request), so the address card stays fresh without a
  /// continuous high-accuracy stream.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAddress();
    }
  }

  Future<void> _initLocation() async {
    setState(() => _locationState = _LocationState.determining);

    final permission = await LocationService.requestLocationPermission();

    if (!mounted) return;

    switch (permission) {
      case PermissionResult.serviceDisabled:
        _locationState = _LocationState.unavailable;
        _showServiceDisabledDialog();
        return;

      case PermissionResult.denied:
        _locationState = _LocationState.unavailable;
        _showLocationExplanationDialog();
        return;

      case PermissionResult.deniedForever:
        _locationState = _LocationState.unavailable;
        _showDeniedForeverDialog();
        return;

      case PermissionResult.granted:
        break;
    }

    // Instant paint: a cached fix renders the map marker right away; the
    // address bar shows "Определяем адрес…" until reverse geocoding finishes.
    final lastKnown = await LocationService.getLastKnownPosition();
    if (mounted && lastKnown != null) {
      _locationState = _LocationState.available;
      _lastPositionLat = lastKnown.latitude;
      _lastPositionLng = lastKnown.longitude;
      setState(() {});
    }

    await _resolveAndDetect();
  }

  /// Single fast GPS fix (cached first, then medium/high) followed by a single
  /// reverse-geocode pass. Never waits 10s on high accuracy to block first
  /// paint — the cached position is already on screen.
  Future<void> _resolveAndDetect() async {
    double lat;
    double lng;
    try {
      final pos = await LocationService.getCurrentPositionQuick();
      if (!mounted) return;
      _locationState = _LocationState.available;
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      if (!mounted) return;
      final cachedLat = _lastPositionLat;
      final cachedLng = _lastPositionLng;
      if (cachedLat == null || cachedLng == null) {
        _locationState = _LocationState.unavailable;
        setState(() {});
        return;
      }
      lat = cachedLat;
      lng = cachedLng;
    }
    _lastPositionLat = lat;
    _lastPositionLng = lng;
    _runAddressDetection(lat, lng);
    if (mounted) setState(() {});
  }

  /// Kicks off the service-area check and the reverse-geocoded address for the
  /// current position. Coordinates come from the caller's single GPS fix and
  /// are passed straight to [OrderFlowNotifier.detectCurrentLocation] so the
  /// backend reverse-geocodes them without a second GPS request.
  Future<void> _runAddressDetection(double lat, double lng) async {
    if (!mounted) return;
    _detectionAttempted = true;
    ref.read(serviceAreaProvider.notifier).checkServiceArea(lat, lng);
    if (_addressDetectionInFlight) return;
    _addressDetectionInFlight = true;
    try {
      await ref
          .read(orderFlowProvider.notifier)
          .detectCurrentLocation(lat: lat, lng: lng);
    } finally {
      _addressDetectionInFlight = false;
    }
  }

  /// Soft address refresh: re-resolves the last known position without a new
  /// GPS request. Used on address-bar tap and on app resume.
  void _refreshAddress() {
    final lat = _lastPositionLat;
    final lng = _lastPositionLng;
    if (lat == null || lng == null) {
      _initLocation();
      return;
    }
    _runAddressDetection(lat, lng);
  }

  void _retryAddressDetection() {
    final lat = _lastPositionLat;
    final lng = _lastPositionLng;
    if (lat == null || lng == null) {
      _initLocation();
      return;
    }
    _runAddressDetection(lat, lng);
    if (mounted) setState(() {});
  }

  void _showServiceDisabledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Геолокация отключена'),
        content: const Text(
          'Для работы приложения необходимо включить геолокацию на устройстве.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openLocationSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  void _showLocationExplanationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступ к геолокации'),
        content: const Text(
          'Авро использует ваше местоположение, чтобы определить адрес подачи эвакуатора.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _retryPermission();
            },
            child: const Text('Разрешить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Пока нет'),
          ),
        ],
      ),
    );
  }

  void _showDeniedForeverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Геолокация запрещена'),
        content: const Text(
          'Разрешите геолокацию в настройках приложения, чтобы Авро мог определить адрес подачи эвакуатора.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openAppSettings();
            },
            child: const Text('Настройки приложения'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryPermission() async {
    final permission = await LocationService.requestLocationPermission();
    if (!mounted) return;
    if (permission == PermissionResult.granted) {
      _locationState = _LocationState.determining;
      setState(() {});
      await _resolveAndDetect();
    } else if (permission == PermissionResult.deniedForever) {
      _locationState = _LocationState.unavailable;
      _showDeniedForeverDialog();
    } else {
      _locationState = _LocationState.unavailable;
    }
    if (mounted) setState(() {});
  }

  void _openPickupSelection() {
    ref.read(orderFlowProvider.notifier).startOrderFlow();
    context.push('/order/pickup');
  }

  void _openNotificationsAnnouncement() {
    FeatureAnnouncementSheet.show(
      context,
      const FeatureAnnouncementSheet(
        title: 'Уведомления',
        icon: Icons.notifications_none_rounded,
        description:
            'Будем сообщать о статусе заказа: когда эвакуатор назначен, '
            'в пути и работа завершена.',
        items: [
          'Push-уведомления о заказе',
          'SMS о статусе эвакуатора',
          'Новости и акции',
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location =
        ref.watch(orderFlowProvider.select((state) => state.pickupLocation));
    final orderLoading =
        ref.watch(orderFlowProvider.select((state) => state.isLoading));
    final serviceArea = ref.watch(serviceAreaProvider);

    final locationUnavailable = _locationState == _LocationState.unavailable;
    final addressMissing = location == null && !locationUnavailable;
    final addressFailed =
        addressMissing && _detectionAttempted && !orderLoading;
    final showAddressLoading = addressMissing && !addressFailed;

    String address;
    String city;
    VoidCallback? onRetryAddress;
    if (location != null) {
      address = location.displayAddress;
      city = _cityOf(address);
    } else if (locationUnavailable) {
      address = 'Местоположение недоступно';
      city = 'Укажите точку на карте';
    } else if (addressFailed) {
      address = 'Не удалось определить адрес';
      city = 'Проверьте подключение и повторите';
      onRetryAddress = _retryAddressDetection;
    } else {
      address = 'Определяем адрес…';
      city = '';
    }

    final lat = location?.latitude ??
        _lastPositionLat ??
        AppConstants.makhachkalaLat;
    final lng = location?.longitude ??
        _lastPositionLng ??
        AppConstants.makhachkalaLng;

    final outsideServiceArea =
        serviceArea.isChecked && !serviceArea.isAllowed;
    final canRequest = !locationUnavailable && !outsideServiceArea;

    final bottomInset = math.max(MediaQuery.of(context).padding.bottom, 8.0);
    // Floating services card + "my location" button anchors, measured from
    // the screen bottom, sharing the single safe-inset accounting above.
    final servicesTop = bottomInset + _servicesCardBottomGap + _servicesCardHeight;
    final locationButtonBottom = servicesTop + _myLocationButtonGap;
    final attributionBottom =
        locationButtonBottom + _myLocationButtonSize + 8;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _LocationMapCard(
              lat: lat,
              lng: lng,
              locationButtonBottomOffset: locationButtonBottom,
              attributionBottomOffset: attributionBottom,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      onNotificationsPressed: _openNotificationsAnnouncement,
                      onProfilePressed: widget.onProfilePressed,
                    ),
                    if (outsideServiceArea) ...[
                      const SizedBox(height: 8),
                      _ServiceAreaBanner(),
                    ],
                    if (locationUnavailable) ...[
                      const SizedBox(height: 8),
                      _LocationUnavailableBanner(),
                    ],
                    const SizedBox(height: 10),
                    _AddressBar(
                      address: address,
                      city: city,
                      isLoading: showAddressLoading,
                      onRetry: onRetryAddress,
                      onTap: _refreshAddress,
                      latitude: location?.latitude ?? _lastPositionLat,
                      longitude: location?.longitude ?? _lastPositionLng,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: servicesTop - _servicesCardHeight,
            child: _FloatingServicesCard(
              key: const ValueKey('client_services_card'),
              enabled: canRequest,
              onEvacTap: _openPickupSelection,
              onServiceTap: (service) {
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
            ),
          ),
        ],
      ),
    );
  }

  // TODO: fix UTF-8 encoding in geocoding response
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onNotificationsPressed,
    this.onProfilePressed,
  });

  final VoidCallback onNotificationsPressed;
  final VoidCallback? onProfilePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('client_home_logo'),
            borderRadius: BorderRadius.circular(8),
            onTap: onProfilePressed,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/img/app_icon_load_fg.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Авро',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AvroClientColors.textPrimary,
          ),
        ),
        const Spacer(),
        Material(
          color: AvroClientColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onNotificationsPressed,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.notifications_none_rounded,
                color: AvroClientColors.textPrimary,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceAreaBanner extends StatelessWidget {
  const _ServiceAreaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AvroClientColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AvroClientColors.background,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Авро пока не работает в вашем городе. Мы скоро появимся!',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AvroClientColors.background,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationUnavailableBanner extends StatelessWidget {
  const _LocationUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AvroClientColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_off_rounded,
            size: 20,
            color: AvroClientColors.background,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Местоположение недоступно. Разрешите геолокацию в настройках.',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AvroClientColors.background,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingServicesCard extends StatelessWidget {
  const _FloatingServicesCard({
    super.key,
    required this.enabled,
    required this.onEvacTap,
    required this.onServiceTap,
  });

  final bool enabled;
  final VoidCallback onEvacTap;
  final ValueChanged<_QuickService> onServiceTap;

  static const List<_QuickService> _services = <_QuickService>[
    _QuickService(
      icon: Icons.tire_repair_rounded,
      label: 'Шиномонтаж',
      subtitle: 'Выездной сервис',
      description: 'Выездной шиномонтаж прямо на месте поломки. Замена колёс, ремонт проколов, балансировка.',
    ),
    _QuickService(
      icon: Icons.battery_charging_full_rounded,
      label: 'Не заводится',
      subtitle: 'Запуск двигателя',
      description: 'Прикуривание аккумулятора, диагностика на месте, запуск двигателя в любую погоду.',
    ),
    _QuickService(
      icon: Icons.bolt_rounded,
      label: 'Автоэлектрик',
      subtitle: 'Диагностика и ремонт',
      description: 'Выездной автоэлектрик: диагностика, ремонт проводки, замена предохранителей.',
    ),
    _QuickService(
      icon: Icons.local_gas_station_rounded,
      label: 'Подвоз топлива',
      subtitle: 'Быстрая доставка',
      description: 'Доставка бензина или дизеля прямо к вашей машине. Быстро и безопасно.',
    ),
    _QuickService(
      icon: Icons.car_repair_rounded,
      label: 'Разблокировка',
      subtitle: 'Авто и сигнализация',
      description: 'Помощь при срабатывании сигнализации и блокировке руля или КПП.',
    ),
    _QuickService(
      icon: Icons.construction_rounded,
      label: 'Помощь на дороге',
      subtitle: 'Техническая помощь',
      description: 'Выезд мастера для решения любых технических проблем на месте.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Услуги',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AvroClientColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: _services.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _EvacPrimaryItem(
                    enabled: enabled,
                    onTap: onEvacTap,
                  );
                }
                final service = _services[index - 1];
                return _FloatingServiceItem(
                  service: service,
                  onTap: () => onServiceTap(service),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EvacPrimaryItem extends StatelessWidget {
  const _EvacPrimaryItem({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 128,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? AvroClientColors.accentBrand
              : AvroClientColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_rounded,
              size: 26,
              color: enabled
                  ? AvroClientColors.background
                  : AvroClientColors.tabInactive,
            ),
            const SizedBox(height: 8),
            Text(
              'Вызвать эвакуатор',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: enabled
                    ? AvroClientColors.background
                    : AvroClientColors.tabInactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingServiceItem extends StatelessWidget {
  const _FloatingServiceItem({required this.service, required this.onTap});

  final _QuickService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AvroClientColors.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(service.icon, size: 24, color: AvroClientColors.accent),
            const SizedBox(height: 8),
            Text(
              service.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: AvroClientColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Responds on pointer-down with a fast press-scale (≈0.97), restores on
/// release/cancel. Interruptible: the scale is a simple AnimatedScale whose
/// state is driven by gesture callbacks, so an interrupted press always
/// returns to rest cleanly.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final child = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: widget.child,
    );
    if (widget.onTap == null) {
      return Opacity(
        opacity: 0.6,
        child: child,
      );
    }
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: child,
    );
  }
}

class _QuickService {
  const _QuickService({
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

class _LocationMapCard extends StatelessWidget {
  const _LocationMapCard({
    required this.lat,
    required this.lng,
    this.locationButtonBottomOffset = 16,
    this.attributionBottomOffset = 16,
  });

  final double lat;
  final double lng;
  final double locationButtonBottomOffset;
  final double attributionBottomOffset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AvroClientColors.background,
      child: EvikOsmMapView(
        key: const ValueKey('client_home_map'),
        initialLat: lat,
        initialLng: lng,
        initialZoom: 15,
        showControls: false,
        showLocationButton: false,
        showUserLocation: false,
        showStandaloneLocationButton: true,
        locationButtonBottomOffset: locationButtonBottomOffset,
        fitToMarkers: false,
        attributionBottomOffset: attributionBottomOffset,
        markers: [
          // Own position: green radar-pulse dot (no orange pin).
          EvikMapMarker(
            lat: lat,
            lng: lng,
            child: const PulsingLocationDot(),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.address,
    required this.city,
    required this.isLoading,
    required this.onTap,
    this.onRetry,
    this.latitude,
    this.longitude,
  });

  final String address;
  final String city;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onRetry;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final hasCoordinates = latitude != null && longitude != null;
    final secondaryLine = hasCoordinates
        ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
        : city;

    return Material(
      color: AvroClientColors.background,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AvroClientColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AvroClientColors.accent,
                        ),
                      )
                    : const Icon(
                        Icons.my_location_rounded,
                        color: AvroClientColors.accent,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AvroClientColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondaryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AvroClientColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onRetry != null)
                Material(
                  color: AvroClientColors.accent.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRetry,
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.refresh_rounded,
                        color: AvroClientColors.accent,
                        size: 20,
                      ),
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.expand_more_rounded,
                  color: AvroClientColors.textSecondary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
