import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/performance/rebuild_tracker.dart';

import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/providers/service_area_provider.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/available_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';

// Provider for driver profile data (reused from profile screen)
final driverProfileProvider = FutureProvider.autoDispose<Driver?>((ref) async {
  final authState = ref.watch(authProvider);
  final driverId = authState.user?.id;

  if (driverId == null) return null;

  final repository = ref.watch(httpDriverRepositoryProvider);
  return await repository.getDriver(driverId);
});

class NewDriverHomeScreen extends ConsumerStatefulWidget {
  const NewDriverHomeScreen({super.key});

  @override
  ConsumerState<NewDriverHomeScreen> createState() =>
      _NewDriverHomeScreenState();
}

class _NewDriverHomeScreenState extends ConsumerState<NewDriverHomeScreen>
    with TickerProviderStateMixin {
  bool _isAppInForeground = true;
  late final _DriverLifecycleObserver _lifecycleObserver;
  AnimationController? _offerAnimationController;
  Animation<double>? _offerProgressAnimation;
  String? _visibleOfferId;
  String? _routePreviewOrderId;
  RoutePreview? _routePreview;
  bool _routePreviewFailed = false;


  // Координаты Москвы по умолчанию
  static const double _moscowLat = 55.7558;
  static const double _moscowLng = 37.6173;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _DriverLifecycleObserver(
      onChanged: (state) {
        if (!mounted) return;
        setState(() {
          _isAppInForeground = state != AppLifecycleState.paused &&
              state != AppLifecycleState.detached &&
              state != AppLifecycleState.hidden;
        });
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pos = await LocationService.getCurrentPositionWithFallback();
        if (mounted) {
          ref
              .read(serviceAreaProvider.notifier)
              .checkServiceArea(pos.latitude, pos.longitude);
        }
      } catch (_) {
        if (mounted) {
          ref
              .read(serviceAreaProvider.notifier)
              .checkServiceArea(_moscowLat, _moscowLng);
        }
      }
    });
  }

  @override
  void dispose() {
    _offerAnimationController?.dispose();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    RebuildTracker.trackRebuild('NewDriverHomeScreen');

    final workState =
        ref.watch(newDriverProvider.select((state) => state.workState));
    final availableOrders =
        ref.watch(newDriverProvider.select((state) => state.availableOrders));
    final isLoading =
        ref.watch(newDriverProvider.select((state) => state.isLoading));
    final stats = ref.watch(newDriverProvider.select((state) => state.stats));
    final driverProfile = ref.watch(driverProfileProvider);
    final serviceArea = ref.watch(serviceAreaProvider);

    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message), backgroundColor: AvroDriverColors.error),
        );
      }
    });

    // Create minimal state object for methods that need full state
    final driverState = DriverState(
      workState: workState,
      availableOrders: availableOrders,
      isLoading: isLoading,
      stats: stats,
      activeOrder: null,
      error: null,
    );

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      body: workState == DriverWorkState.offline
          ? SafeArea(child: _buildOfflineView(driverState, driverProfile, serviceArea))
          : _BackgroundOptimizer(
              isDriverWaiting: workState == DriverWorkState.online,
              isAppInForeground: _isAppInForeground,
              child: _buildOnlineView(driverState, driverProfile, serviceArea),
            ),
    );
  }

  void _syncIncomingOffer(DriverWorkState workState, List availableOrders) {
    if (workState != DriverWorkState.online || availableOrders.isEmpty) {
      _offerAnimationController?.stop();
      _visibleOfferId = null;
      return;
    }

    final incoming = availableOrders.first;
    if (_visibleOfferId == incoming.id) return;

    _offerAnimationController?.dispose();
    _visibleOfferId = incoming.id;

    Duration duration;
    if (incoming.expiresAt != null) {
      final remaining = incoming.expiresAt!.difference(DateTime.now().toUtc());
      duration = remaining > Duration.zero ? remaining : Duration.zero;
    } else {
      duration = const Duration(seconds: 15);
    }

    if (duration == Duration.zero) {
      _visibleOfferId = null;
      return;
    }

    _offerAnimationController = AnimationController(
      duration: duration,
      vsync: this,
    );

    _offerProgressAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _offerAnimationController!,
      curve: Curves.linear,
    ));

    _offerAnimationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _visibleOfferId = null;
        });
      }
    });

    _offerAnimationController!.forward();
  }

  /// Get driver display name from profile
  String _getDriverDisplayName(AsyncValue<Driver?> driverProfile) {
    return driverProfile.when(
      data: (driver) {
        if (driver?.fullName?.isNotEmpty == true) {
          // Extract first name from full name
          final firstName = driver!.fullName!.split(' ').first;
          return firstName;
        }
        return 'Водитель';
      },
      loading: () => 'Водитель',
      error: (_, __) => 'Водитель',
    );
  }

  /// Get driver initial from profile
  String _getDriverInitial(AsyncValue<Driver?> driverProfile) {
    return driverProfile.when(
      data: (driver) {
        if (driver?.fullName?.isNotEmpty == true) {
          return driver!.fullName!.characters.first.toUpperCase();
        }
        return 'В';
      },
      loading: () => 'В',
      error: (_, __) => 'В',
    );
  }

  Widget _buildOfflineView(
      DriverState driverState, AsyncValue<Driver?> driverProfile, ServiceAreaState serviceArea) {
    final outsideServiceArea = serviceArea.isChecked && !serviceArea.isAllowed;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (outsideServiceArea) _DriverServiceAreaBanner(),
            // Приветствие
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добрый день,',
                      style: EvikTypography.h2.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 22,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _getDriverDisplayName(driverProfile),
                          style: EvikTypography.h2.copyWith(fontSize: 22),
                        ),
                        const SizedBox(width: 6),
                        const Text('👋', style: TextStyle(fontSize: 20)),
                      ],
                    ),
                  ],
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AvroDriverColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getDriverInitial(driverProfile),
                      style: const TextStyle(
                        color: AvroDriverColors.surface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Offline состояние
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AvroDriverColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AvroDriverColors.grayHint,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.power_settings_new,
                      color: AvroDriverColors.grayHint,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Вы не в сети',
                    style: EvikTypography.h3.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Включите режим работы, чтобы получать заказы',
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroDriverColors.grayHint,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Кнопка начать работу
            EvikButton(
              text: 'Начать работу',
              isLoading: driverState.isLoading,
              onPressed: driverState.isLoading || outsideServiceArea
                  ? null
                  : () {
                      try { HapticFeedback.selectionClick(); } catch (_) {}
                      ref.read(newDriverProvider.notifier).goOnline();
                    },
              width: double.infinity,
              variant: EvikButtonVariant.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineView(
      DriverState driverState, AsyncValue<Driver?> driverProfile, ServiceAreaState serviceArea) {
    _syncIncomingOffer(driverState.workState, driverState.availableOrders);
    final incomingOrder = driverState.availableOrders.isEmpty
        ? null
        : driverState.availableOrders.first;
    _syncRoutePreview(incomingOrder);
    const navBottom = 10.0 + 72.0 + 10.0;

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: EvikOsmMapView(
              initialLat: incomingOrder?.pickupLat ?? _moscowLat,
              initialLng: incomingOrder?.pickupLng ?? _moscowLng,
              initialZoom: incomingOrder == null ? 12.2 : 13.5,
              markers: _mapMarkers(incomingOrder),
              routePoints: _routePreview?.points ?? const <LatLng>[],
              controlsBottomOffset:
                  10 + 72 + 50 + (incomingOrder == null ? 128 : 330),
              controlsBackgroundColor: AvroDriverColors.surface,
              controlsIconColor: AvroDriverColors.accent,
            ),
          ),
        ),
        if (incomingOrder != null && _routePreviewFailed)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 74,
            child: const _RouteUnavailableBadge(),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          child: _OnlineStatusBar(
            statsText: driverState.stats.today.displayText,
            onGoOffline: driverState.isLoading
                ? null
                : () {
                    try { HapticFeedback.selectionClick(); } catch (_) {}
                    ref.read(newDriverProvider.notifier).goOffline();
                  },
          ),
        ),
        if (incomingOrder == null)
          Positioned(
            left: 10,
            right: 10,
            bottom: navBottom,
            child: _WaitingForOrdersCard(isLoading: driverState.isLoading),
          )
        else
          Positioned(
            left: 10,
            right: 10,
            bottom: navBottom,
            child: AnimatedBuilder(
              animation:
                  _offerProgressAnimation ?? const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return _IncomingOrderSheet(
                  order: incomingOrder,
                  progress: _offerProgressAnimation?.value ?? 1.0,
                  isLoading: driverState.isLoading,
                  onDecline: () {
                    try { HapticFeedback.lightImpact(); } catch (_) {}
                    _offerAnimationController?.stop();
                    setState(() {
                      _visibleOfferId = null;
                    });
                    ref
                        .read(newDriverProvider.notifier)
                        .declineOrder(incomingOrder.id);
                  },
                  onAccept: () {
                    try { HapticFeedback.heavyImpact(); } catch (_) {}
                    _offerAnimationController?.stop();
                    ref
                        .read(newDriverProvider.notifier)
                        .acceptOrder(incomingOrder.id);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  List<EvikMapMarker> _mapMarkers(AvailableOrder? incoming) {
    return [
      const EvikMapMarker(
        lat: _moscowLat,
        lng: _moscowLng,
        title: 'Вы',
        color: AvroDriverColors.success,
      ),
      if (incoming != null)
        EvikMapMarker(
          lat: incoming.pickupLat,
          lng: incoming.pickupLng,
          title: incoming.pickupAddress,
          color: AvroDriverColors.accent,
        ),
    ];
  }

  void _syncRoutePreview(AvailableOrder? incoming) {
    if (incoming == null) {
      if (_routePreviewOrderId != null) {
        _routePreviewOrderId = null;
        _routePreview = null;
        _routePreviewFailed = false;
      }
      return;
    }
    if (_routePreviewOrderId == incoming.id) return;
    _routePreviewOrderId = incoming.id;
    _routePreview = null;
    _routePreviewFailed = false;
    OpenStreetMapService.getRoutePreview(
      fromLat: _moscowLat,
      fromLng: _moscowLng,
      toLat: incoming.pickupLat,
      toLng: incoming.pickupLng,
    ).then((preview) {
      if (!mounted || _routePreviewOrderId != incoming.id) return;
      setState(() {
        _routePreview = preview;
        _routePreviewFailed = preview == null;
      });
    });
  }
}

class _RouteUnavailableBadge extends StatelessWidget {
  const _RouteUnavailableBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AvroDriverColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AvroDriverColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.route_outlined,
                size: 18,
                color: AvroDriverColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Маршрут недоступен',
                style: EvikTypography.bodySmall.copyWith(
                  color: AvroDriverColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverServiceAreaBanner extends StatelessWidget {
  const _DriverServiceAreaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AvroDriverColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AvroDriverColors.background,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Авро пока не работает в вашем городе. Мы скоро появимся!',
              style: EvikTypography.bodySmall.copyWith(
                color: AvroDriverColors.background,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineStatusBar extends StatelessWidget {
  const _OnlineStatusBar({required this.statsText, required this.onGoOffline});

  final String statsText;
  final VoidCallback? onGoOffline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AvroDriverColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'В сети',
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroDriverColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statsText,
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 52,
              height: 40,
              child: Switch.adaptive(
                value: true,
                onChanged: onGoOffline == null
                    ? null
                    : (value) {
                        if (!value) onGoOffline!();
                      },
                activeThumbColor: AvroDriverColors.surface,
                activeTrackColor: AvroDriverColors.success,
                inactiveThumbColor: AvroDriverColors.surface,
                inactiveTrackColor: AvroDriverColors.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingForOrdersCard extends StatelessWidget {
  const _WaitingForOrdersCard({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: isLoading
                  ? const CircularProgressIndicator(strokeWidth: 3)
                  : const Icon(
                      Icons.radar_rounded,
                      color: AvroDriverColors.accent,
                      size: 30,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ищем заказы рядом',
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Оставайтесь на линии, заказ появится автоматически',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingOrderSheet extends StatelessWidget {
  const _IncomingOrderSheet({
    required this.order,
    required this.progress,
    required this.isLoading,
    required this.onDecline,
    required this.onAccept,
  });

  final AvailableOrder order;
  final double progress;
  final bool isLoading;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 28 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Material(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(22),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Новый заказ рядом',
                          style: EvikTypography.h3.copyWith(fontSize: 19),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${order.distanceKm.toStringAsFixed(1)} км до клиента · ${order.estimatedMinutes} мин',
                          style: EvikTypography.bodySmall.copyWith(
                            color: AvroDriverColors.grayHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${order.price.toInt()} ₽',
                    style: EvikTypography.price.copyWith(fontSize: 21),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AvroDriverColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AvroDriverColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.directions_car_rounded,
                    label: order.vehicleDisplayName,
                  ),
                  _InfoPill(
                    icon: Icons.build_rounded,
                    label: order.problemType,
                  ),
                  _InfoPill(
                    icon: Icons.motion_photos_off_rounded,
                    label: 'Колеса: ${order.blockedWheelsCount}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AvroDriverColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AvroDriverColors.border),
                ),
                child: Column(
                  children: [
                    _AddressLine(
                      color: AvroDriverColors.accent,
                      label: 'К клиенту',
                      value: order.pickupAddress,
                    ),
                    const SizedBox(height: 8),
                    _AddressLine(
                      color: AvroDriverColors.grayHint,
                      label: 'Доставка',
                      value: order.dropoffAddress,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: _OrderActionButton(
                      text: 'Отклонить',
                      onPressed: isLoading ? null : onDecline,
                      backgroundColor: AvroDriverColors.surface,
                      foregroundColor: AvroDriverColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OrderActionButton(
                      text: 'Принять',
                      onPressed: isLoading ? null : onAccept,
                      isLoading: isLoading,
                      backgroundColor: AvroDriverColors.success,
                      foregroundColor: AvroDriverColors.surface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _OrderActionButton extends StatelessWidget {
  const _OrderActionButton({
    required this.text,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          foregroundColor: foregroundColor,
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.8),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: EvikTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text, maxLines: 1),
              ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AvroDriverColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: EvikTypography.bodySmall.copyWith(
              color: AvroDriverColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: EvikTypography.sectionLabel),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverLifecycleObserver extends WidgetsBindingObserver {
  _DriverLifecycleObserver({required this.onChanged});

  final ValueChanged<AppLifecycleState> onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state);
  }
}

class _BackgroundOptimizer extends StatelessWidget {
  const _BackgroundOptimizer({
    required this.child,
    required this.isDriverWaiting,
    required this.isAppInForeground,
  });

  final Widget child;
  final bool isDriverWaiting;
  final bool isAppInForeground;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: !isDriverWaiting || isAppInForeground,
      child: Visibility(
        visible: !isDriverWaiting || isAppInForeground,
        maintainState: true,
        maintainAnimation: false,
        maintainSize: false,
        child: child,
      ),
    );
  }
}
