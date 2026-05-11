import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../map/presentation/widgets/evik_osm_map_view.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class DriverInfoScreen extends ConsumerWidget {
  const DriverInfoScreen({super.key});

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sendMessage(String phoneNumber) async {
    final uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _goToTracking(BuildContext context, WidgetRef ref) {
    ref.read(orderFlowProvider.notifier).goToTracking();
    context.go('/order/tracking');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final driver = orderFlowState.assignedDriver;
    final pickup = orderFlowState.pickupLocation;
    final destination = orderFlowState.destinationLocation;

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.tracking &&
          previous?.currentStep != OrderFlowStep.tracking) {
        context.go('/order/tracking');
      }
    });

    if (driver == null) {
      return const Scaffold(
        backgroundColor: EvikColors.gray50,
        body: Center(child: Text('Информация о водителе недоступна')),
      );
    }

    final centerLat = driver.currentLocation?.lat ??
        pickup?.latitude ??
        AppConstants.moscowLat;
    final centerLng = driver.currentLocation?.lng ??
        pickup?.longitude ??
        AppConstants.moscowLng;
    const phoneNumber = '+7(999)123-45-67';

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: Stack(
        children: [
          Positioned.fill(
            child: EvikOsmMapView(
              initialLat: centerLat,
              initialLng: centerLng,
              initialZoom: 15.5,
              controlsBottomOffset: MediaQuery.paddingOf(context).bottom + 238,
              controlsBackgroundColor: EvikColors.primaryWhite,
              controlsIconColor: EvikColors.accentOrange,
              markers: [
                if (driver.currentLocation != null)
                  EvikMapMarker(
                    lat: driver.currentLocation!.lat,
                    lng: driver.currentLocation!.lng,
                    title: 'Водитель',
                    color: EvikColors.infoBlue,
                    icon: Icons.local_shipping_rounded,
                  ),
                if (pickup != null)
                  EvikMapMarker(
                    lat: pickup.latitude,
                    lng: pickup.longitude,
                    title: pickup.displayAddress,
                    color: EvikColors.accentOrange,
                  ),
                if (destination != null)
                  EvikMapMarker(
                    lat: destination.latitude,
                    lng: destination.longitude,
                    title: destination.displayAddress,
                    color: EvikColors.gray700,
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
              driverName: 'Водитель EVIK',
              vehicleNumber: driver.vehicleNumber,
              vehicleModel: driver.vehicleModel,
              rating: driver.rating,
              onCall: () => _makePhoneCall(phoneNumber),
              onMessage: () => _sendMessage(phoneNumber),
              onTrack: () => _goToTracking(context, ref),
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
      color: EvikColors.primaryWhite,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: EvikColors.successGreen,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Эвакуатор принял заказ',
                style: EvikTypography.bodyMedium.copyWith(
                  color: EvikColors.primaryBlack,
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
    required this.onTrack,
  });

  final String driverName;
  final String vehicleNumber;
  final String vehicleModel;
  final double rating;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
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
                    color: EvikColors.gray100,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: EvikColors.accentOrange,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: EvikColors.gray500,
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
                          color: EvikColors.primaryBlack,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$vehicleNumber · $vehicleModel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.gray600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '★ ${rating.toStringAsFixed(1)}',
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.accentOrange,
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
                        EvikColors.accentOrange.withValues(alpha: 0.12),
                    foregroundColor: EvikColors.accentOrange,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Чат',
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: EvikColors.gray100,
                    foregroundColor: EvikColors.gray700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            EvikButton(
              text: 'Отследить на карте',
              onPressed: onTrack,
              width: double.infinity,
              variant: EvikButtonVariant.primary,
              icon: const Icon(Icons.map_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
