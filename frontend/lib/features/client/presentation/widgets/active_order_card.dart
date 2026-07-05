import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({
    super.key,
    required this.order,
    this.driver,
    this.onCancel,
    this.onContactDriver,
    this.onShowDetails,
  });

  final Order order;
  final Driver? driver;
  final VoidCallback? onCancel;
  final VoidCallback? onContactDriver;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Semantics(
        container: true,
        label: driver == null
            ? 'Активный заказ. Статус ${_statusText(order.status)}'
            : 'Водитель найден. Прибудет в ближайшее время.',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText(order.status),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onShowDetails != null)
                    IconButton(
                      onPressed: onShowDetails,
                      icon: const Icon(Icons.expand_less),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.pickupLocation.address} -> ${order.dropoffLocation.address}',
                style: TextStyle(color: AvroClientColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Стоимость: ${(order.finalPrice ?? order.estimatedPrice).toStringAsFixed(0)}₽',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (driver != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Водитель: ${driver!.vehicleModel}, рейтинг ${driver!.rating.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (onCancel != null &&
                      (order.status == OrderStatus.searching ||
                          order.status == OrderStatus.assigned))
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        child: const Text('Отменить'),
                      ),
                    ),
                  if (onContactDriver != null && driver != null) ...[
                    if (onCancel != null) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onContactDriver,
                        child: const Text('Связаться'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(OrderStatus status) {
    return switch (status) {
      OrderStatus.searching => 'Ищем водителя',
      OrderStatus.assigned => 'Водитель назначен',
      OrderStatus.onWay => 'Водитель едет к вам',
      OrderStatus.arrived => 'Водитель на месте',
      OrderStatus.evacuating => 'Автомобиль в пути',
      OrderStatus.awaitingPayment => 'Ожидает оплаты',
      OrderStatus.completed => 'Заказ завершен',
      OrderStatus.cancelled => 'Заказ отменен',
    };
  }
}
