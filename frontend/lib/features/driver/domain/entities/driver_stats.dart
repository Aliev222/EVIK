class DriverStats {
  final YesterdayStats yesterday;
  final TodayStats today;
  final WeeklyStats weekly;

  const DriverStats({
    required this.yesterday,
    required this.today,
    required this.weekly,
  });

  static const DriverStats mock = DriverStats(
    yesterday: YesterdayStats(
      ordersCount: 4,
      earnings: 6200,
      rating: 4.9,
    ),
    today: TodayStats(
      ordersCount: 2,
      earnings: 3200,
    ),
    weekly: WeeklyStats(
      totalEarnings: 18400,
      weeklyChange: 12,
      ordersCount: 12,
      averageOrder: 1533,
      hoursWorked: 28,
      rating: 4.9,
      availableForWithdrawal: 18400,
    ),
  );
}

class YesterdayStats {
  final int ordersCount;
  final double earnings;
  final double rating;

  const YesterdayStats({
    required this.ordersCount,
    required this.earnings,
    required this.rating,
  });
}

class TodayStats {
  final int ordersCount;
  final double earnings;

  const TodayStats({
    required this.ordersCount,
    required this.earnings,
  });

  String get displayText {
    return '$ordersCount заказа • ${earnings.toInt()} ₽';
  }
}

class WeeklyStats {
  final double totalEarnings;
  final int weeklyChange; // процент изменения
  final int ordersCount;
  final double averageOrder;
  final int hoursWorked;
  final double rating;
  final double availableForWithdrawal;

  const WeeklyStats({
    required this.totalEarnings,
    required this.weeklyChange,
    required this.ordersCount,
    required this.averageOrder,
    required this.hoursWorked,
    required this.rating,
    required this.availableForWithdrawal,
  });

  String get weeklyChangeText {
    final sign = weeklyChange >= 0 ? '+' : '';
    return '$sign$weeklyChange% чем на прошлой неделе';
  }

  String get formattedEarnings {
    return '${totalEarnings.toInt()} ₽';
  }

  String get formattedAverage {
    return '${averageOrder.toInt()} ₽';
  }

  String get formattedWithdrawal {
    return '${availableForWithdrawal.toInt()} ₽';
  }
}