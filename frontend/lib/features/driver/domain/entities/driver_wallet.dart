class DriverWallet {
  const DriverWallet({
    required this.availableBalance,
    required this.pendingBalance,
    required this.debtBalance,
    required this.currency,
    required this.recentTransactions,
    required this.recentPayouts,
    this.maxCashDebtKopecks = 0,
  });

  final int availableBalance;
  final int pendingBalance;
  final int debtBalance;
  final String currency;
  final List<WalletTransaction> recentTransactions;
  final List<DriverPayout> recentPayouts;

  /// Platform-configured maximum allowed cash debt in kopecks.
  /// A value of 0 means the debt gate is disabled.
  final int maxCashDebtKopecks;

  /// True when enforcement is enabled and the driver's debt exceeds (or has
  /// reached) the configured threshold, blocking new orders.
  bool get debtBlocked =>
      maxCashDebtKopecks > 0 && debtBalance >= maxCashDebtKopecks;

  factory DriverWallet.fromJson(Map<String, dynamic> json) {
    return DriverWallet(
      availableBalance:
          _readMoney(json, 'available_balance', 'AvailableBalance'),
      pendingBalance: _readMoney(json, 'pending_balance', 'PendingBalance'),
      debtBalance: _readMoney(json, 'debt_balance', 'DebtBalance'),
      maxCashDebtKopecks:
          _readMoney(json, 'max_cash_debt_kopecks', 'MaxCashDebtKopecks'),
      currency: (json['currency'] ?? json['Currency'] ?? 'RUB').toString(),
      recentTransactions:
          _readList(json, 'recent_transactions', 'RecentTransactions')
              .map(WalletTransaction.fromJson)
              .toList(),
      recentPayouts: _readList(json, 'recent_payouts', 'RecentPayouts')
          .map(DriverPayout.fromJson)
          .toList(),
    );
  }
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.direction,
    required this.amount,
    required this.status,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String direction;
  final int amount;
  final String status;
  final String description;
  final DateTime? createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: _readString(json, 'id', 'ID'),
      type: _readString(json, 'type', 'Type'),
      direction: _readString(json, 'direction', 'Direction'),
      amount: _readMoney(json, 'amount', 'Amount'),
      status: _readString(json, 'status', 'Status'),
      description: _readString(json, 'description', 'Description'),
      createdAt: _readDate(json, 'created_at', 'CreatedAt'),
    );
  }
}

/// A single entry in the driver's cash-commission debt history: either an
/// accrual (cash_commission_debt — commission withheld for a cash order) or a
/// repayment (debt_repayment — commission retained from a card order).
class DriverDebtTransaction {
  const DriverDebtTransaction({
    required this.id,
    required this.type,
    required this.direction,
    required this.amount,
    required this.currency,
    required this.status,
    required this.description,
    this.orderId,
    this.orderAmount = 0,
    this.createdAt,
  });

  final String id;
  final String type;
  final String direction;
  final int amount;
  final String currency;
  final String status;
  final String description;
  final String? orderId;

  /// Total of the linked order (price_total), used to show what the order was.
  final int orderAmount;
  final DateTime? createdAt;

  bool get isAccrual => type == 'cash_commission_debt';

  factory DriverDebtTransaction.fromJson(Map<String, dynamic> json) {
    return DriverDebtTransaction(
      id: _readString(json, 'id', 'ID'),
      type: _readString(json, 'type', 'Type'),
      direction: _readString(json, 'direction', 'Direction'),
      amount: _readMoney(json, 'amount', 'Amount'),
      currency: _readString(json, 'currency', 'Currency', fallback: 'RUB'),
      status: _readString(json, 'status', 'Status', fallback: 'succeeded'),
      description: _readString(json, 'description', 'Description'),
      orderId: json['order_id']?.toString(),
      orderAmount: _readMoney(json, 'order_amount', 'OrderAmount'),
      createdAt: _readDate(json, 'created_at', 'CreatedAt'),
    );
  }
}

/// Aggregated debt history from GET /driver/wallet/debt.
class DriverDebtBreakdown {
  const DriverDebtBreakdown({
    required this.transactions,
    required this.accrued,
    required this.repaid,
  });

  final List<DriverDebtTransaction> transactions;
  final int accrued;
  final int repaid;

  int get outstanding => accrued - repaid;

