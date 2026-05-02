import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../map/domain/entities/map_location.dart';
import '../../../map/presentation/widgets/yandex_map_view.dart';
import '../providers/order_flow_provider.dart';

class LocationPickerBody extends ConsumerStatefulWidget {
  const LocationPickerBody({
    super.key,
    required this.title,
    required this.addressLabel,
    required this.initialLocation,
    required this.initialAddress,
    required this.confirmText,
    required this.onLocationConfirmed,
  });

  final String title;
  final String addressLabel;
  final MapLocation? initialLocation;
  final String initialAddress;
  final String confirmText;
  final ValueChanged<MapLocation> onLocationConfirmed;

  @override
  ConsumerState<LocationPickerBody> createState() => _LocationPickerBodyState();
}

class _LocationPickerBodyState extends ConsumerState<LocationPickerBody> {
  static const _fallbackPoint = Point(
    latitude: AppConstants.moscowLat,
    longitude: AppConstants.moscowLng,
  );

  late final TextEditingController _addressController;
  YandexMapController? _controller;
  late Point _selectedPoint;
  late String _selectedAddress;
  bool _isLoading = false;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialLocation == null
        ? _fallbackPoint
        : Point(
            latitude: widget.initialLocation!.latitude,
            longitude: widget.initialLocation!.longitude,
          );
    _selectedAddress =
        widget.initialLocation?.displayAddress ?? widget.initialAddress;
    _addressController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialLocation == null) {
        _detectCurrentLocation();
      } else {
        setState(() => _hasSelection = true);
      }
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _onMapCreated(YandexMapController controller) async {
    _controller = controller;
    await _moveCamera(_selectedPoint, zoom: 16.2, duration: 0.2);
  }

  Future<void> _moveCamera(
    Point point, {
    double zoom = 16.2,
    double duration = 0.45,
  }) async {
    await _controller?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: zoom),
      ),
      animation: MapAnimation(
        type: MapAnimationType.smooth,
        duration: duration,
      ),
    );
  }

  Future<void> _detectCurrentLocation() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final location =
          await ref.read(locationServiceProvider).getCurrentLocation();
      if (!mounted || location == null) return;

      final point = Point(latitude: location.lat, longitude: location.lng);
      setState(() {
        _selectedPoint = point;
        _selectedAddress = location.address;
        _hasSelection = true;
      });
      await _moveCamera(point, zoom: 17);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedPoint = _fallbackPoint;
        _selectedAddress = 'Москва, центр';
        _hasSelection = true;
      });
      await _moveCamera(_fallbackPoint, zoom: 15.5);
      _showError(
          'Не удалось определить геолокацию. Выберите точку на карте или введите адрес.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _addressController.text.trim();
    if (query.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      final location =
          await ref.read(locationServiceProvider).getLocationByAddress(query);
      if (!mounted || location == null) {
        _showError('Адрес не найден. Уточните запрос.');
        return;
      }

      final point = Point(latitude: location.lat, longitude: location.lng);
      setState(() {
        _selectedPoint = point;
        _selectedAddress = location.address;
        _hasSelection = true;
      });
      await _moveCamera(point, zoom: 16.5);
    } catch (_) {
      if (mounted) _showError('Не удалось найти адрес. Попробуйте еще раз.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onCameraChanged(
    CameraPosition cameraPosition,
    CameraUpdateReason reason,
    bool finished,
  ) {
    if (!finished) return;
    final target = cameraPosition.target;
    setState(() {
      _selectedPoint = target;
      _selectedAddress =
          'Точка на карте: ${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)}';
      _hasSelection = true;
    });
  }

  void _confirm() {
    if (!_hasSelection) return;
    widget.onLocationConfirmed(
      MapLocation(
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        address: _selectedAddress,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: EvikColors.errorRed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: EvikColors.gray50,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapKitAwareYandexMap(
              builder: (_) => YandexMap(
                onMapCreated: _onMapCreated,
                onCameraPositionChanged: _onCameraChanged,
                mapType: MapType.vector,
              ),
            ),
          ),
          const Center(
            child: IgnorePointer(child: _PickerPin()),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: _TopPanel(
              title: widget.title,
              controller: _addressController,
              isLoading: _isLoading,
              onBack: () => Navigator.of(context).pop(),
              onSearch: _searchAddress,
              onUseCurrentLocation: _detectCurrentLocation,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 182,
            child: _MapLocationButton(
              isLoading: _isLoading,
              onPressed: _detectCurrentLocation,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: _BottomPanel(
              addressLabel: widget.addressLabel,
              address: _selectedAddress,
              confirmText: widget.confirmText,
              canConfirm: _hasSelection && !_isLoading,
              onConfirm: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel({
    required this.title,
    required this.controller,
    required this.isLoading,
    required this.onBack,
    required this.onSearch,
    required this.onUseCurrentLocation,
  });

  final String title;
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onUseCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.primaryWhite,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.h3.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isLoading ? null : onUseCurrentLocation,
                  icon: const Icon(
                    Icons.my_location_rounded,
                    color: EvikColors.accentOrange,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  hintText: 'Введите адрес',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: isLoading ? null : onSearch,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: EvikColors.gray100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.addressLabel,
    required this.address,
    required this.confirmText,
    required this.canConfirm,
    required this.onConfirm,
  });

  final String addressLabel;
  final String address;
  final String confirmText;
  final bool canConfirm;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              addressLabel,
              style: EvikTypography.bodySmall.copyWith(
                color: EvikColors.gray500,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodyLarge.copyWith(
                color: EvikColors.primaryBlack,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            EvikButton(
              text: confirmText,
              onPressed: canConfirm ? onConfirm : null,
              width: double.infinity,
              variant: canConfirm
                  ? EvikButtonVariant.primary
                  : EvikButtonVariant.ghost,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLocationButton extends StatelessWidget {
  const _MapLocationButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isLoading ? null : onPressed,
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.near_me_rounded,
                  color: EvikColors.accentOrange,
                ),
        ),
      ),
    );
  }
}

class _PickerPin extends StatelessWidget {
  const _PickerPin();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -22),
      child: const Icon(
        Icons.location_pin,
        color: EvikColors.accentOrange,
        size: 48,
        shadows: [
          Shadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
    );
  }
}
