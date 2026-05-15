import '../../../../core/network/api_client.dart';
import '../../domain/entities/review.dart';
import '../../domain/repositories/review_repository.dart';

class HttpReviewRepository implements ReviewRepository {
  const HttpReviewRepository({
    required ApiClient apiClient,
    required String? accessToken,
    String? Function()? accessTokenProvider,
  })  : _apiClient = apiClient,
        _accessToken = accessToken,
        _accessTokenProvider = accessTokenProvider;

  final ApiClient _apiClient;
  final String? _accessToken;
  final String? Function()? _accessTokenProvider;

  Map<String, String>? get _authHeaders {
    final token = _accessTokenProvider?.call() ?? _accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  @override
  Future<Review> createReview(CreateReviewRequest request) async {
    final response = await _apiClient.post(
      '/api/v1/reviews',
      request.toMap(),
      headers: _authHeaders,
    );

    final reviewData = response['review'] as Map<String, dynamic>;
    return Review.fromMap(reviewData);
  }

  @override
  Future<DriverReviews> getDriverReviews(String driverId, {int limit = 50}) async {
    final response = await _apiClient.get(
      '/api/v1/drivers/$driverId/reviews?limit=$limit',
      headers: _authHeaders,
    );

    return DriverReviews.fromMap(response);
  }

  @override
  Future<Review?> getOrderReview(String orderId) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/orders/$orderId/review',
        headers: _authHeaders,
      );

      final reviewData = response['review'] as Map<String, dynamic>;
      return Review.fromMap(reviewData);
    } catch (e) {
      // Return null if review not found (404)
      if (e.toString().contains('404') || e.toString().contains('not found')) {
        return null;
      }
      rethrow;
    }
  }
}