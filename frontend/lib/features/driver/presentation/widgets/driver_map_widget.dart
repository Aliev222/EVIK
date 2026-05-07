import 'package:flutter/material.dart';

import '../../../map/presentation/widgets/promaps_view_simple.dart';
import '../../../order/domain/entities/order.dart';

class DriverMapWidget extends StatelessWidget {
  const DriverMapWidget({
    super.key,
    required this.driverLocation,
    this.currentOrder,
    this.availableOrders = const <Order>[],
    this.etaText,
  });

  final LocationModel? driverLocation;
  final Order? currentOrder;
  final List<Order> availableOrders;
  final String? etaText;

  @override
  Widget build(BuildContext context) {
    final initialLat =
        driverLocation?.lat ?? currentOrder?.pickupLocation.lat ?? 55.751244;
    final initialLng =
        driverLocation?.lng ?? currentOrder?.pickupLocation.lng ?? 37.618423;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: ProMapsViewSimple(
              initialLat: initialLat,
              initialLng: initialLng,
              initialZoom: currentOrder == null ? 12 : 10,
              markers: [
                if (driverLocation != null)
                  ProMapMarker(
                    lat: driverLocation!.lat,
                    lng: driverLocation!.lng,
                    title: 'Вы',
                    color: const Color(0xFF2E90FA),
                  ),
                if (currentOrder != null) ...[
                  ProMapMarker(
                    lat: currentOrder!.pickupLocation.lat,
                    lng: currentOrder!.pickupLocation.lng,
                    title: currentOrder!.pickupLocation.address,
                    color: const Color(0xFF12B76A),
                  ),
                  ProMapMarker(
                    lat: currentOrder!.dropoffLocation.lat,
                    lng: currentOrder!.dropoffLocation.lng,
                    title: currentOrder!.dropoffLocation.address,
                    color: const Color(0xFFF04438),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _LegendChip(color: Color(0xFF2E90FA), text: 'Вы'),
                if (currentOrder != null)
                  const _LegendChip(
                    color: Color(0xFF12B76A),
                    text: 'Забор',
                  ),
                if (currentOrder != null)
                  const _LegendChip(
                    color: Color(0xFFF04438),
                    text: 'Доставка',
                  ),
                if (currentOrder == null && availableOrders.isNotEmpty)
                  _LegendChip(
                    color: const Color(0xFFF79009),
                    text: '${availableOrders.length} заказов рядом',
                  ),
                if (etaText != null)
                  _LegendChip(
                    color: const Color(0xFF101828),
                    text: etaText!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
