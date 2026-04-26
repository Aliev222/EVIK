import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/animated_list_item.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../domain/entities/driver_work_state.dart';
import '../providers/new_driver_provider.dart';
import '../widgets/available_order_card.dart';

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

  // Координаты Москвы по умолчанию
  static const Point _moscowCenter =
      Point(latitude: 55.7558, longitude: 37.6173);

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
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: SafeArea(
        child: driverState.workState == DriverWorkState.offline
            ? _buildOfflineView(driverState)
            : _BackgroundOptimizer(
                isDriverWaiting:
                    driverState.workState == DriverWorkState.online &&
                        driverState.activeOrder == null,
                isAppInForeground: _isAppInForeground,
                child: _buildOnlineView(driverState),
              ),
      ),
    );
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
              onPressed: () {
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
    return Column(
      children: [
        // Header с статистикой сегодня и переключателем
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Сегодня',
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.gray500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        driverState.stats.today.displayText,
                        style: EvikTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: EvikColors.successGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'В сети',
                        style: EvikTypography.bodyMedium.copyWith(
                          color: EvikColors.successGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(newDriverProvider.notifier).goOffline();
                        },
                        child: Container(
                          width: 44,
                          height: 24,
                          decoration: BoxDecoration(
                            color: EvikColors.successGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(
                                color: EvikColors.primaryWhite,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Карта
        Expanded(
          flex: 2,
          child: RepaintBoundary(
            child: YandexMap(
              onMapCreated: _onMapCreated,
              mapType: MapType.vector,
              mapObjects: _buildMapObjects(driverState),
            ),
          ),
        ),

        // Список доступных заказов
        Expanded(
          flex: 3,
          child: Container(
            decoration: const BoxDecoration(
              color: EvikColors.primaryWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        'ДОСТУПНЫЕ ЗАКАЗЫ (${driverState.availableOrders.length})',
                        style: EvikTypography.sectionLabel.copyWith(
                          color: EvikColors.gray500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    cacheExtent: 200,
                    itemCount: driverState.availableOrders.length,
                    itemBuilder: (context, index) {
                      final order = driverState.availableOrders[index];
                      return AnimatedListItem(
                        index: index,
                        child: AvailableOrderCard(
                          order: order,
                          onAccept: () {
                            ref
                                .read(newDriverProvider.notifier)
                                .acceptOrder(order.id);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
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

  Future<void> _onMapCreated(YandexMapController controller) async {
    if (_mapInitialized) return;
    _mapInitialized = true;

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(target: _moscowCenter, zoom: 11),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1),
    );
  }

  List<MapObject> _buildMapObjects(DriverState driverState) {
    final signature = driverState.availableOrders.map((e) => e.id).join('|');
    if (_cachedMapObjects != null && _cachedMapSignature == signature) {
      return _cachedMapObjects!;
    }

    final objects = <MapObject>[];

    // Маркеры доступных заказов
    for (int i = 0; i < driverState.availableOrders.length; i++) {
      final order = driverState.availableOrders[i];
      objects.add(
        PlacemarkMapObject(
          mapId: MapObjectId('order_${order.id}'),
          point: Point(latitude: order.pickupLat, longitude: order.pickupLng),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(Uint8List.fromList(
                  [255, 165, 0])), // Временная заглушка оранжевый маркер
              scale: 0.8,
            ),
          ),
        ),
      );
    }

    // Позиция водителя (центр карты)
    objects.add(
      PlacemarkMapObject(
        mapId: const MapObjectId('driver_location'),
        point: _moscowCenter,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(Uint8List.fromList(
                [0, 255, 0])), // Временная заглушка зеленый маркер
            scale: 1.0,
          ),
        ),
      ),
    );

    _cachedMapSignature = signature;
    _cachedMapObjects = objects;
    return objects;
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
