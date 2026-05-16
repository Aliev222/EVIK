import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/review/data/repository_impl/http_review_repository.dart';
import 'package:tow_truck_frontend/features/review/domain/entities/review.dart';
import 'package:tow_truck_frontend/features/review/domain/repositories/review_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return HttpReviewRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
    accessTokenProvider: () => ref.read(authProvider).accessToken,
  );
});

// Provider to create a review
final createReviewProvider = FutureProvider.family<Review, CreateReviewRequest>(
  (ref, request) async {
    final repository = ref.watch(reviewRepositoryProvider);
    return repository.createReview(request);
  },
);

// Provider to get driver reviews
final driverReviewsProvider = FutureProvider.family<DriverReviews, String>(
  (ref, driverId) async {
    final repository = ref.watch(reviewRepositoryProvider);
    return repository.getDriverReviews(driverId);
  },
);

// Provider to get order review
final orderReviewProvider = FutureProvider.family<Review?, String>(
  (ref, orderId) async {
    final repository = ref.watch(reviewRepositoryProvider);
    return repository.getOrderReview(orderId);
  },
);
