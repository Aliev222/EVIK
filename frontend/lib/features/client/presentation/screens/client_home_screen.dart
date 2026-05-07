import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../auth/presentation/providers/new_auth_provider.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/repositories/order_repository.dart';
import '../../../order/presentation/providers/order_provider.dart';
import '../../../order/presentation/providers/realtime_order_provider.dart';
import '../../../map/presentation/widgets/promaps_view_simple.dart';
import '../widgets/live_driver_map.dart';

enum OrderCreationState {
  addressInput,
  searchingDrivers,
  driverFound,
  noDriversFound,
}

enum _ClientHomeFlowState {
  idle,
  evacuating,
  completed,
}

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  static const LocationModel _moscowLocation =
      LocationModel(lat: 55.7558, lng: 37.6176, address: 'Москва');

  LocationModel _userLocation = _moscowLocation;
  _ClientHomeFlowState _flowState = _ClientHomeFlowState.idle;
  OrderCreationState _orderState = OrderCreationState.addressInput;
  Timer? _searchTimer;
  String? _pickupAddress;
  String? _dropoffAddress;
  bool _notificationRequested = false;
  int _arrivalMinutes = 12;

  static const Map<String, String> _mockDriver = {
    'name': 'Михаил Соколов',
    'rating': '4.8',
    'totalOrders': '156',
    'carNumber': 'А 123 КО 77',
    'phone': '+7 (916) 234-56-78',
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _moveToCurrentLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await Geolocator.isLocationServiceEnabled()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Включите геолокацию на устройстве.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Нет доступа к геопозиции. Используется Москва по умолчанию.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;

      setState(() {
        _userLocation = LocationModel(
          lat: position.latitude,
          lng: position.longitude,
          address: 'Текущее местоположение',
        );
      });
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Не удалось определить местоположение. Попробуйте еще раз.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
    }
  }

  Future<void> _startOrderFlow() async {
    final pickup = await Navigator.of(context).push<_SelectedLocation>(
      MaterialPageRoute(
        builder: (_) => _LocationSelectScreen(initialPoint: _userLocation),
      ),
    );
    if (pickup == null || !mounted) return;

    final draft = await Navigator.of(context).push<_OrderDraft>(
      MaterialPageRoute(
        builder: (_) => _OrderFormScreen(pickupAddress: pickup.address),
      ),
    );
    if (draft == null || !mounted) return;

    setState(() {
      _userLocation = pickup.location;
      _pickupAddress = pickup.address;
      _dropoffAddress = draft.dropoffAddress;
    });
    await _createBackendOrder(pickup, draft);
  }

  Future<void> _createBackendOrder(
    _SelectedLocation pickup,
    _OrderDraft draft,
  ) async {
    final user = ref.read(currentUserProviderNew);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите в аккаунт, чтобы создать заказ.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
      return;
    }

    final dropoffLocation = LocationModel(
      lat: pickup.location.lat - 0.025,
      lng: pickup.location.lng + 0.0091,
      address: draft.dropoffAddress,
    );

    // Используем НОВЫЙ real-time сервис вместо старого HTTP API
    await ref.read(realTimeOrderProvider.notifier).createRealTimeOrder(
      clientId: user.id,
      pickupLocation: pickup.location,
      dropoffLocation: dropoffLocation,
      vehicleType: draft.vehicleType,
      notes: draft.reason,
    );

    final orderState = ref.read(realTimeOrderProvider);
    orderState.when(
      data: (orderId) {
        if (orderId != null) {
          _startDriverSearch();
        }
      },
      loading: () {},
      error: (error, _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString()), backgroundColor: EvikColors.errorRed),
          );
        }
      },
    );
  }

  void _goToEvacuating() =>
      setState(() => _flowState = _ClientHomeFlowState.evacuating);
  void _goToCompleted() =>
      setState(() => _flowState = _ClientHomeFlowState.completed);
  void _resetToIdle() {
    _searchTimer?.cancel();
    setState(() {
      _flowState = _ClientHomeFlowState.idle;
      _orderState = OrderCreationState.addressInput;
    });
  }

  void _startDriverSearch() {
    _searchTimer?.cancel();
    setState(() {
      _orderState = OrderCreationState.searchingDrivers;
      _notificationRequested = false;
    });

    _searchTimer = Timer(Duration(seconds: 3 + Random().nextInt(3)), () {
      final found = Random().nextDouble() < 0.7;
      if (!mounted) return;
      setState(() {
        _arrivalMinutes = Random().nextInt(20) + 5;
        _orderState = found
            ? OrderCreationState.driverFound
            : OrderCreationState.noDriversFound;
      });
    });
  }

  void _cancelSearch() {
    _searchTimer?.cancel();
    setState(() => _orderState = OrderCreationState.addressInput);
  }

  void _retrySearch() => _startDriverSearch();

  void _callDriver() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Звонок: ${_mockDriver['phone']}')),
    );
  }

  void _requestDriverNotification() {
    setState(() => _notificationRequested = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Мы сообщим когда появится водитель'),
        backgroundColor: EvikColors.accentOrange,
      ),
    );
  }

  Widget _buildMapWidget() {
    if (_flowState == _ClientHomeFlowState.evacuating) {
      // Show live driver tracking during evacuation
      final currentOrder = ref.watch(orderProvider).currentOrder;
      if (currentOrder != null) {
        return LiveDriverMap(
          order: currentOrder,
          pickupLocation: _userLocation,
          height: double.infinity,
        );
      }
    }

    // Default ProMaps view for idle state
    return ProMapsViewSimple(
      initialLat: _userLocation.lat,
      initialLng: _userLocation.lng,
      initialZoom: 15,
      markers: [
        ProMapMarker(
          lat: _userLocation.lat,
          lng: _userLocation.lng,
          title: 'Ваше местоположение',
          color: Colors.orange,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_flowState == _ClientHomeFlowState.completed) {
      return _CompletedScreen(onReset: _resetToIdle);
    }

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildMapWidget(),
          ),
          if (_flowState == _ClientHomeFlowState.idle) ...[
            const Positioned(left: 0, right: 0, top: 0, child: _MapHeader()),
            Positioned(
              right: 12,
              top: 58,
              child: _OrderStateDebugActions(
                onSearch: _startDriverSearch,
                onFound: () => setState(
                  () => _orderState = OrderCreationState.driverFound,
                ),
                onNotFound: () => setState(
                  () => _orderState = OrderCreationState.noDriversFound,
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: _orderState == OrderCreationState.addressInput ? 188 : 92,
              child: _NavigationButton(onPressed: _moveToCurrentLocation),
            ),
            if (_orderState != OrderCreationState.addressInput)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _orderState == OrderCreationState.searchingDrivers
                      ? 1
                      : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              ),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: _buildOrderStateOverlay(),
              ),
            ),
          ],
          if (_flowState == _ClientHomeFlowState.evacuating)
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: _EvacuatingCard(onTrackPressed: _goToCompleted),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderStateOverlay() {
    switch (_orderState) {
      case OrderCreationState.addressInput:
        return Align(
          key: const ValueKey(OrderCreationState.addressInput),
          alignment: Alignment.bottomCenter,
          child: _IdleCta(
            pickupAddress: _pickupAddress,
            dropoffAddress: _dropoffAddress,
            onSelectAddresses: _startOrderFlow,
            onStartSearch: _startDriverSearch,
          ),
        );
      case OrderCreationState.searchingDrivers:
        return Center(
          key: const ValueKey(OrderCreationState.searchingDrivers),
          child: _DismissibleStateCard(
            onDismiss: _cancelSearch,
            child: _SearchingDriversCard(onCancel: _cancelSearch),
          ),
        );
      case OrderCreationState.driverFound:
        return Align(
          key: const ValueKey(OrderCreationState.driverFound),
          alignment: Alignment.bottomCenter,
          child: _DismissibleStateCard(
            onDismiss: _cancelSearch,
            child: _DriverFoundSheet(
              driver: _mockDriver,
              arrivalMinutes: _arrivalMinutes,
              onCall: _callDriver,
              onCancel: _cancelSearch,
              onNext: _goToEvacuating,
            ),
          ),
        );
      case OrderCreationState.noDriversFound:
        return Align(
          key: const ValueKey(OrderCreationState.noDriversFound),
          alignment: Alignment.bottomCenter,
          child: _DismissibleStateCard(
            onDismiss: _cancelSearch,
            child: _NoDriversFoundSheet(
              notificationRequested: _notificationRequested,
              onRetry: _retrySearch,
              onNotify: _requestDriverNotification,
            ),
          ),
        );
    }
  }
}

