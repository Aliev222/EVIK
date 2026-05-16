// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/client/domain/entities/payment_wallet.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

part 'order_flow_state.freezed.dart';
part 'order_flow_state.g.dart';

enum TowTruckType {
  @JsonValue('winch')
  winch,
  @JsonValue('platform')
  platform,
  @JsonValue('manipulator')
  manipulator,
}

enum OrderFlowStep {
  idle,
  pickupSelection,
  destinationSelection,
  vehicleSelection,
  towTruckSelection,
  driverSearch,
  driverFound,
  tracking,
  completion,
  rating,
}

@freezed
class OrderFlowState with _$OrderFlowState {
  const factory OrderFlowState({
    @Default(OrderFlowStep.idle) OrderFlowStep currentStep,
    MapLocation? pickupLocation,
    MapLocation? destinationLocation,
    VehicleType? selectedVehicleType,
    TowTruckType? selectedTowTruckType,
    @Default(0) int blockedWheelsCount,
    @Default('') String clientComment,
    @Default(false) bool isLoading,
    String? errorMessage,
    @JsonKey(includeFromJson: false, includeToJson: false) Order? activeOrder,
    @JsonKey(includeFromJson: false, includeToJson: false)
    Driver? assignedDriver,
    @Default(PaymentMethod.cash) PaymentMethod selectedPaymentMethod,
    @JsonKey(includeFromJson: false, includeToJson: false)
    OrderPayment? payment,
    @JsonKey(includeFromJson: false, includeToJson: false)
    OrderReceipt? receipt,
    @Default(false) bool isPaymentProcessing,
    @Default(false) bool isReceiptLoading,
    String? receiptError,
    @Default(0) int searchDurationSeconds,
    @Default(0.0) double estimatedPrice,
    @Default(0.0) double distance,
  }) = _OrderFlowState;

  factory OrderFlowState.fromJson(Map<String, dynamic> json) =>
      _$OrderFlowStateFromJson(json);
}

extension TowTruckTypeExtension on TowTruckType {
  String get displayName {
    switch (this) {
      case TowTruckType.winch:
        return '�������';
      case TowTruckType.platform:
        return '���������';
      case TowTruckType.manipulator:
        return '�����������';
    }
  }

  String get shortLabel {
    switch (this) {
      case TowTruckType.winch:
        return '��������';
      case TowTruckType.platform:
        return '���������';
      case TowTruckType.manipulator:
        return '�����������';
    }
  }

  String get description {
    switch (this) {
      case TowTruckType.winch:
        return '��� ���� �� ���� ��� � ���������������� ��������';
      case TowTruckType.platform:
        return '������ �������� ���������� �� ���������';
      case TowTruckType.manipulator:
        return '��� ������� ��������, ������ ��� ������� �����';
    }
  }

  String get assetPath {
    switch (this) {
      case TowTruckType.winch:
        return EvikAssetPaths.winchTowTruck;
      case TowTruckType.platform:
        return EvikAssetPaths.platformTowTruck;
      case TowTruckType.manipulator:
        return EvikAssetPaths.manipulatorTowTruck;
    }
  }
}

extension VehicleTypeExtension on VehicleType {
  String get displayName {
    switch (this) {
      case VehicleType.light:
        return '�����';
      case VehicleType.suv:
        return '���������';
      case VehicleType.minibus:
        return '�����������';
      case VehicleType.truck:
        return '��������';
    }
  }

  String get description {
    switch (this) {
      case VehicleType.light:
        return '�������� ���������� �� 1.8 �';
      case VehicleType.suv:
        return '��������� ��� �����������';
      case VehicleType.minibus:
        return '����������� ��� ��������� ������';
      case VehicleType.truck:
        return '�������� ����������';
    }
  }

  String get assetPath {
    switch (this) {
      case VehicleType.light:
        return EvikAssetPaths.sedan;
      case VehicleType.suv:
        return EvikAssetPaths.crossover;
      case VehicleType.minibus:
      case VehicleType.truck:
        return EvikAssetPaths.minibus;
    }
  }
}
