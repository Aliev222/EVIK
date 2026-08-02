import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';

/// Driver marker status with corresponding colors and icons
enum DriverMarkerStatus {
  toPickup,
  toDestination,
  waiting;

  Color get color {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return AvroClientColors.success; // Green - coming to pickup
      case DriverMarkerStatus.toDestination:
        return AvroClientColors.info; // Blue - driving to destination
      case DriverMarkerStatus.waiting:
        return AvroClientColors.warning; // Orange - waiting
    }
  }

  String get iconPath {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return 'assets/images/vehicles/truck.png'; // Пустой эвакуатор
      case DriverMarkerStatus.toDestination:
        return 'assets/images/vehicles/truck_loaded.png'; // Загруженный эвакуатор
      case DriverMarkerStatus.waiting:
        return 'assets/images/vehicles/truck.png'; // Ожидает
    }
  }

  IconData get icon {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return Icons.local_shipping; // Fallback icon
      case DriverMarkerStatus.toDestination:
        return Icons.local_shipping; // Fallback icon
      case DriverMarkerStatus.waiting:
        return Icons.pause; // Pause icon
    }
  }

  String get label {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return 'Едет к вам';
      case DriverMarkerStatus.toDestination:
        return 'Везет машину';
      case DriverMarkerStatus.waiting:
        return 'Ожидает';
    }
  }
}
