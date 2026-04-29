import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../domain/entities/available_order.dart';
import '../../domain/entities/driver_work_state.dart';
import '../providers/new_driver_provider.dart';

class NewDriverHomeScreen extends ConsumerStatefulWidget {
  const NewDriverHomeScreen({super.key});

  @override
  ConsumerState<NewDriverHomeScreen> createState() =>
      _NewDriverHomeScreenState();
}

class _NewDriverHomeScreenState extends ConsumerState<NewDriverHomeScreen> {
  bool _mapInitialized = false;
  bool _isAppInForeground = true;
  String? _cachedMapSignature;
  List<MapObject>? _cachedMapObjects;
  late final _DriverLifecycleObserver _lifecycleObserver;
  DrivingSession? _drivingSession;
  Timer? _offerTimer;
  double _offerProgress = 1;
  String? _visibleOfferId;
  List<MapObject> _routeObjects = const [];
  int _routeVersion = 0;
  static const Duration _offerLifetime = Duration(seconds: 10);
  static const Duration _offerTick = Duration(milliseconds: 50);

  // Координаты Москвы по умолчанию
  static const Point _moscowCenter = Point(
    latitude: 55.7558,
    longitude: 37.6173,
  );

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
    _offerTimer?.cancel();
    _drivingSession?.close();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);
    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: EvikColors.errorRed),
      );
    });

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: driverState.workState == DriverWorkState.offline
          ? SafeArea(child: _buildOfflineView(driverState))
          : _BackgroundOptimizer(
              isDriverWaiting:
                  driverState.workState == DriverWorkState.online &&
                      driverState.activeOrder == null,
              isAppInForeground: _isAppInForeground,
              child: _buildOnlineView(driverState),
            ),
    );
  }

  void _syncIncomingOffer(DriverState driverState) {
    if (driverState.workState != DriverWorkState.online ||
        driverState.availableOrders.isEmpty) {
      _offerTimer?.cancel();
      _visibleOfferId = null;
      _offerProgress = 1;
      return;
    }

    final incoming = driverState.availableOrders.first;
    if (_visibleOfferId == incoming.id) return;

    _offerTimer?.cancel();
    _visibleOfferId = incoming.id;
    _offerProgress = 1;
    final expiresAt = DateTime.now().add(_offerLifetime);
    _updateOfferRoute(incoming);
    _offerTimer = Timer.periodic(_offerTick, (timer) {
      if (!mounted) return;
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        timer.cancel();
        ref.read(newDriverProvider.notifier).declineOrder(incoming.id);
        setState(() {
          _visibleOfferId = null;
          _offerProgress = 1;
          _routeObjects = const [];
          _routeVersion++;
        });
        return;
      }
      setState(() {
        _offerProgress =
            remaining.inMilliseconds / _offerLifetime.inMilliseconds;
      });
    });
  }

  Widget _buildOfflineView(DriverState driverState) {
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
                          'Михаил',
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
                  child: const Center(
                    child: Text(
                      'М',
                      style: TextStyle(
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

  Widget _buildOnlineView(DriverState driverState) {
    _syncIncomingOffer(driverState);
    final incomingOrder = driverState.availableOrders.isEmpty
        ? null
        : driverState.availableOrders.first;

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: YandexMap(
              onMapCreated: _onMapCreated,
              mapType: MapType.vector,
              mapObjects: _buildMapObjects(driverState),
            ),
          ),
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
            child: _IncomingOrderSheet(
              order: incomingOrder,
              progress: _offerProgress,
              isLoading: driverState.isLoading,
              onDecline: () {
                HapticFeedback.lightImpact();
                _offerTimer?.cancel();
                setState(() {
                  _visibleOfferId = null;
                  _offerProgress = 1;
                  _routeObjects = const [];
                  _routeVersion++;
                });
                ref
                    .read(newDriverProvider.notifier)
                    .declineOrder(incomingOrder.id);
              },
              onAccept: () {
                HapticFeedback.heavyImpact();
                _offerTimer?.cancel();
                ref
                    .read(newDriverProvider.notifier)
                    .acceptOrder(incomingOrder.id);
              },
            ),
          ),
      ],
    );
  }

  Future<void> _updateOfferRoute(AvailableOrder order) async {
    await _drivingSession?.cancel();
    await _drivingSession?.close();

    try {
      final resultWithSession = await YandexDriving.requestRoutes(
        points: [
          const RequestPoint(
            point: _moscowCenter,
            requestPointType: RequestPointType.wayPoint,
          ),
          RequestPoint(
            point: Point(latitude: order.pickupLat, longitude: order.pickupLng),
            requestPointType: RequestPointType.wayPoint,
          ),
        ],
        drivingOptions: const DrivingOptions(
          routesCount: 1,
          annotationLanguage: AnnotationLanguage.russian,
          avoidanceFlags: DrivingAvoidanceFlags(),
        ),
      );
      _drivingSession = resultWithSession.$1;
      final result = await resultWithSession.$2;
      if (!mounted || _visibleOfferId != order.id) return;
      final route =
          result.routes?.isNotEmpty == true ? result.routes!.first : null;
      setState(() {
        _routeObjects = route == null
            ? const []
            : [
                PolylineMapObject(
                  mapId: const MapObjectId('incoming_order_route'),
                  polyline: route.geometry,
                  strokeColor: EvikColors.accentOrange,
                  strokeWidth: 4,
                ),
              ];
        _routeVersion++;
      });
    } catch (_) {
      if (!mounted || _visibleOfferId != order.id) return;
      setState(() {
        _routeObjects = const [];
        _routeVersion++;
      });
    }
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

  Future<void> _onMapCreated(YandexMapController controller) async {
    await controller.toggleTrafficLayer(visible: true);
    if (_mapInitialized) return;
    _mapInitialized = true;

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(target: _moscowCenter, zoom: 12.2),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1),
    );
  }

  List<MapObject> _buildMapObjects(DriverState driverState) {
    final signature = [
      driverState.availableOrders.map((e) => e.id).join('|'),
      _routeVersion,
    ].join(':');
    if (_cachedMapObjects != null && _cachedMapSignature == signature) {
      return _cachedMapObjects!;
    }

    final objects = <MapObject>[
      ..._routeObjects,
      PlacemarkMapObject(
        mapId: const MapObjectId('driver_location'),
        point: _moscowCenter,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(Uint8List.fromList([0, 180, 90])),
            scale: 1.0,
          ),
        ),
      ),
    ];

    final incoming = driverState.availableOrders.isEmpty
        ? null
        : driverState.availableOrders.first;
    if (incoming != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: MapObjectId('pickup_${incoming.id}'),
          point: Point(
            latitude: incoming.pickupLat,
            longitude: incoming.pickupLng,
          ),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(
                Uint8List.fromList([255, 96, 50]),
              ),
              scale: 0.9,
            ),
          ),
        ),
      );
    }

    _cachedMapSignature = signature;
    _cachedMapObjects = objects;
    return objects;
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