class _MapHeader extends StatelessWidget {
  const _MapHeader();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: EvikColors.primaryWhite,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: EvikColors.accentOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text('Москва, ЦАО',
                        style: EvikTypography.bodyMedium.copyWith(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: EvikColors.primaryBlack,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text('?',
                    style: EvikTypography.bodyMedium.copyWith(
                        color: EvikColors.primaryWhite,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: const Icon(Icons.navigation_rounded,
              color: EvikColors.accentOrange),
        ),
      ),
    );
  }
}

class _IdleCta extends StatelessWidget {
  const _IdleCta({
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.onSelectAddresses,
    required this.onStartSearch,
  });

  final String? pickupAddress;
  final String? dropoffAddress;
  final VoidCallback onSelectAddresses;
  final VoidCallback onStartSearch;

  bool get _canOrder =>
      pickupAddress?.trim().isNotEmpty == true &&
      dropoffAddress?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            EvikColors.primaryWhite.withValues(alpha: 0.0),
            EvikColors.primaryWhite.withValues(alpha: 0.75),
            EvikColors.primaryWhite,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AddressInputRow(
                  icon: Icons.trip_origin,
                  color: EvikColors.accentOrange,
                  placeholder: 'Откуда забрать?',
                  value: pickupAddress,
                  onTap: onSelectAddresses,
                ),
                const SizedBox(height: 10),
                _AddressInputRow(
                  icon: Icons.place_outlined,
                  color: EvikColors.primaryBlack,
                  placeholder: 'Куда доставить?',
                  value: dropoffAddress,
                  onTap: onSelectAddresses,
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        color: EvikColors.accentOrange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '~1500-2000 ?',
                        style: EvikTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.schedule,
                          color: EvikColors.gray500, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '≈ 25 минут',
                        style: EvikTypography.bodyMedium.copyWith(
                          color: EvikColors.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                EvikButton(
                  text: 'Заказать эвакуатор',
                  onPressed: _canOrder ? onStartSearch : null,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressInputRow extends StatelessWidget {
  const _AddressInputRow({
    required this.icon,
    required this.color,
    required this.placeholder,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String placeholder;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.trim().isNotEmpty == true;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: EvikColors.gray50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EvikColors.gray200),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showChrome = constraints.maxWidth >= 92;
            return Row(
              children: [
                if (showChrome) ...[
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.bodyLarge.copyWith(
                      color: hasValue
                          ? EvikColors.primaryBlack
                          : EvikColors.gray500,
                      fontWeight: hasValue ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (showChrome)
                  const Icon(Icons.chevron_right, color: EvikColors.gray400),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DismissibleStateCard extends StatelessWidget {
  const _DismissibleStateCard({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) onDismiss();
      },
      child: child,
    );
  }
}

class _SearchingDriversCard extends StatelessWidget {
  const _SearchingDriversCard({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: EvikColors.accentOrange),
            const SizedBox(height: 24),
            Text(
              'Ищем водителя',
              style: EvikTypography.h3.copyWith(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Это может занять до 2 минут',
              style:
                  EvikTypography.bodyMedium.copyWith(color: EvikColors.gray600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: EvikColors.errorRed,
                  side: const BorderSide(color: EvikColors.errorRed),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Отменить поиск',
                  style: EvikTypography.buttonText
                      .copyWith(color: EvikColors.errorRed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverFoundSheet extends StatelessWidget {
  const _DriverFoundSheet({
    required this.driver,
    required this.arrivalMinutes,
    required this.onCall,
    required this.onCancel,
    required this.onNext,
  });

  final Map<String, String> driver;
  final int arrivalMinutes;
  final VoidCallback onCall;
  final VoidCallback onCancel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _StateBottomSheet(
      minHeight: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Водитель найден',
                  style: EvikTypography.h3.copyWith(fontSize: 20)),
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: EvikColors.successGreen),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: EvikColors.gray100,
                child: Text(
                  driver['name']!.characters.first,
                  style: EvikTypography.h3.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver['name']!, style: EvikTypography.h3),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '? ${driver['rating']}',
                            style: const TextStyle(
                              color: EvikColors.accentOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' ? ${driver['totalOrders']} заказов',
                            style: const TextStyle(color: EvikColors.gray500),
                          ),
                        ],
                      ),
                      style: EvikTypography.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(driver['carNumber']!,
                        style: EvikTypography.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.schedule, color: EvikColors.successGreen),
              const SizedBox(width: 8),
              Text(
                'Будет через $arrivalMinutes минут',
                style: EvikTypography.bodyLarge
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Позвонить водителю'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EvikColors.infoBlue,
                    side: const BorderSide(color: EvikColors.infoBlue),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onCancel,
                child: Text(
                  'Отменить заказ',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.errorRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onNext,
            child: Text(
              'Тест: перейти к эвакуации',
              style: EvikTypography.bodySmall
                  .copyWith(color: EvikColors.accentOrange),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoDriversFoundSheet extends StatelessWidget {
  const _NoDriversFoundSheet({
    required this.notificationRequested,
    required this.onRetry,
    required this.onNotify,
  });

  final bool notificationRequested;
  final VoidCallback onRetry;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    return _StateBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: EvikColors.warningAmber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sentiment_dissatisfied_outlined,
              color: EvikColors.warningAmber,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Водители не найдены',
            style: EvikTypography.h3.copyWith(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'В данный момент все водители заняты',
            style:
                EvikTypography.bodyMedium.copyWith(color: EvikColors.gray500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          EvikButton(
              text: 'Попробовать снова',
              onPressed: onRetry,
              width: double.infinity),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: notificationRequested ? null : onNotify,
              style: OutlinedButton.styleFrom(
                foregroundColor: EvikColors.gray700,
                side: const BorderSide(color: EvikColors.gray300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                notificationRequested
                    ? 'Уведомление включено'
                    : 'Уведомить когда появится',
                style: EvikTypography.buttonTextSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBottomSheet extends StatelessWidget {
  const _StateBottomSheet({required this.child, this.minHeight});

  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _OrderStateDebugActions extends StatelessWidget {
  const _OrderStateDebugActions({
    required this.onSearch,
    required this.onFound,
    required this.onNotFound,
  });

  final VoidCallback onSearch;
  final VoidCallback onFound;
  final VoidCallback onNotFound;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DebugIconButton(icon: Icons.search, onPressed: onSearch),
        _DebugIconButton(icon: Icons.person, onPressed: onFound),
        _DebugIconButton(icon: Icons.error_outline, onPressed: onNotFound),
      ],
    );
  }
}

class _DebugIconButton extends StatelessWidget {
  const _DebugIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, color: EvikColors.accentOrange, size: 18),
      ),
    );
  }
}

class _EvacuatingCard extends StatelessWidget {
  const _EvacuatingCard({required this.onTrackPressed});
  final VoidCallback onTrackPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Везет ваш автомобиль',
                style: EvikTypography.h3.copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text('Доставка через 25 мин',
                style: EvikTypography.bodyLarge
                    .copyWith(color: EvikColors.accentOrange)),
            const SizedBox(height: 10),
            const LinearProgressIndicator(
                value: 0.58,
                minHeight: 4,
                color: EvikColors.accentOrange,
                backgroundColor: EvikColors.gray200),
            const SizedBox(height: 12),
            EvikButton(
                text: 'Отследить',
                onPressed: onTrackPressed,
                width: double.infinity,
                variant: EvikButtonVariant.ghost),
          ],
        ),
      ),
    );
  }
}

class _CompletedScreen extends StatelessWidget {
  const _CompletedScreen({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.check_circle,
                  color: Color(0xFF10B981), size: 72),
              const SizedBox(height: 12),
              Text('Заказ завершен', style: EvikTypography.h2),
              const SizedBox(height: 16),
              EvikButton(
                text: 'Заказать еще раз',
                onPressed: onReset,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedLocation {
  const _SelectedLocation({
    required this.location,
    required this.address,
  });

  final LocationModel location;
  final String address;
}

class _LocationSelectScreen extends StatefulWidget {
  const _LocationSelectScreen({required this.initialPoint});
  final LocationModel initialPoint;

  @override
  State<_LocationSelectScreen> createState() => _LocationSelectScreenState();
}

class _LocationSelectScreenState extends State<_LocationSelectScreen> {
  late LocationModel _selectedLocation;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialPoint;
    _addressController = TextEditingController(text: 'Текущее местоположение');
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _moveToCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _selectedLocation = LocationModel(
          lat: position.latitude,
          lng: position.longitude,
          address: 'Текущее местоположение',
        );
      });
    } catch (_) {}
  }

  void _confirm() {
    final address = _addressController.text.trim();
    Navigator.of(context).pop(
      _SelectedLocation(
        location: _selectedLocation,
        address: address.isEmpty ? 'Точка на карте' : address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text('Выберите место', style: EvikTypography.h3),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3EC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: EvikColors.accentOrange.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: EvikColors.accentOrange),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Где стоит ваш автомобиль?',
                          style: EvikTypography.bodyLarge
                              .copyWith(fontWeight: FontWeight.w700))),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ProMapsViewSimple(
                    initialLat: _selectedLocation.lat,
                    initialLng: _selectedLocation.lng,
                    initialZoom: 16,
                    markers: [
                      ProMapMarker(
                        lat: _selectedLocation.lat,
                        lng: _selectedLocation.lng,
                        title: 'Выбранное место',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),
                const Center(
                  child: IgnorePointer(
                    child: _Crosshair(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_on_outlined,
                          color: EvikColors.accentOrange),
                      suffixIcon: IconButton(
                        onPressed: _moveToCurrentLocation,
                        icon: const Icon(Icons.my_location,
                            color: EvikColors.gray500),
                      ),
                      hintText: 'Введите адрес вручную',
                      filled: true,
                      fillColor: EvikColors.gray100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: EvikColors.gray200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: EvikColors.gray200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  EvikButton(
                    text: 'Подтвердить место',
                    onPressed: _confirm,
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(width: 56, height: 2, color: EvikColors.accentOrange),
        Container(width: 2, height: 56, color: EvikColors.accentOrange),
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: EvikColors.accentOrange),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: EvikColors.primaryWhite),
        ),
      ],
    );
  }
}

class _OrderDraft {
  const _OrderDraft({
    required this.vehicleType,
    required this.paymentMethod,
    required this.reason,
    required this.dropoffAddress,
  });

  final VehicleType vehicleType;
  final PaymentMethod paymentMethod;
  final String reason;
  final String dropoffAddress;
}

class _OrderFormScreen extends StatefulWidget {
  const _OrderFormScreen({required this.pickupAddress});
  final String pickupAddress;

  @override
  State<_OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<_OrderFormScreen> {
  int _vehicle = 0;
  int _reason = 0;
  int _payment = 0;
  late final TextEditingController _dropoffController;

  @override
  void initState() {
    super.initState();
    _dropoffController = TextEditingController();
  }

  @override
  void dispose() {
    _dropoffController.dispose();
    super.dispose();
  }

  void _submit() {
    final dropoff = _dropoffController.text.trim();
    if (dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите адрес СТО или стоянки.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
      return;
    }

    const vehicleMap = <VehicleType>[
      VehicleType.light,
      VehicleType.suv,
      VehicleType.truck,
    ];
    const reasonMap = <String>[
      'Не заводится',
      'ДТП',
      'Прокол колеса',
      'Другое'
    ];
    const paymentMap = <PaymentMethod>[PaymentMethod.card, PaymentMethod.cash];

    Navigator.of(context).pop(
      _OrderDraft(
        vehicleType: vehicleMap[_vehicle],
        paymentMethod: paymentMap[_payment],
        reason: reasonMap[_reason],
        dropoffAddress: dropoff,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const vehicles = <String>['Легковой', 'Внедорожник', 'Грузовой'];
    const emojis = <String>['🚘', '🚙', '🚚'];
    const reasons = <String>['Не заводится', 'ДТП', 'Прокол колеса', 'Другое'];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text('Оформить заказ', style: EvikTypography.h3),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: EvikColors.gray100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _routeRow('ОТКУДА', widget.pickupAddress,
                              EvikColors.accentOrange),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _dropoffController,
                            decoration: InputDecoration(
                              labelText: 'КУДА',
                              labelStyle: EvikTypography.sectionLabel,
                              hintText: 'Введите адрес СТО или стоянки',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: EvikTypography.bodyLarge
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('ТИП АВТОМОБИЛЯ', style: EvikTypography.sectionLabel),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(vehicles.length, (index) {
                        final selected = index == _vehicle;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: index < vehicles.length - 1 ? 8 : 0),
                            child: GestureDetector(
                              onTap: () => setState(() => _vehicle = index),
                              child: Container(
                                height: 92,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? EvikColors.accentOrange
                                          .withValues(alpha: 0.08)
                                      : EvikColors.primaryWhite,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: selected
                                          ? EvikColors.accentOrange
                                          : EvikColors.gray200,
                                      width: 2),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(emojis[index],
                                        style: const TextStyle(fontSize: 20)),
                                    const SizedBox(height: 8),
                                    Text(vehicles[index],
                                        style: EvikTypography.bodyMedium
                                            .copyWith(
                                                fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 14),
                    Text('ПРИЧИНА ВЫЗОВА', style: EvikTypography.sectionLabel),
                    const SizedBox(height: 8),
                    ...List.generate(reasons.length, (index) {
                      final selected = index == _reason;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _reason = index),
                          child: Container(
                            width: double.infinity,
                            height: 54,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: EvikColors.primaryWhite,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: selected
                                      ? EvikColors.accentOrange
                                      : EvikColors.gray200,
                                  width: 2),
                            ),
                            child: Text(reasons[index],
                                style:
                                    EvikTypography.h3.copyWith(fontSize: 17)),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text('ОПЛАТА', style: EvikTypography.sectionLabel),
                    Row(
                      children: [
                        Expanded(
                          child: _paymentChip(
                            label: 'Карта',
                            icon: Icons.credit_card,
                            selected: _payment == 0,
                            onTap: () => setState(() => _payment = 0),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _paymentChip(
                            label: 'Наличные',
                            icon: Icons.attach_money,
                            selected: _payment == 1,
                            onTap: () => setState(() => _payment = 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: SafeArea(
                top: false,
                child: EvikButton(
                  text: 'Заказать эвакуатор',
                  onPressed: _submit,
                  width: double.infinity,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(String label, String text, Color dotColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: EvikTypography.sectionLabel),
              const SizedBox(height: 4),
              Text(text,
                  style: EvikTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? EvikColors.accentOrange : EvikColors.gray200,
              width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? EvikColors.accentOrange : EvikColors.gray500),
            const SizedBox(width: 6),
            Text(
              label,
              style: EvikTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? EvikColors.accentOrange : EvikColors.gray800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
