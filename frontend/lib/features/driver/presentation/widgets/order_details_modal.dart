import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class OrderDetailsModal extends StatefulWidget {
  const OrderDetailsModal({
    super.key,
    required this.order,
    required this.onAccept,
    required this.onDecline,
  });

  final Order order;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  State<OrderDetailsModal> createState() => _OrderDetailsModalState();
}

class _OrderDetailsModalState extends State<OrderDetailsModal> {
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        final navigator = Navigator.of(context);
        await widget.onDecline();
        if (mounted) {
          navigator.maybePop();
        }
        return;
      }

      setState(() {
        _remainingSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remainingSeconds / 30;

    return Scaffold(
      backgroundColor: AvroDriverColors.darkBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Новый заказ',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ),
                  Text(
                    '$_remainingSeconds c',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                color: AvroDriverColors.success,
              ),
              const SizedBox(height: 20),
              _ModalCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line('Забор', widget.order.pickupLocation.address),
                    _line('Доставка', widget.order.dropoffLocation.address),
                    _line(
                      'Стоимость',
                      '${widget.order.estimatedPrice.toStringAsFixed(0)}₽',
                    ),
                    _line('Расстояние',
                        '${widget.order.distance.toStringAsFixed(1)} км'),
                    if ((widget.order.notes ?? '').trim().isNotEmpty)
                      _line('Проблема', widget.order.notes!),
                    _line(
                        'Автомобиль', _vehicleLabel(widget.order.vehicleType)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: AvroDriverColors.success,
                  ),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final navigator = Navigator.of(context);
                    await widget.onAccept();
                    if (mounted) {
                      navigator.pop();
                    }
                  },
                  child: const Text('Принять заказ'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final navigator = Navigator.of(context);
                    await widget.onDecline();
                    if (mounted) {
                      navigator.pop();
                    }
                  },
                  child: const Text('Отклонить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AvroDriverColors.grayHint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: AvroDriverColors.darkBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _vehicleLabel(VehicleType type) {
    return switch (type) {
      VehicleType.light => 'Легковой автомобиль',
      VehicleType.suv => 'SUV / кроссовер',
      VehicleType.minibus => 'Минивэн',
      VehicleType.truck => 'Грузовой автомобиль',
    };
  }
}

class _ModalCard extends StatelessWidget {
  const _ModalCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }
}
