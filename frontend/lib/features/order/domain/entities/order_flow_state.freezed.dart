// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order_flow_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OrderFlowState _$OrderFlowStateFromJson(Map<String, dynamic> json) {
  return _OrderFlowState.fromJson(json);
}

/// @nodoc
mixin _$OrderFlowState {
  OrderFlowStep get currentStep => throw _privateConstructorUsedError;
  MapLocation? get pickupLocation => throw _privateConstructorUsedError;
  MapLocation? get destinationLocation => throw _privateConstructorUsedError;
  VehicleType? get selectedVehicleType => throw _privateConstructorUsedError;
  TowTruckType? get selectedTowTruckType => throw _privateConstructorUsedError;
  int get blockedWheelsCount => throw _privateConstructorUsedError;
  String get clientComment => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  String? get errorMessage => throw _privateConstructorUsedError;
  @JsonKey(includeFromJson: false, includeToJson: false)
  Order? get activeOrder => throw _privateConstructorUsedError;
  @JsonKey(includeFromJson: false, includeToJson: false)
  Driver? get assignedDriver => throw _privateConstructorUsedError;
  int get searchDurationSeconds => throw _privateConstructorUsedError;
  double get estimatedPrice => throw _privateConstructorUsedError;
  double get distance => throw _privateConstructorUsedError;

  /// Serializes this OrderFlowState to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OrderFlowState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderFlowStateCopyWith<OrderFlowState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderFlowStateCopyWith<$Res> {
  factory $OrderFlowStateCopyWith(
          OrderFlowState value, $Res Function(OrderFlowState) then) =
      _$OrderFlowStateCopyWithImpl<$Res, OrderFlowState>;
  @useResult
  $Res call(
      {OrderFlowStep currentStep,
      MapLocation? pickupLocation,
      MapLocation? destinationLocation,
      VehicleType? selectedVehicleType,
      TowTruckType? selectedTowTruckType,
      int blockedWheelsCount,
      String clientComment,
      bool isLoading,
      String? errorMessage,
      @JsonKey(includeFromJson: false, includeToJson: false) Order? activeOrder,
      @JsonKey(includeFromJson: false, includeToJson: false)
      Driver? assignedDriver,
      int searchDurationSeconds,
      double estimatedPrice,
      double distance});
}

