import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

class MapLocation {
  const MapLocation({
    required this.latitude,
    required this.longitude,
    this.address,
    this.description,
  });

  final double latitude;
  final double longitude;
  final String? address;
  final String? description;

  MapLocation copyWith({
    double? latitude,
    double? longitude,
    String? address,
    String? description,
  }) {
    return MapLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      description: description ?? this.description,
    );
  }

  factory MapLocation.fromJson(Map<String, dynamic> json) {
    return MapLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'description': description,
    };
  }

  String get displayAddress => address ?? description ?? 'Адрес не указан';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MapLocation &&
            latitude == other.latitude &&
            longitude == other.longitude &&
            address == other.address &&
            description == other.description;
  }

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      address.hashCode ^
      description.hashCode;
}

extension MapLocationExtension on MapLocation {
  LocationModel toLocationModel() {
    return LocationModel(
      lat: latitude,
      lng: longitude,
      address: displayAddress,
    );
  }
}
