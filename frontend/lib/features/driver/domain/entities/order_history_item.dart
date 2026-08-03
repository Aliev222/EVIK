import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class OrderHistoryItem {
  final String id;
  final DateTime date;
  final String vehicleModel;
  final String pickupAddress;
  final String dropoffAddress;
  final int duration;
  final int earnings;
  final OrderHistoryStatus status;

  const OrderHistoryItem({
    required this.id,
    required this.date,
    required this.vehicleModel,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.duration,
    required this.earnings,
    required this.status,
  });

  String get formattedDate {
    final day = date.day.toString().padLeft(2, '0');
    final month = _getMonthName(date.month);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day $month, $hour:$minute';
  }

  String _getMonthName(int month) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return months[month];
  }

  factory OrderHistoryItem.fromOrder(Order order) {
    final vehicleDisplay = switch (order.vehicleType) {
      VehicleType.light => 'Легковой автомобиль',
      VehicleType.suv => 'Внедорожник',
      VehicleType.minibus => 'Минивэн',
      VehicleType.truck => 'Грузовой автомобиль',
    };

    final historyStatus = order.status == OrderStatus.completed
        ? OrderHistoryStatus.completed
        : OrderHistoryStatus.cancelled;

    final price = order.finalPrice ?? order.estimatedPrice;

    return OrderHistoryItem(
      id: order.id,
      date: order.createdAt,
      vehicleModel: vehicleDisplay,
      pickupAddress: order.pickupLocation.address,
      dropoffAddress: order.dropoffLocation.address,
      duration: 0,
      earnings: price.toInt(),
      status: historyStatus,
    );
  }
}

enum OrderHistoryStatus {
  completed,
  cancelled,
}