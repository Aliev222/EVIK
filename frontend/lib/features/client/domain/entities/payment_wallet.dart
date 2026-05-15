class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.holder,
    required this.status,
    required this.isDefault,
    required this.createdAt,
  });

  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String holder;
  final String status;
  final bool isDefault;
  final DateTime createdAt;

  String get displayBrand {
    return switch (brand) {
      'visa' => 'Visa',
      'mastercard' => 'MC',
      'mir' => 'МИР',
      _ => 'Card',
    };
  }

  String get maskedNumber => '•••• •••• •••• $last4';

  String get expiresAt {
    final month = expMonth.toString().padLeft(2, '0');
    final year = (expYear % 100).toString().padLeft(2, '0');
    return 'До $month/$year';
  }

  factory PaymentCard.fromJson(Map<String, dynamic> json) {
    return PaymentCard(
      id: json['id']?.toString() ?? '',
      brand: json['brand']?.toString() ?? 'unknown',
      last4: json['last4']?.toString() ?? '',
      expMonth: (json['exp_month'] as num?)?.toInt() ?? 1,
      expYear: (json['exp_year'] as num?)?.toInt() ?? 2000,
      holder: json['holder']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      isDefault: json['is_default'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  PaymentCard copyWith({bool? isDefault, String? status}) {
    return PaymentCard(
      id: id,
      brand: brand,
      last4: last4,
      expMonth: expMonth,
      expYear: expYear,
      holder: holder,
      status: status ?? this.status,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
    );
  }
}

class AddCardInitResponse {
  const AddCardInitResponse({
    required this.confirmationUrl,
    required this.paymentMethodId,
  });

  final String confirmationUrl;
  final String paymentMethodId;

  factory AddCardInitResponse.fromJson(Map<String, dynamic> json) {
    return AddCardInitResponse(
      confirmationUrl: json['confirmation_url']?.toString() ?? '',
      paymentMethodId: json['payment_method_id']?.toString() ?? '',
    );
  }
}

class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.paymentMethod,
    required this.amount,
    required this.currency,
    required this.status,
    this.confirmationUrl,
    this.createdAt,
    this.paidAt,
  });

  final String id;
  final String orderId;
  final String paymentMethod;
  final int amount;
  final String currency;
  final String status;
  final String? confirmationUrl;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get isPending => status == 'pending' || status == 'waiting_for_capture';
  bool get isSucceeded => status == 'succeeded';
  bool get isFailed => status == 'failed' || status == 'canceled';

  factory OrderPayment.fromJson(Map<String, dynamic> json) {
    return OrderPayment(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'RUB',
      status: json['status']?.toString() ?? 'pending',
      confirmationUrl: json['confirmation_url']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      paidAt: DateTime.tryParse(json['paid_at']?.toString() ?? ''),
    );
  }
}

class OrderReceipt {
  const OrderReceipt({
    required this.orderId,
    required this.priceTotal,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.commissionAmount,
    required this.driverAmount,
    this.paymentId,
    this.currency = 'RUB',
    this.createdAt,
    this.completedAt,
    this.driverId,
    this.driverName,
    this.driverPhone,
  });

  final String orderId;
  final String? paymentId;
  final int priceTotal;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final int commissionAmount;
  final int driverAmount;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;

  factory OrderReceipt.fromJson(Map<String, dynamic> json) {
    return OrderReceipt(
      orderId: json['order_id']?.toString() ?? '',
      paymentId: json['payment_id']?.toString(),
      priceTotal: (json['price_total'] as num?)?.toInt() ??
          (json['amount'] as num?)?.toInt() ??
          0,
      currency: json['currency']?.toString() ?? 'RUB',
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      paymentStatus: json['payment_status']?.toString() ??
          json['status']?.toString() ??
          'pending',
      commissionAmount: (json['commission_amount'] as num?)?.toInt() ??
          (json['commission'] as num?)?.toInt() ??
          0,
      driverAmount: (json['driver_amount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      driverId: json['driver_id']?.toString(),
      driverName: json['driver_name']?.toString(),
      driverPhone: json['driver_phone']?.toString(),
    );
  }
}

class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.orderId,
    required this.title,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String title;
  final int amount;
  final String status;
  final DateTime createdAt;

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Оплата заказа',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'completed',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PaymentWallet {
  const PaymentWallet({
    required this.cards,
    required this.payments,
    this.promocode,
  });

  final List<PaymentCard> cards;
  final List<PaymentTransaction> payments;
  final AppliedPromocode? promocode;

  PaymentCard? get defaultCard {
    for (final card in cards) {
      if (card.isDefault) return card;
    }
    return cards.isEmpty ? null : cards.first;
  }

  factory PaymentWallet.fromJson(Map<String, dynamic> json) {
    final cards = json['cards'] as List<dynamic>? ?? const [];
    final payments = json['payments'] as List<dynamic>? ?? const [];
    return PaymentWallet(
      cards: cards
          .map((item) => PaymentCard.fromJson(item as Map<String, dynamic>))
          .toList(),
      payments: payments
          .map((item) =>
              PaymentTransaction.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  PaymentWallet copyWith({
    List<PaymentCard>? cards,
    List<PaymentTransaction>? payments,
    AppliedPromocode? promocode,
  }) {
    return PaymentWallet(
      cards: cards ?? this.cards,
      payments: payments ?? this.payments,
      promocode: promocode ?? this.promocode,
    );
  }
}

class AppliedPromocode {
  const AppliedPromocode({
    required this.code,
    required this.description,
    required this.discountPct,
  });

  final String code;
  final String description;
  final int discountPct;

  factory AppliedPromocode.fromJson(Map<String, dynamic> json) {
    return AppliedPromocode(
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      discountPct: (json['discount_pct'] as num?)?.toInt() ?? 0,
    );
  }
}

class AddPaymentCardCommand {
  const AddPaymentCardCommand({
    required this.cardNumber,
    required this.expMonth,
    required this.expYear,
    required this.holder,
    required this.cvv,
    required this.setDefault,
  });

  final String cardNumber;
  final int expMonth;
  final int expYear;
  final String holder;
  final String cvv;
  final bool setDefault;
}
