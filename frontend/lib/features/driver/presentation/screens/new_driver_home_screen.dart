import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/performance/rebuild_tracker.dart';

import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/providers/service_area_provider.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/available_order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_work_state.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_stats.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/widgets/driver_debt_banner.dart';

// Provider for driver profile data (reused from profile screen)
final driverProfileProvider = FutureProvider.autoDispose<Driver?>((ref) async {
  final authState = ref.watch(authProvider);
  final driverId = authState.user?.id;

  if (driverId == null) return null;

  final repository = ref.watch(httpDriverRepositoryProvider);
  return await repository.getDriver(driverId);
});

class NewDriverHomeScreen extends ConsumerStatefulWidget {
  const NewDriverHomeScreen({
    super.key,
    this.auditState,
    this.auditNow,
    this.onOpenProfile,
  });

  /// Local-only visual fixture. It is supplied only by the UI-audit catalogue.
  final DriverState? auditState;

  /// Fixed time used only by deterministic UI-audit captures.
  final DateTime? auditNow;

  /// Opens the existing profile tab when this screen is hosted by the shell.
  final VoidCallback? onOpenProfile;

  @override
  ConsumerState<NewDriverHomeScreen> createState() =>
      _NewDriverHomeScreenState();
}

class _DriverHomeDashboard extends StatelessWidget {
  const _DriverHomeDashboard({
    required this.name,
    required this.initial,
    required this.isOnline,
    required this.isLoading,
    required this.stats,
    required this.locationUnavailable,
    required this.outsideServiceArea,
    required this.wallet,
    required this.onOpenProfile,
    required this.onPrimaryAction,
    required this.primaryLabel,
    this.incomingOrder,
    this.offerProgress = 1,
    this.onAcceptOrder,
    this.onDeclineOrder,
    this.auditNow,
  });

  final String name;
  final String initial;
  final bool isOnline;
  final bool isLoading;
  final TodayStats stats;
  final bool locationUnavailable;
  final bool outsideServiceArea;
  final DriverWallet? wallet;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onPrimaryAction;
  final String primaryLabel;
  final AvailableOrder? incomingOrder;
  final double offerProgress;
  final VoidCallback? onAcceptOrder;
  final VoidCallback? onDeclineOrder;
  final DateTime? auditNow;

