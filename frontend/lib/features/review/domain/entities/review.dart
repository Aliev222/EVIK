class Review {
  const Review({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.clientId,
    required this.stars,
    required this.text,
    required this.createdAt,
    this.driverName,
    this.clientName,
  });

  final String id;
  final String orderId;
  final String driverId;
  final String clientId;
  final int stars;
  final String text;
  final DateTime createdAt;
  final String? driverName;
  final String? clientName;

  factory Review.fromMap(Map<String, dynamic> map) {
    return Review(
      id: map['id']?.toString() ?? '',
      orderId: map['order_id']?.toString() ?? '',
      driverId: map['driver_id']?.toString() ?? '',
      clientId: map['client_id']?.toString() ?? '',
      stars: (map['stars'] as num?)?.toInt() ?? 0,
      text: map['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      driverName: map['driver_name']?.toString(),
      clientName: map['client_name']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'driver_id': driverId,
      'client_id': clientId,
      'stars': stars,
      'text': text,
      'created_at': createdAt.toIso8601String(),
      if (driverName != null) 'driver_name': driverName,
      if (clientName != null) 'client_name': clientName,
    };
  }
}

class DriverReviews {
  const DriverReviews({
    required this.items,
    required this.total,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final List<Review> items;
  final int total;
  final double ratingAverage;
  final int ratingCount;

  factory DriverReviews.fromMap(Map<String, dynamic> map) {
    final itemsList = map['items'] as List<dynamic>? ?? const [];
    final items = itemsList
        .map((item) => Review.fromMap(item as Map<String, dynamic>))
        .toList();

    return DriverReviews(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? 0,
      ratingAverage: (map['rating_average'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (map['rating_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class CreateReviewRequest {
  const CreateReviewRequest({
    required this.orderId,
    required this.driverId,
    required this.stars,
    required this.text,
  });

  final String orderId;
  final String driverId;
  final int stars;
  final String text;

  Map<String, dynamic> toMap() {
    return {
      'order_id': orderId,
      'driver_id': driverId,
      'stars': stars,
      'text': text,
    };
  }
}