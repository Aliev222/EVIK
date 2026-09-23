import 'package:flutter/material.dart';
import 'edit_order_route_screen.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/real_time_driver_provider.dart';

class DriverInfoScreen extends ConsumerStatefulWidget {
  const DriverInfoScreen({super.key});

  @override
  ConsumerState<DriverInfoScreen> createState() => _DriverInfoScreenState();
}

class _DriverInfoScreenState extends ConsumerState<DriverInfoScreen> {
  @override
  void initState() {
    super.initState();
    // Kept as a backwards-compatible deep-link target. The old screen had a
    // second map but never started tracking; the companion screen contains
    // these details in its expandable sheet and owns the one live session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/order/tracking');
    });
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sendMessage(String phoneNumber) async {
    final uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final driver = orderFlowState.assignedDriver;
    final pickup = orderFlowState.pickupLocation;
    final destination = orderFlowState.destinationLocation;

    if (driver == null) {
      return Scaffold(
        backgroundColor: AvroClientColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AvroClientColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Получаем данные водителя',
                    textAlign: TextAlign.center,
                    style: EvikTypography.h2.copyWith(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Это может занять несколько секунд. Не закрывайте экран — заказ сохраняется.',
                    textAlign: TextAlign.center,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroClientColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  EvikButton(
                    text: 'Обновить',
                    width: double.infinity,
                    onPressed: () => ref
                        .read(orderFlowProvider.notifier)
                        .restoreActiveFlow(),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.go('/order/search'),
                    child: const Text('Вернуться к поиску'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final liveDriverLoc = ref.watch(realTimeDriverProvider).driverLocation;
    final centerLat = liveDriverLoc?.lat ??
        driver.currentLocation?.lat ??
        pickup?.latitude ??
        42.9764;
    final centerLng = liveDriverLoc?.lng ??
        driver.currentLocation?.lng ??
        pickup?.longitude ??
        47.5024;

    // Use real driver data instead of hardcoded values
    final driverName =
        driver.fullName?.isNotEmpty == true ? driver.fullName! : 'Водитель';
    final phoneNumber = driver.phone?.isNotEmpty == true
        ? driver.phone!
        : null; // No fallback phone number

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: EvikOsmMapView(
              initialLat: centerLat,
              initialLng: centerLng,
              initialZoom: 15.5,
              controlsBottomOffset: MediaQuery.paddingOf(context).bottom + 238,
              controlsBackgroundColor: AvroClientColors.background,
              controlsIconColor: AvroClientColors.accent,
              markers: [
                if (liveDriverLoc != null)
                  EvikMapMarker(
                    lat: liveDriverLoc.lat,
                    lng: liveDriverLoc.lng,
                    title: 'Водитель',
                    color: AvroClientColors.info,
                    icon: Icons.local_shipping_rounded,
                  ),
                if (pickup != null)
                  EvikMapMarker(
                    lat: pickup.latitude,
                    lng: pickup.longitude,
                    title: pickup.displayAddress,
                    color: AvroClientColors.accent,
                  ),
                if (destination != null)
                  EvikMapMarker(
                    lat: destination.latitude,
                    lng: destination.longitude,
                    title: destination.displayAddress,
                    color: AvroClientColors.textPrimary,
                    icon: Icons.flag_rounded,
                  ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: const _DriverFoundBadge(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DriverCompactSheet(
              onChangeAddress: orderFlowState.activeOrder != null &&
                      ![
                        OrderStatus.completed,
                        OrderStatus.cancelled,
                        OrderStatus.awaitingPayment
                      ].contains(orderFlowState.activeOrder!.status)
                  ? () => editOrderRoute(context, orderFlowState.activeOrder!)
                  : null,
              driverName: driverName,
              vehicleNumber: driver.vehicleNumber,
              vehicleModel: driver.vehicleModel,
              rating: driver.rating,
              onCall: phoneNumber != null
                  ? () => _makePhoneCall(phoneNumber)
                  : () {},
              onMessage:
                  phoneNumber != null ? () => _sendMessage(phoneNumber) : () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverFoundBadge extends StatelessWidget {
  const _DriverFoundBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroClientColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AvroClientColors.success,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Эвакуатор принял заказ',
                style: EvikTypography.bodyMedium.copyWith(
                  color: AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverCompactSheet extends StatelessWidget {
  const _DriverCompactSheet({
    required this.driverName,
    required this.vehicleNumber,
    required this.vehicleModel,
    required this.rating,
    required this.onCall,
    required this.onMessage,
    this.onChangeAddress,
  });

  final String driverName;
  final String vehicleNumber;
  final String vehicleModel;
  final double rating;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback? onChangeAddress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AvroClientColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AvroClientColors.accent,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AvroClientColors.tabInactive,
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
                        driverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodyLarge.copyWith(
                          color: AvroClientColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$vehicleNumber · $vehicleModel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroClientColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '★ ${rating.toStringAsFixed(1)}',
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroClientColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Позвонить',
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        AvroClientColors.accent.withValues(alpha: 0.12),
                    foregroundColor: AvroClientColors.accent,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Чат',
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AvroClientColors.surface,
                    foregroundColor: AvroClientColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (onChangeAddress != null)
              TextButton.icon(
                  onPressed: onChangeAddress,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Сменить адрес')),
            Text(
              'Местоположение эвакуатора обновляется на карте',
              textAlign: TextAlign.center,
              style: EvikTypography.bodySmall.copyWith(
                color: AvroClientColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
