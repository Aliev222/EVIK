import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../order/domain/entities/order.dart';
import '../providers/driver_navigation_provider.dart';

class DriverActiveOrderCard extends ConsumerWidget {
  const DriverActiveOrderCard({
    super.key,
    required this.order,
    required this.driverLat,
    required this.driverLng,
    required this.onStatusUpdate,
    required this.onCancel,
    required this.onComplete,
  });

  final Order order;
  final double? driverLat;
  final double? driverLng;
  final Future<void> Function(OrderStatus status) onStatusUpdate;
  final Future<void> Function() onCancel;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.watch(driverNavigationProvider);
    final distanceToPickup = _distanceTo(order.pickupLocation);
    final distanceToDropoff = _distanceTo(order.dropoffLocation);
    final isNearPickup = distanceToPickup != null && distanceToPickup <= 0.25;
    final isNearDropoff =
        distanceToDropoff != null && distanceToDropoff <= 0.35;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusTitle(order.status),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _statusSubtitle(order.status),
            style: const TextStyle(
              fontSize: 14,
              color: EvikColors.textSecondaryDark,
            ),
          ),
          const SizedBox(height: 14),
          _InfoRow(title: 'Забор', value: order.pickupLocation.address),
          _InfoRow(title: 'Доставка', value: order.dropoffLocation.address),
          _InfoRow(
            title: 'Стоимость',
            value:
                '${(order.finalPrice ?? order.estimatedPrice).toStringAsFixed(0)}₽',
          ),
          if (navigation.eta != null)
            _InfoRow(
              title: 'ETA',
              value: '${navigation.eta!.inMinutes} мин',
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _launch(Uri.parse('tel:${order.clientId}')),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Позвонить'),
              ),
              OutlinedButton.icon(
                onPressed: () => _launch(Uri.parse('sms:${order.clientId}')),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('SMS'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final target = order.status == OrderStatus.evacuating
                      ? order.dropoffLocation
                      : order.pickupLocation;
                  ref
                      .read(driverNavigationProvider.notifier)
                      .openExternalNavigation(target.lat, target.lng);
                },
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Навигация'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Отменить заказ?'),
                      content: const Text(
                        'Клиент получит уведомление об отмене.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Нет'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Отменить'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await onCancel();
                  }
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Отменить'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (order.status == OrderStatus.assigned)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => onStatusUpdate(OrderStatus.onWay),
                child: const Text('Еду к клиенту'),
              ),
            ),
          if (order.status == OrderStatus.onWay)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isNearPickup
                    ? () => onStatusUpdate(OrderStatus.arrived)
                    : null,
                child: Text(
                  isNearPickup ? 'Я на месте' : 'Я на месте • подъедьте ближе',
                ),
              ),
            ),
          if (order.status == OrderStatus.arrived)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => onStatusUpdate(OrderStatus.evacuating),
                child: const Text('Начать эвакуацию'),
              ),
            ),
          if (order.status == OrderStatus.evacuating)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isNearDropoff ? onComplete : null,
                child: Text(
                  isNearDropoff
                      ? 'Завершить заказ'
                      : 'Завершить заказ • подъедьте к точке',
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusTitle(OrderStatus status) {
    return switch (status) {
      OrderStatus.assigned => 'Заказ принят',
      OrderStatus.onWay => 'Следуете к клиенту',
      OrderStatus.arrived => 'Вы прибыли к клиенту',
      OrderStatus.evacuating => 'Везете автомобиль клиента',
      OrderStatus.completed => 'Заказ завершен',
      OrderStatus.cancelled => 'Заказ отменен',
      OrderStatus.searching => 'Новый заказ',
    };
  }

  String _statusSubtitle(OrderStatus status) {
    return switch (status) {
      OrderStatus.assigned =>
        'Постройте маршрут и свяжитесь с клиентом при необходимости.',
      OrderStatus.onWay =>
        'Кнопка "Я на месте" станет активной, когда вы будете рядом.',
      OrderStatus.arrived =>
        'Подтвердите начало эвакуации, когда автомобиль подготовлен.',
      OrderStatus.evacuating =>
        'Двигайтесь к точке доставки. Кнопка завершения доступна рядом с адресом.',
      OrderStatus.completed => 'Оплата проведена, можно ждать следующий заказ.',
      OrderStatus.cancelled => 'Заказ закрыт.',
      OrderStatus.searching => 'Ожидается подтверждение.',
    };
  }

  double? _distanceTo(LocationModel target) {
    if (driverLat == null || driverLng == null) {
      return null;
    }

    return Geolocator.distanceBetween(
          driverLat!,
          driverLng!,
          target.lat,
          target.lng,
        ) /
        1000;
  }

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: EvikColors.textSecondaryDark,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