  String get _greeting {
    final hour = (auditNow ?? DateTime.now()).hour;
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  String _money(double amount) {
    final digits = amount.round().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.add(digits.substring(end >= 3 ? end - 3 : 0, end));
    }
    return '${groups.reversed.join(' ')} ₽';
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final heading = name == 'Водитель' ? _greeting : '$_greeting, $name';
    final state = _stateContent();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Авро',
                          style: EvikTypography.h3.copyWith(
                            color: AvroDriverColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Semantics(
                          button: true,
                          label: 'Открыть профиль',
                          child: InkWell(
                            onTap: onOpenProfile,
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AvroDriverColors.border,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: AvroDriverColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      heading,
                      style: EvikTypography.h2.copyWith(
                        color: AvroDriverColors.textPrimary,
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _LineStatus(isOnline: isOnline),
                    const SizedBox(height: 24),
                    _TodayCard(
                      earnings: _money(stats.earnings),
                      orders: stats.ordersCount,
                      isLoading: isLoading && !isOnline,
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      child: _ReadinessCard(
                        key: ValueKey(state.title),
                        icon: state.icon,
                        accent: state.accent,
                        title: state.title,
                        description: state.description,
                        isOnline: isOnline,
                      ),
                    ),
                    if (incomingOrder != null) ...[
                      const SizedBox(height: 16),
                      _IncomingOrderSheet(
                        order: incomingOrder!,
                        progress: offerProgress,
                        isLoading: isLoading,
                        onAccept: onAcceptOrder!,
                        onDecline: onDeclineOrder!,
                      ),
                    ],
                    if (wallet != null && wallet!.debtBalance > 0) ...[
                      const SizedBox(height: 16),
                      DriverDebtBanner(wallet: wallet!),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(color: AvroDriverColors.background),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _DriverPrimaryActionButton(
                  label: primaryLabel,
                  isLoading: isLoading,
                  onPressed: onPrimaryAction,
                  icon: locationUnavailable
                      ? Icons.location_on_outlined
                      : isOnline
                          ? Icons.power_settings_new_rounded
                          : Icons.play_arrow_rounded,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  _ReadinessContent _stateContent() {
    if (locationUnavailable) {
      return const _ReadinessContent(
        icon: Icons.location_on_outlined,
        accent: AvroDriverColors.warning,
        title: 'Включите геолокацию',
        description:
            'Чтобы получать заказы рядом и показывать клиенту ваш путь',
      );
    }
    if (outsideServiceArea) {
      return const _ReadinessContent(
        icon: Icons.location_off_outlined,
        accent: AvroDriverColors.warning,
        title: 'Сервис пока недоступен',
        description: 'Авро ещё не работает в вашем городе.',
      );
    }
    if (isOnline) {
      return const _ReadinessContent(
        icon: Icons.radar_rounded,
        accent: AvroDriverColors.success,
        title: 'Ищем заказы рядом',
        description: 'Новый заказ появится автоматически',
      );
    }
    return const _ReadinessContent(
      icon: Icons.power_settings_new_rounded,
      accent: AvroDriverColors.grayHint,
      title: 'Готовы принимать заказы?',
      description: 'Выйдите на линию, чтобы получать предложения поблизости',
    );
  }
}

class _ReadinessContent {
  const _ReadinessContent({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
}

class _LineStatus extends StatelessWidget {
  const _LineStatus({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline
                  ? AvroDriverColors.success
                  : AvroDriverColors.grayHint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Вы на линии' : 'Вы не на линии',
            style: EvikTypography.bodyMedium.copyWith(
              color: AvroDriverColors.grayHint,
              fontSize: 14,
              height: 1.43,
            ),
          ),
        ],
      );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.earnings,
    required this.orders,
    required this.isLoading,
  });

  final String earnings;
  final int orders;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AvroDriverColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AvroDriverColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сегодня',
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroDriverColors.grayHint,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                      child: _TodayMetric(
                          value: earnings,
                          label: 'Заработано',
                          isLoading: isLoading)),
                  const VerticalDivider(
                      color: AvroDriverColors.border, width: 33),
                  Expanded(
                      child: _TodayMetric(
                          value: '$orders',
                          label: 'Заказов',
                          isLoading: isLoading)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TodayMetric extends StatelessWidget {
  const _TodayMetric(
      {required this.value, required this.label, required this.isLoading});
  final String value;
  final String label;
  final bool isLoading;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            Container(
                width: 104,
                height: 38,
                decoration: BoxDecoration(
                    color: AvroDriverColors.border,
                    borderRadius: BorderRadius.circular(8)))
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: EvikTypography.h2.copyWith(
                      color: AvroDriverColors.textPrimary,
                      fontSize: 32,
                      height: 1.19,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          const SizedBox(height: 4),
          Text(label,
              style: EvikTypography.bodyMedium.copyWith(
                  color: AvroDriverColors.grayHint,
                  fontSize: 14,
                  height: 1.43)),
        ],
      );
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard(
      {super.key,
      required this.icon,
      required this.accent,
      required this.title,
      required this.description,
      required this.isOnline});
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final bool isOnline;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: AvroDriverColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AvroDriverColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: Text(title,
                    style: EvikTypography.h2.copyWith(
                        color: AvroDriverColors.textPrimary,
                        fontSize: 28,
                        height: 1.21,
                        fontWeight: FontWeight.w600))),
            if (isOnline)
              const Padding(
                  padding: EdgeInsets.only(left: 12), child: _SearchPulse()),
          ]),
          const SizedBox(height: 12),
          Text(description,
              style: EvikTypography.bodyLarge.copyWith(
                  color: AvroDriverColors.grayHint, fontSize: 16, height: 1.5)),
        ]),
      );
}

