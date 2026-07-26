import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/navigation_service.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/active_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';

class ActiveOrderScreen extends ConsumerStatefulWidget {
  const ActiveOrderScreen({super.key});

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen> {
  double? _driverLat;
  double? _driverLng;
  String? _routeKey;
  RoutePreview? _routePreview;
  bool _routePreviewFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    try {
      final pos = await LocationService.getCurrentPositionWithFallback();
      if (mounted) {
        setState(() {
          _driverLat = pos.latitude;
          _driverLng = pos.longitude;
        });
      }
    } catch (_) {
      // Location unavailable — routes fall back to pickup/dropoff coords.
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);
    final order = driverState.activeOrder;

    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AvroDriverColors.error,
        ),
      );
    });

    if (order == null) {
      return const Scaffold(
        backgroundColor: AvroDriverColors.surface,
        body: Center(child: Text('Нет активного заказа')),
      );
    }
    _syncRoutePreview(order);

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: EvikOsmMapView(
              initialLat: _driverLat ?? order.pickupLat,
              initialLng: _driverLng ?? order.pickupLng,
              initialZoom: 13.4,
              markers: _mapMarkers(order),
              routePoints: _routePreview?.points ?? const <LatLng>[],
              controlsBottomOffset: 10 + 72 + 50 + 246,
              controlsBackgroundColor: AvroDriverColors.surface,
              controlsIconColor: AvroDriverColors.accent,
            ),
          ),
          if (_routePreviewFailed)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 78,
              child: const _RouteUnavailableBadge(),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: _ActiveOrderTopBar(order: order),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ActiveOrderBottomSheet(
              order: order,
              isLoading: driverState.isLoading,
              workState: driverState.workState,
              onCall: () => _makePhoneCall(order.clientPhone),
              onMessage: () => _openSMS(order.clientPhone),
              onNavigation: () => _openNavigation(order),
              onPrimaryAction: () => _handlePrimaryAction(order),
            ),
          ),
        ],
      ),
    );
  }

  List<EvikMapMarker> _mapMarkers(ActiveOrder order) {
    return [
      if (_driverLat != null && _driverLng != null)
        EvikMapMarker(
          lat: _driverLat!,
          lng: _driverLng!,
          title: 'Водитель',
          color: AvroDriverColors.info,
        ),
      EvikMapMarker(
        lat: order.pickupLat,
        lng: order.pickupLng,
        title: order.pickupAddress,
        color: AvroDriverColors.accent,
      ),
      EvikMapMarker(
        lat: order.dropoffLat,
        lng: order.dropoffLng,
        title: order.dropoffAddress,
        color: AvroDriverColors.textSecondary,
      ),
    ];
  }

  ({double lat, double lng}) _targetPoint(ActiveOrder order) {
    if (order.status == ActiveOrderStatus.drivingToDestination) {
      return (lat: order.dropoffLat, lng: order.dropoffLng);
    }
    return (lat: order.pickupLat, lng: order.pickupLng);
  }

  Future<void> _handlePrimaryAction(ActiveOrder order) async {
    try { HapticFeedback.heavyImpact(); } catch (_) {}
    final notifier = ref.read(newDriverProvider.notifier);
    switch (order.status) {
      case ActiveOrderStatus.drivingToClient:
        await notifier.arrivedAtClient();
        break;
      case ActiveOrderStatus.arrivedAtClient:
        await notifier.startDrivingToDestination();
        break;
      case ActiveOrderStatus.drivingToDestination:
        await notifier.completeOrder();
        break;
      case ActiveOrderStatus.completed:
        break;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openSMS(String phoneNumber) async {
    final uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openNavigation(ActiveOrder order) async {
    final target = _targetPoint(order);
    if (!mounted) return;
    await NavigationLauncher.openPreferredOrChoose(
      context: context,
      toLat: target.lat,
      toLng: target.lng,
      destinationName: order.status == ActiveOrderStatus.drivingToDestination
          ? order.dropoffAddress
          : order.pickupAddress,
    );
  }

  void _syncRoutePreview(ActiveOrder order) {
    final target = _targetPoint(order);
    final nextKey = '${order.id}:${order.status}:${target.lat}:${target.lng}';
    if (_routeKey == nextKey) return;
    _routeKey = nextKey;
    _routePreview = null;
    _routePreviewFailed = false;
    final fromLat = _driverLat ?? order.pickupLat;
    final fromLng = _driverLng ?? order.pickupLng;
    OpenStreetMapService.getRoutePreview(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: target.lat,
      toLng: target.lng,
    ).then((preview) {
      if (!mounted || _routeKey != nextKey) return;
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

class _ActiveOrderTopBar extends StatelessWidget {
  const _ActiveOrderTopBar({required this.order});

  final ActiveOrder order;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AvroDriverColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: AvroDriverColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.statusDisplayName,
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${order.distanceToClient.toStringAsFixed(1)} км · ${order.estimatedMinutes} мин',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${order.price.toInt()} ₽',
              style: EvikTypography.price.copyWith(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveOrderBottomSheet extends StatelessWidget {
  const _ActiveOrderBottomSheet({
    required this.order,
    required this.isLoading,
    required this.workState,
    required this.onCall,
    required this.onMessage,
    required this.onNavigation,
    required this.onPrimaryAction,
  });

  final ActiveOrder order;
  final bool isLoading;
  final DriverWorkState workState;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onNavigation;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AvroDriverColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (workState == DriverWorkState.waitingForPayment)
              _WaitingForPaymentIndicator()
            else ...[
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AvroDriverColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        order.clientInitial,
                        style: const TextStyle(
                          color: AvroDriverColors.surface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.clientName,
                          style: EvikTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                        '${order.vehicleModel} · колеса: ${order.blockedWheelsCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroDriverColors.grayHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onCall,
                    icon: const Icon(Icons.phone_rounded),
                    color: AvroDriverColors.accent,
                  ),
                  IconButton(
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_rounded),
                    color: AvroDriverColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _RoutePoint(
                color: AvroDriverColors.accent,
                label: order.status == ActiveOrderStatus.drivingToDestination
                    ? 'Забрали'
                    : 'К клиенту',
                value: order.pickupAddress,
              ),
              const SizedBox(height: 8),
              _RoutePoint(
                color: AvroDriverColors.grayHint,
                label: 'Доставка',
                value: order.dropoffAddress,
              ),
              const SizedBox(height: 14),
              if (order.status == ActiveOrderStatus.drivingToDestination)
                _SlideToComplete(
                  price: order.price,
                  enabled: !isLoading,
                  onCompleted: onPrimaryAction,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: EvikButton(
                        text: 'Построить маршрут',
                        onPressed: isLoading ? null : onNavigation,
                        icon: const Icon(Icons.route_rounded, size: 18),
                        small: true,
                        variant: EvikButtonVariant.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EvikButton(
                        text: _primaryText(order.status),
                        onPressed: isLoading ? null : onPrimaryAction,
                        isLoading: isLoading,
                        small: true,
                        variant: EvikButtonVariant.green,
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _primaryText(ActiveOrderStatus status) {
    return switch (status) {
      ActiveOrderStatus.drivingToClient => 'Прибыл к клиенту',
      ActiveOrderStatus.arrivedAtClient => 'Погрузил, в путь',
      ActiveOrderStatus.drivingToDestination => 'Завершить заказ',
      ActiveOrderStatus.completed => 'Заказ завершен',
    };
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
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

class _WaitingForPaymentIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AvroDriverColors.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ожидание оплаты клиентом',
            style: EvikTypography.bodyLarge.copyWith(
              color: AvroDriverColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'После подтверждения оплаты заказ будет завершён',
            textAlign: TextAlign.center,
            style: EvikTypography.bodySmall.copyWith(
              color: AvroDriverColors.grayHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideToComplete extends StatefulWidget {
  const _SlideToComplete({
    required this.price,
    required this.enabled,
    required this.onCompleted,
  });

  final double price;
  final bool enabled;
  final VoidCallback onCompleted;

  @override
  State<_SlideToComplete> createState() => _SlideToCompleteState();
}

class _SlideToCompleteState extends State<_SlideToComplete> {
  double _drag = 0;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const knobSize = 48.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 36;
        final maxDrag = (width - knobSize - 10).clamp(
          0.0,
          1000.0,
        );
        final progress = maxDrag == 0 ? 0.0 : (_drag / maxDrag).clamp(0.0, 1.0);

        return GestureDetector(
          onHorizontalDragUpdate: !widget.enabled || _completed
              ? null
              : (details) {
                  setState(() {
                    _drag = (_drag + details.delta.dx).clamp(0.0, maxDrag);
                  });
                },
          onHorizontalDragEnd: !widget.enabled || _completed
              ? null
              : (_) {
                  if (progress >= 0.96) {
                    setState(() {
                      _completed = true;
                      _drag = maxDrag;
                    });
                    try { HapticFeedback.heavyImpact(); } catch (_) {}
                    widget.onCompleted();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: SizedBox(
            width: double.infinity,
            height: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.enabled
                    ? AvroDriverColors.accent
                    : AvroDriverColors.border,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                    Padding(
                      padding: const EdgeInsets.only(left: 58, right: 16),
                      child: Text(
                        'Завершить заказ',
                        maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.buttonText.copyWith(
                        color: AvroDriverColors.surface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5 + _drag,
                    child: Container(
                      width: knobSize,
                      height: knobSize,
                      decoration: const BoxDecoration(
                        color: AvroDriverColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: AvroDriverColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
