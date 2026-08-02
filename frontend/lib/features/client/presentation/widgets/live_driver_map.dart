import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/real_time_driver_provider.dart';

/// Live map showing driver moving smoothly to client
class LiveDriverMap extends ConsumerStatefulWidget {
  const LiveDriverMap({
    super.key,
    required this.order,
    required this.pickupLocation,
    this.height = 300,
  });

  final Order order;
  final LocationModel pickupLocation;
  final double height;

  @override
  ConsumerState<LiveDriverMap> createState() => _LiveDriverMapState();
}

class _LiveDriverMapState extends ConsumerState<LiveDriverMap> {
  @override
  void initState() {
    super.initState();
    // Start tracking driver when map loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(realTimeDriverProvider.notifier).startTracking(
            widget.order.id,
            widget.pickupLocation,
          );
    });
  }

  @override
  void dispose() {
    // Stop tracking when map is disposed
    ref.read(realTimeDriverProvider.notifier).stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(realTimeDriverProvider);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: Stack(
        children: [
          // Base map
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: EvikOsmMapView(
              initialLat: widget.pickupLocation.lat,
              initialLng: widget.pickupLocation.lng,
              initialZoom: 13,
              markers: [
                // Pickup location marker
                EvikMapMarker(
                  lat: widget.pickupLocation.lat,
                  lng: widget.pickupLocation.lng,
                  title: 'Место погрузки',
                  color: Colors.green,
                ),
                // Destination marker if available
                EvikMapMarker(
                  lat: widget.order.dropoffLocation.lat,
                  lng: widget.order.dropoffLocation.lng,
                  title: 'Место назначения',
                  color: Colors.blue,
                ),
              ],
              routePoints: driverState.route?.points ?? const [],
            ),
          ),

          // Driver info overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AvroClientColors.background.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AvroClientColors.surface),
              ),
              child: Row(
                children: [
                  // Driver status icon
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: driverState.status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Driver info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          driverState.status.label,
                          style: const TextStyle(
                            color: AvroClientColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (ref
                                .read(realTimeDriverProvider.notifier)
                                .formattedETA !=
                            null)
                          Text(
                            'Прибытие: ${ref.read(realTimeDriverProvider.notifier).formattedETA}',
                            style: const TextStyle(
                              color: AvroClientColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Distance info
                  if (driverState.route != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${driverState.route!.distanceKm.toStringAsFixed(1)} км',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Error overlay
          if (driverState.error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  driverState.error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Loading overlay
          if (!driverState.isTracking && driverState.driverLocation == null)
            const Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.green,
                      strokeWidth: 2,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Поиск водителя...',
                      style: TextStyle(
                        color: AvroClientColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact driver info widget for order cards
class DriverInfoWidget extends ConsumerWidget {
  const DriverInfoWidget({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driverState = ref.watch(realTimeDriverProvider);

    if (!driverState.isTracking) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: driverState.status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),

          // Status and ETA
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  driverState.status.label,
                  style: const TextStyle(
                    color: AvroClientColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (ref.read(realTimeDriverProvider.notifier).formattedETA !=
                    null)
                  Text(
                    ref.read(realTimeDriverProvider.notifier).formattedETA!,
                    style: const TextStyle(
                      color: AvroClientColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),

          // Driver icon
          Icon(
            driverState.status.icon,
            color: driverState.status.color,
            size: 20,
          ),
        ],
      ),
    );
  }
}