/// @nodoc
class _$OrderFlowStateCopyWithImpl<$Res, $Val extends OrderFlowState>
    implements $OrderFlowStateCopyWith<$Res> {
  _$OrderFlowStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderFlowState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentStep = null,
    Object? pickupLocation = freezed,
    Object? destinationLocation = freezed,
    Object? selectedVehicleType = freezed,
    Object? selectedTowTruckType = freezed,
    Object? blockedWheelsCount = null,
    Object? clientComment = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
    Object? activeOrder = freezed,
    Object? assignedDriver = freezed,
    Object? searchDurationSeconds = null,
    Object? estimatedPrice = null,
    Object? distance = null,
  }) {
    return _then(_value.copyWith(
      currentStep: null == currentStep
          ? _value.currentStep
          : currentStep // ignore: cast_nullable_to_non_nullable
              as OrderFlowStep,
      pickupLocation: freezed == pickupLocation
          ? _value.pickupLocation
          : pickupLocation // ignore: cast_nullable_to_non_nullable
              as MapLocation?,
      destinationLocation: freezed == destinationLocation
          ? _value.destinationLocation
          : destinationLocation // ignore: cast_nullable_to_non_nullable
              as MapLocation?,
      selectedVehicleType: freezed == selectedVehicleType
          ? _value.selectedVehicleType
          : selectedVehicleType // ignore: cast_nullable_to_non_nullable
              as VehicleType?,
      selectedTowTruckType: freezed == selectedTowTruckType
          ? _value.selectedTowTruckType
          : selectedTowTruckType // ignore: cast_nullable_to_non_nullable
              as TowTruckType?,
      blockedWheelsCount: null == blockedWheelsCount
          ? _value.blockedWheelsCount
          : blockedWheelsCount // ignore: cast_nullable_to_non_nullable
              as int,
      clientComment: null == clientComment
          ? _value.clientComment
          : clientComment // ignore: cast_nullable_to_non_nullable
              as String,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      activeOrder: freezed == activeOrder
          ? _value.activeOrder
          : activeOrder // ignore: cast_nullable_to_non_nullable
              as Order?,
      assignedDriver: freezed == assignedDriver
          ? _value.assignedDriver
          : assignedDriver // ignore: cast_nullable_to_non_nullable
              as Driver?,
      searchDurationSeconds: null == searchDurationSeconds
          ? _value.searchDurationSeconds
          : searchDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      estimatedPrice: null == estimatedPrice
          ? _value.estimatedPrice
          : estimatedPrice // ignore: cast_nullable_to_non_nullable
              as double,
      distance: null == distance
          ? _value.distance
          : distance // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderFlowStateImplCopyWith<$Res>
    implements $OrderFlowStateCopyWith<$Res> {
  factory _$$OrderFlowStateImplCopyWith(_$OrderFlowStateImpl value,
          $Res Function(_$OrderFlowStateImpl) then) =
      __$$OrderFlowStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {OrderFlowStep currentStep,
      MapLocation? pickupLocation,
      MapLocation? destinationLocation,
      VehicleType? selectedVehicleType,
      TowTruckType? selectedTowTruckType,
      int blockedWheelsCount,
      String clientComment,
      bool isLoading,
      String? errorMessage,
      @JsonKey(includeFromJson: false, includeToJson: false) Order? activeOrder,
      @JsonKey(includeFromJson: false, includeToJson: false)
      Driver? assignedDriver,
      int searchDurationSeconds,
      double estimatedPrice,
      double distance});
}

/// @nodoc
class __$$OrderFlowStateImplCopyWithImpl<$Res>
    extends _$OrderFlowStateCopyWithImpl<$Res, _$OrderFlowStateImpl>
    implements _$$OrderFlowStateImplCopyWith<$Res> {
  __$$OrderFlowStateImplCopyWithImpl(
      _$OrderFlowStateImpl _value, $Res Function(_$OrderFlowStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderFlowState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentStep = null,
    Object? pickupLocation = freezed,
    Object? destinationLocation = freezed,
    Object? selectedVehicleType = freezed,
    Object? selectedTowTruckType = freezed,
    Object? blockedWheelsCount = null,
    Object? clientComment = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
    Object? activeOrder = freezed,
    Object? assignedDriver = freezed,
    Object? searchDurationSeconds = null,
    Object? estimatedPrice = null,
    Object? distance = null,
  }) {
    return _then(_$OrderFlowStateImpl(
      currentStep: null == currentStep
          ? _value.currentStep
          : currentStep // ignore: cast_nullable_to_non_nullable
              as OrderFlowStep,
      pickupLocation: freezed == pickupLocation
          ? _value.pickupLocation
          : pickupLocation // ignore: cast_nullable_to_non_nullable
              as MapLocation?,
      destinationLocation: freezed == destinationLocation
          ? _value.destinationLocation
          : destinationLocation // ignore: cast_nullable_to_non_nullable
              as MapLocation?,
      selectedVehicleType: freezed == selectedVehicleType
          ? _value.selectedVehicleType
          : selectedVehicleType // ignore: cast_nullable_to_non_nullable
              as VehicleType?,
      selectedTowTruckType: freezed == selectedTowTruckType
          ? _value.selectedTowTruckType
          : selectedTowTruckType // ignore: cast_nullable_to_non_nullable
              as TowTruckType?,
      blockedWheelsCount: null == blockedWheelsCount
          ? _value.blockedWheelsCount
          : blockedWheelsCount // ignore: cast_nullable_to_non_nullable
              as int,
      clientComment: null == clientComment
          ? _value.clientComment
          : clientComment // ignore: cast_nullable_to_non_nullable
              as String,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      activeOrder: freezed == activeOrder
          ? _value.activeOrder
          : activeOrder // ignore: cast_nullable_to_non_nullable
              as Order?,
      assignedDriver: freezed == assignedDriver
          ? _value.assignedDriver
          : assignedDriver // ignore: cast_nullable_to_non_nullable
              as Driver?,
      searchDurationSeconds: null == searchDurationSeconds
          ? _value.searchDurationSeconds
          : searchDurationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      estimatedPrice: null == estimatedPrice
          ? _value.estimatedPrice
          : estimatedPrice // ignore: cast_nullable_to_non_nullable
              as double,
      distance: null == distance
          ? _value.distance
          : distance // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OrderFlowStateImpl implements _OrderFlowState {
  const _$OrderFlowStateImpl(
      {this.currentStep = OrderFlowStep.idle,
      this.pickupLocation,
      this.destinationLocation,
      this.selectedVehicleType,
      this.selectedTowTruckType,
      this.blockedWheelsCount = 0,
      this.clientComment = '',
      this.isLoading = false,
      this.errorMessage,
      @JsonKey(includeFromJson: false, includeToJson: false) this.activeOrder,
      @JsonKey(includeFromJson: false, includeToJson: false)
      this.assignedDriver,
      this.searchDurationSeconds = 0,
      this.estimatedPrice = 0.0,
      this.distance = 0.0});

  factory _$OrderFlowStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$OrderFlowStateImplFromJson(json);

  @override
  @JsonKey()
  final OrderFlowStep currentStep;
  @override
  final MapLocation? pickupLocation;
  @override
  final MapLocation? destinationLocation;
  @override
  final VehicleType? selectedVehicleType;
  @override
  final TowTruckType? selectedTowTruckType;
  @override
  @JsonKey()
  final int blockedWheelsCount;
  @override
  @JsonKey()
  final String clientComment;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  final String? errorMessage;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Order? activeOrder;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Driver? assignedDriver;
  @override
  @JsonKey()
  final int searchDurationSeconds;
  @override
  @JsonKey()
  final double estimatedPrice;
  @override
  @JsonKey()
  final double distance;

  @override
  String toString() {
    return 'OrderFlowState(currentStep: $currentStep, pickupLocation: $pickupLocation, destinationLocation: $destinationLocation, selectedVehicleType: $selectedVehicleType, selectedTowTruckType: $selectedTowTruckType, blockedWheelsCount: $blockedWheelsCount, clientComment: $clientComment, isLoading: $isLoading, errorMessage: $errorMessage, activeOrder: $activeOrder, assignedDriver: $assignedDriver, searchDurationSeconds: $searchDurationSeconds, estimatedPrice: $estimatedPrice, distance: $distance)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderFlowStateImpl &&
            (identical(other.currentStep, currentStep) ||
                other.currentStep == currentStep) &&
            (identical(other.pickupLocation, pickupLocation) ||
                other.pickupLocation == pickupLocation) &&
            (identical(other.destinationLocation, destinationLocation) ||
                other.destinationLocation == destinationLocation) &&
            (identical(other.selectedVehicleType, selectedVehicleType) ||
                other.selectedVehicleType == selectedVehicleType) &&
            (identical(other.selectedTowTruckType, selectedTowTruckType) ||
                other.selectedTowTruckType == selectedTowTruckType) &&
            (identical(other.blockedWheelsCount, blockedWheelsCount) ||
                other.blockedWheelsCount == blockedWheelsCount) &&
            (identical(other.clientComment, clientComment) ||
                other.clientComment == clientComment) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.activeOrder, activeOrder) ||
                other.activeOrder == activeOrder) &&
            (identical(other.assignedDriver, assignedDriver) ||
                other.assignedDriver == assignedDriver) &&
            (identical(other.searchDurationSeconds, searchDurationSeconds) ||
                other.searchDurationSeconds == searchDurationSeconds) &&
            (identical(other.estimatedPrice, estimatedPrice) ||
                other.estimatedPrice == estimatedPrice) &&
            (identical(other.distance, distance) ||
                other.distance == distance));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      currentStep,
      pickupLocation,
      destinationLocation,
      selectedVehicleType,
      selectedTowTruckType,
      blockedWheelsCount,
      clientComment,
      isLoading,
      errorMessage,
      activeOrder,
      assignedDriver,
      searchDurationSeconds,
      estimatedPrice,
      distance);

  /// Create a copy of OrderFlowState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderFlowStateImplCopyWith<_$OrderFlowStateImpl> get copyWith =>
      __$$OrderFlowStateImplCopyWithImpl<_$OrderFlowStateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OrderFlowStateImplToJson(
      this,
    );
  }
}

abstract class _OrderFlowState implements OrderFlowState {
  const factory _OrderFlowState(
      {final OrderFlowStep currentStep,
      final MapLocation? pickupLocation,
      final MapLocation? destinationLocation,
      final VehicleType? selectedVehicleType,
      final TowTruckType? selectedTowTruckType,
      final int blockedWheelsCount,
      final String clientComment,
      final bool isLoading,
      final String? errorMessage,
      @JsonKey(includeFromJson: false, includeToJson: false)
      final Order? activeOrder,
      @JsonKey(includeFromJson: false, includeToJson: false)
      final Driver? assignedDriver,
      final int searchDurationSeconds,
      final double estimatedPrice,
      final double distance}) = _$OrderFlowStateImpl;

  factory _OrderFlowState.fromJson(Map<String, dynamic> json) =
      _$OrderFlowStateImpl.fromJson;

  @override
  OrderFlowStep get currentStep;
  @override
  MapLocation? get pickupLocation;
  @override
  MapLocation? get destinationLocation;
  @override
  VehicleType? get selectedVehicleType;
  @override
  TowTruckType? get selectedTowTruckType;
  @override
  int get blockedWheelsCount;
  @override
  String get clientComment;
  @override
  bool get isLoading;
  @override
  String? get errorMessage;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  Order? get activeOrder;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  Driver? get assignedDriver;
  @override
  int get searchDurationSeconds;
  @override
  double get estimatedPrice;
  @override
  double get distance;

  /// Create a copy of OrderFlowState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderFlowStateImplCopyWith<_$OrderFlowStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
