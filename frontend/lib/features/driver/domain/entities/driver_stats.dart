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
      ordersCount: 0,
      earnings: 0,
      rating: 5,
    ),
    today: TodayStats(
      ordersCount: 0,
      earnings: 0,
    ),
    weekly: WeeklyStats(
      totalEarnings: 0,
      weeklyChange: 0,
      ordersCount: 0,
      averageOrder: 0,
      hoursWorked: 0,
      rating: 5,
      availableForWithdrawal: 0,
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
