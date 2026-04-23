import '../../../core/network/api_client.dart';

class DriverStatusDto {
  const DriverStatusDto({
    required this.id,
    required this.status,
    this.currentOrderId,
  });

  final String id;
  final String status;
  final String? currentOrderId;

  factory DriverStatusDto.fromJson(Map<String, dynamic> json) {
    return DriverStatusDto(
      id: json['id'] as String,
      status: json['status'] as String,
      currentOrderId: json['current_order_id'] as String?,
    );
  }
}

class DriverLocationDto {
  const DriverLocationDto({
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  final double lat;
  final double lng;
  final DateTime updatedAt;

  factory DriverLocationDto.fromJson(Map<String, dynamic> json) {
    return DriverLocationDto(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

abstract class DriverRemoteDataSource {
  Future<DriverStatusDto> setStatus({
    required String driverId,
    required String userId,
    required String status,
    double? lat,
    double? lng,
  });

  Future<DriverStatusDto> getDriver(String driverId);
  Future<DriverLocationDto> getLocation(String driverId);
}

class HttpDriverRemoteDataSource implements DriverRemoteDataSource {
  const HttpDriverRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  @override
  Future<DriverStatusDto> setStatus({
    required String driverId,
    required String userId,
    required String status,
    double? lat,
    double? lng,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'status': status,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };
    final json =
        await apiClient.post('/api/v1/drivers/$driverId/status', payload);
    return DriverStatusDto.fromJson(json['driver'] as Map<String, dynamic>);
  }

  @override
  Future<DriverStatusDto> getDriver(String driverId) async {
    final json = await apiClient.get('/api/v1/drivers/$driverId');
    return DriverStatusDto.fromJson(json['driver'] as Map<String, dynamic>);
  }

  @override
  Future<DriverLocationDto> getLocation(String driverId) async {
    final json = await apiClient.get('/api/v1/drivers/$driverId/location');
    return DriverLocationDto.fromJson(json['location'] as Map<String, dynamic>);
  }
}