class _SearchPulse extends StatefulWidget {
  const _SearchPulse();
  @override
  State<_SearchPulse> createState() => _SearchPulseState();
}

class _SearchPulseState extends State<_SearchPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const _PulseDot(opacity: 1);
    }
    return FadeTransition(
        opacity: Tween<double>(begin: .45, end: 1).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
        child: const _PulseDot(opacity: 1));
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.opacity});
  final double opacity;
  @override
  Widget build(BuildContext context) => Opacity(
      opacity: opacity,
      child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
              color: AvroDriverColors.success, shape: BoxShape.circle)));
}

class _DriverPrimaryActionButton extends StatefulWidget {
  const _DriverPrimaryActionButton(
      {required this.label,
      required this.icon,
      required this.isLoading,
      required this.onPressed});
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;
  @override
  State<_DriverPrimaryActionButton> createState() =>
      _DriverPrimaryActionButtonState();
}

class _DriverPrimaryActionButtonState
    extends State<_DriverPrimaryActionButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        child: AnimatedScale(
          scale: _pressed && !MediaQuery.disableAnimationsOf(context) ? .98 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 100),
          child: Listener(
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onPressed,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    backgroundColor: AvroDriverColors.textPrimary,
                    foregroundColor: AvroDriverColors.background,
                    disabledBackgroundColor: AvroDriverColors.border,
                    disabledForegroundColor: AvroDriverColors.grayHint,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    textStyle: EvikTypography.buttonText
                        .copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
                icon: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AvroDriverColors.background))
                    : Icon(widget.icon, size: 20),
                label: Text(widget.label),
              ),
            ),
          ),
        ),
      );
}

