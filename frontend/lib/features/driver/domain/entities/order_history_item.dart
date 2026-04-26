class OrderHistoryItem {
  final String id;
  final DateTime date;
  final String vehicleModel;
  final String pickupAddress;
  final String dropoffAddress;
  final int duration; // в минутах
  final int earnings; // в рублях
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
}

enum OrderHistoryStatus {
  completed,
  cancelled,
}