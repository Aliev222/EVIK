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
