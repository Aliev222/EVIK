import 'package:tow_truck_frontend/features/review/domain/entities/review.dart';

abstract class ReviewRepository {
  Future<Review> createReview(CreateReviewRequest request);
  Future<DriverReviews> getDriverReviews(String driverId, {int limit = 50});
  Future<Review?> getOrderReview(String orderId);
}