  factory DriverDebtBreakdown.fromJson(Map<String, dynamic> json) {
    final items = _readList(json, 'transactions', 'Transactions');
    return DriverDebtBreakdown(
      transactions: items
          .map(DriverDebtTransaction.fromJson)
          .where((item) => item.orderId != null && item.orderId!.isNotEmpty)
          .toList(),
      accrued: _readMoney(json, 'accrued', 'Accrued'),
      repaid: _readMoney(json, 'repaid', 'Repaid'),
    );
  }

  List<DriverDebtTransaction> get accruals =>
      transactions.where((item) => item.isAccrual).toList();

  List<DriverDebtTransaction> get repayments =>
      transactions.where((item) => !item.isAccrual).toList();
}

class DriverPayout {
  const DriverPayout({
    required this.id,
    required this.amount,
    required this.status,
    required this.currency,
    required this.createdAt,
    this.failureReason,
  });

  final String id;
  final int amount;
  final String status;
  final String currency;
  final DateTime? createdAt;
  final String? failureReason;

  factory DriverPayout.fromJson(Map<String, dynamic> json) {
    return DriverPayout(
      id: _readString(json, 'id', 'ID'),
      amount: _readMoney(json, 'amount', 'Amount'),
      status: _readString(json, 'status', 'Status'),
      currency: _readString(json, 'currency', 'Currency', fallback: 'RUB'),
      createdAt: _readDate(json, 'created_at', 'CreatedAt'),
      failureReason:
          (json['failure_reason'] ?? json['FailureReason'])?.toString(),
    );
  }
}

class DriverPayoutMethod {
  const DriverPayoutMethod({
    required this.id,
    required this.type,
    required this.maskedValue,
    required this.isDefault,
    required this.status,
  });

  final String id;
  final String type;
  final String maskedValue;
  final bool isDefault;
  final String status;

  factory DriverPayoutMethod.fromJson(Map<String, dynamic> json) {
    return DriverPayoutMethod(
      id: _readString(json, 'id', 'ID'),
      type: _readString(json, 'type', 'Type'),
      maskedValue: _readString(json, 'masked_value', 'MaskedValue'),
      isDefault: (json['is_default'] ?? json['IsDefault']) == true,
      status: _readString(json, 'status', 'Status', fallback: 'active'),
    );
  }
}

class DriverSubscriptionStatus {
  const DriverSubscriptionStatus({
    required this.status,
    this.plan,
    this.amount = 0,
    this.currency = 'RUB',
    this.periodEnd,
    this.endsAt,
    this.daysLeft = 0,
    this.canAcceptOrders = false,
  });

  final String status;
  final String? plan;
  final int amount;
  final String currency;
  final DateTime? periodEnd;
  final DateTime? endsAt;
  final int daysLeft;
  final bool canAcceptOrders;

  factory DriverSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final periodEnd = _readDate(json, 'period_end', 'PeriodEnd') ??
        _readDate(json, 'ends_at', 'EndsAt');
    return DriverSubscriptionStatus(
      status: _readString(json, 'status', 'Status', fallback: 'unknown'),
      plan: (json['plan'] ?? json['Plan'])?.toString(),
      amount: _readMoney(json, 'amount', 'Amount'),
      currency: _readString(json, 'currency', 'Currency', fallback: 'RUB'),
      periodEnd: periodEnd,
      endsAt: periodEnd,
      daysLeft: _readInt(json, 'days_left', 'DaysLeft'),
      canAcceptOrders:
          (json['can_accept_orders'] ?? json['CanAcceptOrders']) == true,
    );
  }
}

List<Map<String, dynamic>> _readList(
  Map<String, dynamic> json,
  String snakeKey,
  String pascalKey,
) {
  final raw = json[snakeKey] ?? json[pascalKey];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList();
}

String _readString(
  Map<String, dynamic> json,
  String snakeKey,
  String pascalKey, {
  String fallback = '',
}) {
  return (json[snakeKey] ?? json[pascalKey] ?? fallback).toString();
}

int _readMoney(Map<String, dynamic> json, String snakeKey, String pascalKey) {
  final value = json[snakeKey] ?? json[pascalKey] ?? 0;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

int _readInt(Map<String, dynamic> json, String snakeKey, String pascalKey) {
  final value = json[snakeKey] ?? json[pascalKey] ?? 0;
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

DateTime? _readDate(
    Map<String, dynamic> json, String snakeKey, String pascalKey) {
  final value = json[snakeKey] ?? json[pascalKey];
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
