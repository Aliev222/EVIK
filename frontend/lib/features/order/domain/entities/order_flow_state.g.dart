// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_flow_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OrderFlowStateImpl _$$OrderFlowStateImplFromJson(Map<String, dynamic> json) =>
    _$OrderFlowStateImpl(
      currentStep:
          $enumDecodeNullable(_$OrderFlowStepEnumMap, json['currentStep']) ??
              OrderFlowStep.idle,
      pickupLocation: json['pickupLocation'] == null
          ? null
          : MapLocation.fromJson(
              json['pickupLocation'] as Map<String, dynamic>),
      destinationLocation: json['destinationLocation'] == null
          ? null
          : MapLocation.fromJson(
              json['destinationLocation'] as Map<String, dynamic>),
      selectedVehicleType: $enumDecodeNullable(
          _$VehicleTypeEnumMap, json['selectedVehicleType']),
      selectedTowTruckType: $enumDecodeNullable(
          _$TowTruckTypeEnumMap, json['selectedTowTruckType']),
      blockedWheelsCount: (json['blockedWheelsCount'] as num?)?.toInt() ?? 0,
      clientComment: json['clientComment'] as String? ?? '',
      isLoading: json['isLoading'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      idempotencyKey: json['idempotencyKey'] as String?,
      selectedPaymentMethod: $enumDecodeNullable(
              _$PaymentMethodEnumMap, json['selectedPaymentMethod']) ??
          PaymentMethod.cash,
      isPaymentProcessing: json['isPaymentProcessing'] as bool? ?? false,
      isReceiptLoading: json['isReceiptLoading'] as bool? ?? false,
      receiptError: json['receiptError'] as String?,
      searchDurationSeconds:
          (json['searchDurationSeconds'] as num?)?.toInt() ?? 0,
      estimatedPrice: (json['estimatedPrice'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      isPriceLoading: json['isPriceLoading'] as bool? ?? false,
      isPriceUnavailable: json['isPriceUnavailable'] as bool? ?? false,
    );

Map<String, dynamic> _$$OrderFlowStateImplToJson(
        _$OrderFlowStateImpl instance) =>
    <String, dynamic>{
      'currentStep': _$OrderFlowStepEnumMap[instance.currentStep]!,
      'pickupLocation': instance.pickupLocation,
      'destinationLocation': instance.destinationLocation,
      'selectedVehicleType': _$VehicleTypeEnumMap[instance.selectedVehicleType],
      'selectedTowTruckType':
          _$TowTruckTypeEnumMap[instance.selectedTowTruckType],
      'blockedWheelsCount': instance.blockedWheelsCount,
      'clientComment': instance.clientComment,
      'isLoading': instance.isLoading,
      'errorMessage': instance.errorMessage,
      'idempotencyKey': instance.idempotencyKey,
      'selectedPaymentMethod':
          _$PaymentMethodEnumMap[instance.selectedPaymentMethod]!,
      'isPaymentProcessing': instance.isPaymentProcessing,
      'isReceiptLoading': instance.isReceiptLoading,
      'receiptError': instance.receiptError,
      'searchDurationSeconds': instance.searchDurationSeconds,
      'estimatedPrice': instance.estimatedPrice,
      'distance': instance.distance,
      'isPriceLoading': instance.isPriceLoading,
      'isPriceUnavailable': instance.isPriceUnavailable,
    };

const _$OrderFlowStepEnumMap = {
  OrderFlowStep.idle: 'idle',
  OrderFlowStep.pickupSelection: 'pickupSelection',
  OrderFlowStep.destinationSelection: 'destinationSelection',
  OrderFlowStep.vehicleSelection: 'vehicleSelection',
  OrderFlowStep.towTruckSelection: 'towTruckSelection',
  OrderFlowStep.driverSearch: 'driverSearch',
  OrderFlowStep.driverFound: 'driverFound',
  OrderFlowStep.tracking: 'tracking',
  OrderFlowStep.paymentConfirmation: 'paymentConfirmation',
  OrderFlowStep.completion: 'completion',
  OrderFlowStep.rating: 'rating',
};

const _$VehicleTypeEnumMap = {
  VehicleType.light: 'light',
  VehicleType.suv: 'suv',
  VehicleType.minibus: 'minibus',
  VehicleType.truck: 'truck',
};

const _$TowTruckTypeEnumMap = {
  TowTruckType.winch: 'winch',
  TowTruckType.platform: 'platform',
  TowTruckType.manipulator: 'manipulator',
};

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.card: 'card',
};
