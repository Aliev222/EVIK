class DailyEarnings {
  const DailyEarnings({
    required this.date,
    required this.totalEarnings,
    required this.completedOrders,
    required this.averageOrderPrice,
    required this.workingHours,
  });

  final DateTime date;
  final double totalEarnings;
  final int completedOrders;
  final double averageOrderPrice;
  final int workingHours;
}

class EarningsStats {
  const EarningsStats({
    required this.todayAmount,
    required this.todayOrders,
    required this.weekAmount,
    required this.weekOrders,
    required this.monthAmount,
    required this.monthOrders,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final int todayAmount;
  final int todayOrders;
  final int weekAmount;
  final int weekOrders;
  final int monthAmount;
  final int monthOrders;
  final double ratingAverage;
  final int ratingCount;

  factory EarningsStats.fromJson(Map json) {
    return EarningsStats(
      todayAmount: (json['today']['amount'] as num).toInt(),
      todayOrders: (json['today']['orders'] as num).toInt(),
      weekAmount: (json['week']['amount'] as num).toInt(),
      weekOrders: (json['week']['orders'] as num).toInt(),
      monthAmount: (json['month']['amount'] as num).toInt(),
      monthOrders: (json['month']['orders'] as num).toInt(),
      ratingAverage: (json['rating']['average'] as num).toDouble(),
      ratingCount: (json['rating']['count'] as num).toInt(),
    );
  }

  static const zero = EarningsStats(
    todayAmount: 0,
    todayOrders: 0,
    weekAmount: 0,
    weekOrders: 0,
    monthAmount: 0,
    monthOrders: 0,
    ratingAverage: 5,
    ratingCount: 0,
  );
}
