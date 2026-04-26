import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../domain/entities/active_order.dart';
import '../../domain/entities/driver_work_state.dart';
import '../providers/new_driver_provider.dart';

class ActiveOrderScreen extends ConsumerStatefulWidget {
  const ActiveOrderScreen({super.key});

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen> {
  bool _mapInitialized = false;

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);
    final activeOrder = driverState.activeOrder;

    if (activeOrder == null) {
      return const Scaffold(
        backgroundColor: EvikColors.gray50,
        body: Center(child: Text('Нет активного заказа')),
      );
    }

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      body: SafeArea(
        child: driverState.workState == DriverWorkState.hasActiveOrder
            ? _buildDrivingToClientView(activeOrder)
            : _buildDrivingToDestinationView(activeOrder),
      ),
    );
  }

  Widget _buildDrivingToClientView(ActiveOrder order) {
    return Column(
      children: [
        // Header с таймером и статусом
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Новый заказ!',
                style: EvikTypography.bodyMedium.copyWith(
                  color: EvikColors.gray500,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: EvikColors.accentOrange, width: 3),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    '30',
                    style: EvikTypography.h2.copyWith(
                      color: EvikColors.accentOrange,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Карта с маршрутом
        Expanded(
          child: YandexMap(
            onMapCreated: _onMapCreated,
            mapType: MapType.vector,
            mapObjects: _buildRouteMapObjects(order),
          ),
        ),

        // Детали заказа
        Container(
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${order.price.toInt()} ₽',
                      style: EvikTypography.price.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: EvikColors.warningAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.problemType,
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.warningAmber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Оплата картой',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.gray500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '🚗 ${order.vehicleModel}',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.gray500,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 20),

                // Адреса
                _buildAddressRow(
                  '📍',
                  'ЗАБРАТЬ',
                  order.pickupAddress,
                  EvikColors.accentOrange,
                ),
                const SizedBox(height: 12),
                _buildAddressRow(
                  '🏁',
                  'ДОСТАВИТЬ',
                  order.dropoffAddress,
                  EvikColors.gray500,
                ),

                const SizedBox(height: 24),

                // Метрики
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricColumn(
                      '${order.distanceToClient.toStringAsFixed(1)} км',
                      'до клиента',
                    ),
                    _buildMetricColumn(
                      '${order.estimatedMinutes} мин',
                      'подача',
                    ),
                    _buildMetricColumn(
                      '${(order.totalDistance - order.distanceToClient).toStringAsFixed(0)} км',
                      'маршрут',
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Кнопки
                Row(
                  children: [
                    Expanded(
                      child: EvikButton(
                        text: 'Отклонить',
                        onPressed: () {
                          ref
                              .read(newDriverProvider.notifier)
                              .declineOrder(order.id);
                        },
                        variant: EvikButtonVariant.ghost,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: EvikButton(
                        text: '✓ Принять заказ',
                        onPressed: () {
                          ref
                              .read(newDriverProvider.notifier)
                              .arrivedAtClient();
                        },
                        variant: EvikButtonVariant.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrivingToDestinationView(ActiveOrder order) {
    return Column(
      children: [
        // Header с статусом
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: EvikColors.warningAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Еду к клиенту',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.warningAmber,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${order.price.toInt()} ₽',
                style: EvikTypography.price.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),

        // Карта
        Expanded(
          child: YandexMap(
            onMapCreated: _onMapCreated,
            mapType: MapType.vector,
            mapObjects: _buildNavigationMapObjects(order),
          ),
        ),

        // Информация о клиенте
        Container(
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: EvikColors.accentOrange,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          order.clientInitial,
                          style: const TextStyle(
                            color: EvikColors.primaryWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
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
                            style: EvikTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '🚗 ${order.vehicleModel} • ${order.problemType}',
                            style: EvikTypography.bodySmall.copyWith(
                              color: EvikColors.gray500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _makePhoneCall(order.clientPhone),
                      icon: const Icon(Icons.phone,
                          color: EvikColors.accentOrange),
                    ),
                    IconButton(
                      onPressed: () => _openSMS(order.clientPhone),
                      icon:
                          const Icon(Icons.message, color: EvikColors.gray500),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: EvikButton(
                        text: 'Навигатор',
                        onPressed: () => _openNavigation(order),
                        variant: EvikButtonVariant.ghost,
                        icon: const Icon(Icons.navigation, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EvikButton(
                        text: 'Я на месте',
                        onPressed: () {
                          ref
                              .read(newDriverProvider.notifier)
                              .startDrivingToDestination();
                        },
                        variant: EvikButtonVariant.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressRow(
      String emoji, String label, String address, Color dotColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: EvikTypography.sectionLabel.copyWith(
                  color: EvikColors.gray500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: EvikTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricColumn(String value, String label) {
    return Column(
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
    if (_mapInitialized) return;
    _mapInitialized = true;

    // Фокус на маршруте
    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: Point(latitude: 55.7558, longitude: 37.6173),
          zoom: 13,
        ),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1),
    );
  }

  List<MapObject> _buildRouteMapObjects(ActiveOrder order) {
    return [
      // Точка забора
      PlacemarkMapObject(
        mapId: const MapObjectId('pickup_point'),
        point: Point(latitude: order.pickupLat, longitude: order.pickupLng),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_createPickupMarkerIcon()),
            scale: 0.8,
          ),
        ),
      ),
      // Точка назначения
      PlacemarkMapObject(
        mapId: const MapObjectId('dropoff_point'),
        point: Point(latitude: order.dropoffLat, longitude: order.dropoffLng),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_createDropoffMarkerIcon()),
            scale: 0.8,
          ),
        ),
      ),
      // Маршрут (упрощенная линия)
      PolylineMapObject(
        mapId: const MapObjectId('route'),
        polyline: Polyline(points: [
          Point(latitude: order.pickupLat, longitude: order.pickupLng),
          Point(latitude: order.dropoffLat, longitude: order.dropoffLng),
        ]),
        strokeColor: EvikColors.accentOrange,
        strokeWidth: 4,
      ),
    ];
  }

  List<MapObject> _buildNavigationMapObjects(ActiveOrder order) {
    return [
      // Позиция водителя
      PlacemarkMapObject(
        mapId: const MapObjectId('driver_location'),
        point: const Point(latitude: 55.7558, longitude: 37.6173),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_createDriverMarkerIcon()),
            scale: 1.0,
          ),
        ),
      ),
      // Точка клиента
      PlacemarkMapObject(
        mapId: const MapObjectId('client_location'),
        point: Point(latitude: order.pickupLat, longitude: order.pickupLng),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(_createPickupMarkerIcon()),
            scale: 0.8,
          ),
        ),
      ),
      // Маршрут до клиента
      PolylineMapObject(
        mapId: const MapObjectId('route_to_client'),
        polyline: Polyline(points: [
          const Point(latitude: 55.7558, longitude: 37.6173),
          Point(latitude: order.pickupLat, longitude: order.pickupLng),
        ]),
        strokeColor: EvikColors.accentOrange,
        strokeWidth: 4,
      ),
    ];
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openSMS(String phoneNumber) async {
    final Uri uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openNavigation(ActiveOrder order) async {
    // Открыть Яндекс.Навигатор с маршрутом
    final Uri uri = Uri.parse(
      'yandexnavi://build_route_on_map?lat_to=${order.pickupLat}&lon_to=${order.pickupLng}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // Простые заглушки вместо сложных маркеров
  Uint8List _createPickupMarkerIcon() =>
      Uint8List.fromList([255, 165, 0]); // Оранжевый
  Uint8List _createDropoffMarkerIcon() =>
      Uint8List.fromList([128, 128, 128]); // Серый
  Uint8List _createDriverMarkerIcon() =>
      Uint8List.fromList([0, 255, 0]); // Зеленый
}
