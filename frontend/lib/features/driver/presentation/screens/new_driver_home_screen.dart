import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/performance/rebuild_tracker.dart';

import '../../../../core/services/openstreetmap_service.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../map/presentation/widgets/evik_osm_map_view.dart';
import '../../domain/entities/available_order.dart';
import '../../domain/entities/driver.dart';
import '../../domain/entities/driver_work_state.dart';
import '../providers/new_driver_provider.dart';

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
  static const Duration _offerLifetime = Duration(seconds: 10);

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

    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message), backgroundColor: EvikColors.errorRed),
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
      backgroundColor: EvikColors.primaryWhite,
      body: workState == DriverWorkState.offline
          ? SafeArea(child: _buildOfflineView(driverState, driverProfile))
          : _BackgroundOptimizer(
              isDriverWaiting: workState == DriverWorkState.online,
              isAppInForeground: _isAppInForeground,
              child: _buildOnlineView(driverState, driverProfile),
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

    // Create new animation controller for this offer
    _offerAnimationController = AnimationController(
      duration: _offerLifetime,
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
        ref.read(newDriverProvider.notifier).declineOrder(incoming.id);
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

  Widget _buildOfflineView(DriverState driverState, AsyncValue<Driver?> driverProfile) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    color: EvikColors.primaryBlack,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getDriverInitial(driverProfile),
                      style: const TextStyle(
                        color: EvikColors.primaryWhite,
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
                color: EvikColors.gray100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: EvikColors.gray200,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.power_settings_new,
                      color: EvikColors.gray500,
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
                      color: EvikColors.gray500,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Статистика вчера
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: EvikColors.gray100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ВЧЕРА',
                    style: EvikTypography.sectionLabel.copyWith(
                      color: EvikColors.gray500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatColumn(
                        '${driverState.stats.yesterday.ordersCount}',
                        'Заказа',
                      ),
                      _buildStatColumn(
                        '${driverState.stats.yesterday.earnings.toInt()} ₽',
                        'Заработано',
                      ),
                      _buildStatColumn(
                        '${driverState.stats.yesterday.rating} ⭐',
                        'Рейтинг',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Кнопка начать работу
            EvikButton(
              text: 'Начать работу',
              isLoading: driverState.isLoading,
              onPressed: driverState.isLoading
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
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

  Widget _buildOnlineView(DriverState driverState, AsyncValue<Driver?> driverProfile) {
    _syncIncomingOffer(driverState.workState, driverState.availableOrders);
    final incomingOrder = driverState.availableOrders.isEmpty
        ? null
        : driverState.availableOrders.first;
    _syncRoutePreview(incomingOrder);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

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
                  bottomInset + (incomingOrder == null ? 128 : 330),
              controlsBackgroundColor: EvikColors.primaryWhite,
              controlsIconColor: EvikColors.accentOrange,
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
                    HapticFeedback.selectionClick();
                    ref.read(newDriverProvider.notifier).goOffline();
                  },
          ),
        ),
        if (incomingOrder == null)
          Positioned(
            left: 20,
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: _WaitingForOrdersCard(isLoading: driverState.isLoading),
          )
        else
          Positioned(
            left: 14,
            right: 14,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: AnimatedBuilder(
              animation:
                  _offerProgressAnimation ?? const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return _IncomingOrderSheet(
                  order: incomingOrder,
                  progress: _offerProgressAnimation?.value ?? 1.0,
                  isLoading: driverState.isLoading,
                  onDecline: () {
                    HapticFeedback.lightImpact();
                    _offerAnimationController?.stop();
                    setState(() {
                      _visibleOfferId = null;
                    });
                    ref
                        .read(newDriverProvider.notifier)
                        .declineOrder(incomingOrder.id);
                  },
                  onAccept: () {
                    HapticFeedback.heavyImpact();
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

  Widget _buildStatColumn(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: EvikTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: EvikTypography.bodySmall.copyWith(
            color: EvikColors.gray500,
            fontSize: 11,
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
        color: EvikColors.successGreen,
      ),
      if (incoming != null)
        EvikMapMarker(
          lat: incoming.pickupLat,
          lng: incoming.pickupLng,
          title: incoming.pickupAddress,
          color: EvikColors.accentOrange,
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
          color: EvikColors.primaryWhite.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: EvikColors.gray200),
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
                color: EvikColors.accentOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Маршрут недоступен',
                style: EvikTypography.bodySmall.copyWith(
                  color: EvikColors.primaryBlack,
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

class _OnlineStatusBar extends StatelessWidget {
  const _OnlineStatusBar({required this.statsText, required this.onGoOffline});

  final String statsText;
  final VoidCallback? onGoOffline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.primaryWhite,
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
                color: EvikColors.successGreen,
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
                      color: EvikColors.successGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statsText,
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray600,
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
                activeThumbColor: EvikColors.primaryWhite,
                activeTrackColor: EvikColors.successGreen,
                inactiveThumbColor: EvikColors.primaryWhite,
                inactiveTrackColor: EvikColors.gray300,
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
      color: EvikColors.primaryWhite,
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
                      color: EvikColors.accentOrange,
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
                      color: EvikColors.gray600,
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
        color: EvikColors.primaryWhite,
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
                            color: EvikColors.gray600,
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
                  backgroundColor: EvikColors.gray200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    EvikColors.accentOrange,
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
                  color: EvikColors.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: EvikColors.gray200),
                ),
                child: Column(
                  children: [
                    _AddressLine(
                      color: EvikColors.accentOrange,
                      label: 'К клиенту',
                      value: order.pickupAddress,
                    ),
                    const SizedBox(height: 8),
                    _AddressLine(
                      color: EvikColors.gray500,
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
                      backgroundColor: EvikColors.gray100,
                      foregroundColor: EvikColors.primaryBlack,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OrderActionButton(
                      text: 'Принять',
                      onPressed: isLoading ? null : onAccept,
                      isLoading: isLoading,
                      backgroundColor: EvikColors.successGreen,
                      foregroundColor: EvikColors.primaryWhite,
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
        color: EvikColors.gray100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: EvikColors.gray700),
          const SizedBox(width: 6),
          Text(
            label,
            style: EvikTypography.bodySmall.copyWith(
              color: EvikColors.gray800,
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