class _NewDriverHomeScreenState extends ConsumerState<NewDriverHomeScreen>
    with TickerProviderStateMixin {
  late final _DriverLifecycleObserver _lifecycleObserver;
  AnimationController? _offerAnimationController;
  Animation<double>? _offerProgressAnimation;
  String? _visibleOfferId;
  String? _routePreviewOrderId;
  RoutePreview? _routePreview;
  bool _routePreviewFailed = false;
  double? _currentLat;
  double? _currentLng;
  bool _locationUnavailable = false;
  PermissionResult? _locationPermission;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _DriverLifecycleObserver(
      onChanged: (state) {
        if (!mounted) return;
        if (state == AppLifecycleState.resumed) _initLocation();
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  Future<void> _initLocation() async {
    final permission = await LocationService.requestLocationPermission();

    if (!mounted) return;

    if (permission != PermissionResult.granted) {
      setState(() {
        _locationUnavailable = true;
        _locationPermission = permission;
      });
      return;
    }

    try {
      final pos = await LocationService.getCurrentPositionWithFallback();
      if (mounted) {
        setState(() {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
          _locationUnavailable = false;
          _locationPermission = PermissionResult.granted;
        });
        ref
            .read(serviceAreaProvider.notifier)
            .checkServiceArea(pos.latitude, pos.longitude);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationUnavailable = true;
          _locationPermission = PermissionResult.denied;
        });
      }
    }
  }

  Future<void> _openLocationSettings({required bool serviceDisabled}) async {
    final opened = serviceDisabled
        ? await Geolocator.openLocationSettings()
        : await Geolocator.openAppSettings();
    if (opened || !mounted) return;

    // iOS simulators do not always expose a separate system location page.
    // The app settings page is the supported fallback for its permission.
    if (serviceDisabled && await Geolocator.openAppSettings()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Не удалось открыть настройки. Разрешите геолокацию для Авро в настройках устройства.',
        ),
        backgroundColor: AvroDriverColors.error,
      ),
    );
  }

  @override
  void dispose() {
    _offerAnimationController?.dispose();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    RebuildTracker.trackRebuild('NewDriverHomeScreen');

    final auditState = widget.auditState;
    final providerState = ref.watch(newDriverProvider);
    final displayedState = auditState ?? providerState;
    final workState = displayedState.workState;
    final availableOrders = displayedState.availableOrders;
    final isLoading = displayedState.isLoading;
    final stats = displayedState.stats;
    final driverProfile = ref.watch(driverProfileProvider);
    final serviceArea = ref.watch(serviceAreaProvider);
    final walletState = ref.watch(driverWalletProvider);

    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message), backgroundColor: AvroDriverColors.error),
        );
      }
    });

    // Create minimal state object for methods that need full state
    final driverState = DriverState(
      workState: workState,
      availableOrders: availableOrders,
      isLoading: isLoading,
      stats: stats,
      activeOrder: null,
      error: null,
    );

    return Scaffold(
      backgroundColor: AvroDriverColors.background,
      body: SafeArea(
        child: _buildOfflineView(
          driverState,
          driverProfile,
          serviceArea,
          walletState,
        ),
      ),
    );
  }

  void _syncIncomingOffer(DriverWorkState workState, List availableOrders) {
    if (workState != DriverWorkState.online || availableOrders.isEmpty) {
      _offerAnimationController?.stop();
      _visibleOfferId = null;
      return;
    }

    final incoming = availableOrders.first;
    if (_visibleOfferId == incoming.id) return;

    _offerAnimationController?.dispose();
    _visibleOfferId = incoming.id;

    Duration duration;
    if (incoming.expiresAt != null) {
      final remaining = incoming.expiresAt!.difference(DateTime.now().toUtc());
      duration = remaining > Duration.zero ? remaining : Duration.zero;
    } else {
      duration = const Duration(seconds: 15);
    }

    if (duration == Duration.zero) {
      _visibleOfferId = null;
      return;
    }

    _offerAnimationController = AnimationController(
      duration: duration,
      vsync: this,
    );

    _offerProgressAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _offerAnimationController!,
      curve: Curves.linear,
    ));

    _offerAnimationController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _visibleOfferId = null;
        });
      }
    });

    _offerAnimationController!.forward();
  }

  /// Get driver display name from profile
  String _getDriverDisplayName(AsyncValue<Driver?> driverProfile) {
    return driverProfile.when(
      data: (driver) {
        if (driver?.fullName?.isNotEmpty == true) {
          // Extract first name from full name
          final firstName = driver!.fullName!.split(' ').first;
          return firstName;
        }
        return 'Водитель';
      },
      loading: () => 'Водитель',
      error: (_, __) => 'Водитель',
    );
  }

  /// Get driver initial from profile
  String _getDriverInitial(AsyncValue<Driver?> driverProfile) {
    return driverProfile.when(
      data: (driver) {
        if (driver?.fullName?.isNotEmpty == true) {
          return driver!.fullName!.characters.first.toUpperCase();
        }
        return 'В';
      },
      loading: () => 'В',
      error: (_, __) => 'В',
    );
  }

  Widget _buildOfflineView(
      DriverState driverState,
      AsyncValue<Driver?> driverProfile,
      ServiceAreaState serviceArea,
      DriverWalletState walletState) {
    final outsideServiceArea = serviceArea.isChecked && !serviceArea.isAllowed;
    final canGoOnline = !_locationUnavailable && !outsideServiceArea;
    final isOnline = driverState.workState == DriverWorkState.online;
    _syncIncomingOffer(driverState.workState, driverState.availableOrders);
    final incomingOrder = isOnline && driverState.availableOrders.isNotEmpty
        ? driverState.availableOrders.first
        : null;
    final locationAction = _locationPermission == PermissionResult.deniedForever
        ? 'Открыть настройки'
        : _locationPermission == PermissionResult.serviceDisabled
            ? 'Включить геолокацию'
            : 'Разрешить геолокацию';

    Future<void> handleAction() async {
      if (_locationUnavailable) {
        if (_locationPermission == PermissionResult.deniedForever) {
          await _openLocationSettings(serviceDisabled: false);
          return;
        }
        if (_locationPermission == PermissionResult.serviceDisabled) {
          await _openLocationSettings(serviceDisabled: true);
          return;
        }
        await _initLocation();
        if (!mounted || !_locationUnavailable) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Разрешение не выдано. Откройте настройки и включите геолокацию для Авро.',
            ),
            action: SnackBarAction(
              label: 'Настройки',
              onPressed: () => _openLocationSettings(serviceDisabled: false),
            ),
          ),
        );
        return;
      }
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
      if (isOnline) {
        await ref.read(newDriverProvider.notifier).goOffline();
      } else if (canGoOnline) {
        await ref.read(newDriverProvider.notifier).goOnline(
              lat: _currentLat,
              lng: _currentLng,
            );
      }
    }

    return _DriverHomeDashboard(
      auditNow: widget.auditNow,
      name: _getDriverDisplayName(driverProfile),
      initial: _getDriverInitial(driverProfile),
      isOnline: isOnline,
      isLoading: driverState.isLoading,
      stats: driverState.stats.today,
      locationUnavailable: _locationUnavailable,
      outsideServiceArea: outsideServiceArea,
      wallet: walletState.wallet,
      onOpenProfile: widget.onOpenProfile,
      onPrimaryAction: driverState.isLoading || (!isOnline && !canGoOnline)
          ? (_locationUnavailable ? handleAction : null)
          : handleAction,
      primaryLabel: driverState.isLoading
          ? 'Подключаемся…'
          : _locationUnavailable
              ? locationAction
              : isOnline
                  ? 'Завершить работу'
                  : 'Выйти на линию',
      incomingOrder: incomingOrder,
      offerProgress: _offerProgressAnimation?.value ?? 1,
      onDeclineOrder: incomingOrder == null
          ? null
          : () {
              _offerAnimationController?.stop();
              ref
                  .read(newDriverProvider.notifier)
                  .declineOrder(incomingOrder.id);
            },
      onAcceptOrder: incomingOrder == null
          ? null
          : () {
              _offerAnimationController?.stop();
              ref
                  .read(newDriverProvider.notifier)
                  .acceptOrder(incomingOrder.id);
            },
    );
  }

  // ignore: unused_element
  Widget _buildOnlineView(DriverState driverState,
      AsyncValue<Driver?> driverProfile, ServiceAreaState serviceArea) {
    _syncIncomingOffer(driverState.workState, driverState.availableOrders);
    final incomingOrder = driverState.availableOrders.isEmpty
        ? null
        : driverState.availableOrders.first;
    _syncRoutePreview(incomingOrder);
    const navBottom = 10.0 + 72.0 + 10.0;

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: EvikOsmMapView(
              initialLat: incomingOrder?.pickupLat ?? _currentLat ?? 42.9764,
              initialLng: incomingOrder?.pickupLng ?? _currentLng ?? 47.5024,
              initialZoom: incomingOrder == null ? 12.2 : 13.5,
              markers: _mapMarkers(incomingOrder),
              routePoints: _routePreview?.points ?? const <LatLng>[],
              controlsBottomOffset:
                  10 + 72 + 50 + (incomingOrder == null ? 128 : 330),
              controlsBackgroundColor: AvroDriverColors.surface,
              controlsIconColor: AvroDriverColors.accent,
            ),
          ),
        ),
        if (incomingOrder != null && _routePreviewFailed)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 74,
            child: const _RouteUnavailableBadge(),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          child: _OnlineStatusBar(
            statsText: driverState.stats.today.displayText,
            onGoOffline: driverState.isLoading
                ? null
                : () {
                    try {
                      HapticFeedback.selectionClick();
                    } catch (_) {}
                    ref.read(newDriverProvider.notifier).goOffline();
                  },
          ),
        ),
        if (incomingOrder == null)
          Positioned(
            left: 10,
            right: 10,
            bottom: navBottom,
            child: _WaitingForOrdersCard(isLoading: driverState.isLoading),
          )
        else
          Positioned(
            left: 10,
            right: 10,
            bottom: navBottom,
            child: AnimatedBuilder(
              animation:
                  _offerProgressAnimation ?? const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return _IncomingOrderSheet(
                  order: incomingOrder,
                  progress: _offerProgressAnimation?.value ?? 1.0,
                  isLoading: driverState.isLoading,
                  onDecline: () {
                    try {
                      HapticFeedback.lightImpact();
                    } catch (_) {}
                    _offerAnimationController?.stop();
                    setState(() {
                      _visibleOfferId = null;
                    });
                    ref
                        .read(newDriverProvider.notifier)
                        .declineOrder(incomingOrder.id);
                  },
                  onAccept: () {
                    try {
                      HapticFeedback.heavyImpact();
                    } catch (_) {}
                    _offerAnimationController?.stop();
                    ref
                        .read(newDriverProvider.notifier)
                        .acceptOrder(incomingOrder.id);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  List<EvikMapMarker> _mapMarkers(AvailableOrder? incoming) {
    return [
      EvikMapMarker(
        lat: _currentLat ?? 42.9764,
        lng: _currentLng ?? 47.5024,
        title: 'Вы',
        color: AvroDriverColors.success,
      ),
      if (incoming != null)
        EvikMapMarker(
          lat: incoming.pickupLat,
          lng: incoming.pickupLng,
          title: incoming.pickupAddress,
          color: AvroDriverColors.accent,
        ),
    ];
  }

  void _syncRoutePreview(AvailableOrder? incoming) {
    if (incoming == null) {
      if (_routePreviewOrderId != null) {
        _routePreviewOrderId = null;
        _routePreview = null;
        _routePreviewFailed = false;
      }
      return;
    }
    if (_routePreviewOrderId == incoming.id) return;
    _routePreviewOrderId = incoming.id;
    _routePreview = null;
    _routePreviewFailed = false;
    OpenStreetMapService.getRoutePreview(
      fromLat: _currentLat ?? 42.9764,
      fromLng: _currentLng ?? 47.5024,
      toLat: incoming.pickupLat,
      toLng: incoming.pickupLng,
    ).then((preview) {
      if (!mounted || _routePreviewOrderId != incoming.id) return;
      setState(() {
        _routePreview = preview;
        _routePreviewFailed = preview == null;
      });
    });
  }
}

class _RouteUnavailableBadge extends StatelessWidget {
  const _RouteUnavailableBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AvroDriverColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AvroDriverColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.route_outlined,
                size: 18,
                color: AvroDriverColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Маршрут недоступен',
                style: EvikTypography.bodySmall.copyWith(
                  color: AvroDriverColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _DriverServiceAreaBanner extends StatelessWidget {
  const _DriverServiceAreaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AvroDriverColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AvroDriverColors.background,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Авро пока не работает в вашем городе. Мы скоро появимся!',
              style: EvikTypography.bodySmall.copyWith(
                color: AvroDriverColors.background,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _LocationUnavailableBanner extends StatelessWidget {
  const _LocationUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AvroDriverColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_off_rounded,
            size: 20,
            color: AvroDriverColors.background,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Местоположение недоступно. Разрешите геолокацию в настройках.',
              style: EvikTypography.bodySmall.copyWith(
                color: AvroDriverColors.background,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineStatusBar extends StatelessWidget {
  const _OnlineStatusBar({required this.statsText, required this.onGoOffline});

  final String statsText;
  final VoidCallback? onGoOffline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AvroDriverColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'В сети',
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroDriverColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statsText,
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 52,
              height: 40,
              child: Switch.adaptive(
                value: true,
                onChanged: onGoOffline == null
                    ? null
                    : (value) {
                        if (!value) onGoOffline!();
                      },
                activeThumbColor: AvroDriverColors.surface,
                activeTrackColor: AvroDriverColors.success,
                inactiveThumbColor: AvroDriverColors.surface,
                inactiveTrackColor: AvroDriverColors.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingForOrdersCard extends StatelessWidget {
  const _WaitingForOrdersCard({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: isLoading
                  ? const CircularProgressIndicator(strokeWidth: 3)
                  : const Icon(
                      Icons.radar_rounded,
                      color: AvroDriverColors.accent,
                      size: 30,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ищем заказы рядом',
                    style: EvikTypography.bodyLarge.copyWith(
                      color: AvroDriverColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Оставайтесь на линии, заказ появится автоматически',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingOrderSheet extends StatelessWidget {
  const _IncomingOrderSheet({
    required this.order,
    required this.progress,
    required this.isLoading,
    required this.onDecline,
    required this.onAccept,
  });

  final AvailableOrder order;
  final double progress;
  final bool isLoading;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 28 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Material(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Новый заказ рядом',
                          style: EvikTypography.h3.copyWith(
                              fontSize: 19,
                              color: AvroDriverColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${order.distanceKm.toStringAsFixed(1)} км до клиента · ${order.estimatedMinutes} мин',
                          style: EvikTypography.bodySmall.copyWith(
                            color: AvroDriverColors.grayHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${order.price.toInt()} ₽',
                    style: EvikTypography.price.copyWith(
                        fontSize: 21, color: AvroDriverColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AvroDriverColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AvroDriverColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.directions_car_rounded,
                    label: order.vehicleDisplayName,
                  ),
                  _InfoPill(
                    icon: Icons.build_rounded,
                    label: order.problemType,
                  ),
                  _InfoPill(
                    icon: Icons.motion_photos_off_rounded,
                    label: 'Колеса: ${order.blockedWheelsCount}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AvroDriverColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AvroDriverColors.border),
                ),
                child: Column(
                  children: [
                    _AddressLine(
                      color: AvroDriverColors.accent,
                      label: 'К клиенту',
                      value: order.pickupAddress,
                    ),
                    const SizedBox(height: 8),
                    _AddressLine(
                      color: AvroDriverColors.grayHint,
                      label: 'Доставка',
                      value: order.dropoffAddress,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: _OrderActionButton(
                      text: 'Отклонить',
                      onPressed: isLoading ? null : onDecline,
                      backgroundColor: AvroDriverColors.surface,
                      foregroundColor: AvroDriverColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OrderActionButton(
                      text: 'Принять',
                      onPressed: isLoading ? null : onAccept,
                      isLoading: isLoading,
                      backgroundColor: AvroDriverColors.success,
                      foregroundColor: AvroDriverColors.surface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderActionButton extends StatelessWidget {
  const _OrderActionButton({
    required this.text,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          foregroundColor: foregroundColor,
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.8),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: EvikTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text, maxLines: 1),
              ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AvroDriverColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: EvikTypography.bodySmall.copyWith(
              color: AvroDriverColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: EvikTypography.sectionLabel
                      .copyWith(color: AvroDriverColors.grayHint)),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyMedium.copyWith(
                  color: AvroDriverColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverLifecycleObserver extends WidgetsBindingObserver {
  _DriverLifecycleObserver({required this.onChanged});

  final ValueChanged<AppLifecycleState> onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state);
  }
}

// ignore: unused_element
class _BackgroundOptimizer extends StatelessWidget {
  const _BackgroundOptimizer({
    required this.child,
    required this.isDriverWaiting,
    required this.isAppInForeground,
  });

  final Widget child;
  final bool isDriverWaiting;
  final bool isAppInForeground;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: !isDriverWaiting || isAppInForeground,
      child: Visibility(
        visible: !isDriverWaiting || isAppInForeground,
        maintainState: true,
        maintainAnimation: false,
        maintainSize: false,
        child: child,
      ),
    );
  }
}
