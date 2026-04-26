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
    required this.today,
    required this.week,
    required this.month,
    required this.ordersToday,
    required this.ordersWeek,
    required this.ordersMonth,
    required this.averageRating,
  });

  final double today;
  final double week;
  final double month;
  final int ordersToday;
  final int ordersWeek;
  final int ordersMonth;
  final double averageRating;

  static const zero = EarningsStats(
    today: 0,
    week: 0,
    month: 0,
    ordersToday: 0,
    ordersWeek: 0,
    ordersMonth: 0,
    averageRating: 5,
  );
}
