import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';

class OsmLocationPicker extends ConsumerStatefulWidget {
  const OsmLocationPicker({
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
  ConsumerState<OsmLocationPicker> createState() => _OsmLocationPickerState();
}

class _OsmLocationPickerState extends ConsumerState<OsmLocationPicker> {
  late final TextEditingController _addressController;
  late double _selectedLat;
  late double _selectedLng;
  late String _selectedAddress;
  bool _isLoading = false;
  bool _hasSelection = false;
  double _pendingLat = 0;
  double _pendingLng = 0;
  Timer? _cameraReverseGeocodeTimer;

  @override
  void initState() {
    super.initState();
    _selectedLat = widget.initialLocation?.latitude ?? AppConstants.moscowLat;
    _selectedLng = widget.initialLocation?.longitude ?? AppConstants.moscowLng;
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
    _cameraReverseGeocodeTimer?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  void _onMapTap(double lat, double lng) {
    setState(() {
      _selectedLat = lat;
      _selectedLng = lng;
      _selectedAddress =
          'Точка на карте: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      _hasSelection = true;
    });
    _reverseGeocode(lat, lng);
  }

  void _onCameraMove(double lat, double lng) {
    _pendingLat = lat;
    _pendingLng = lng;
  }

  void _onCameraEnd() {
    setState(() {
      _selectedLat = _pendingLat;
      _selectedLng = _pendingLng;
      _hasSelection = true;
    });
    _cameraReverseGeocodeTimer?.cancel();
    _cameraReverseGeocodeTimer = Timer(
      const Duration(milliseconds: 700),
      () => _reverseGeocode(_pendingLat, _pendingLng),
    );
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final address =
          await OpenStreetMapService.reverseGeocode(lat: lat, lng: lng);
      if (address != null && mounted) {
        setState(() {
          _selectedAddress = address;
        });
      }
    } catch (e) {
      // Keep the coordinate-based address if reverse geocoding fails
      debugPrint('Reverse geocoding failed: $e');
    }
  }

  Future<void> _detectCurrentLocation() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final location = await OpenStreetMapService.getCurrentLocation();
      if (!mounted || location == null) return;

      setState(() {
        _selectedLat = location.latitude;
        _selectedLng = location.longitude;
        _selectedAddress = location.address;
        _hasSelection = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedLat = AppConstants.moscowLat;
        _selectedLng = AppConstants.moscowLng;
        _selectedAddress = 'Москва, центр';
        _hasSelection = true;
      });
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
      final location = await OpenStreetMapService.searchLocation(query);
      if (!mounted || location == null) {
        _showError('Адрес не найден. Уточните запрос.');
        return;
      }

      setState(() {
        _selectedLat = location.latitude;
        _selectedLng = location.longitude;
        _selectedAddress = location.address;
        _hasSelection = true;
      });
    } catch (_) {
      if (mounted) _showError('Не удалось найти адрес. Попробуйте еще раз.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirm() {
    if (!_hasSelection) return;
    widget.onLocationConfirmed(
      MapLocation(
        latitude: _selectedLat,
        longitude: _selectedLng,
        address: _selectedAddress,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AvroClientColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AvroClientColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: EvikOsmMapView(
              initialLat: _selectedLat,
              initialLng: _selectedLng,
              initialZoom: 16,
              onTap: _onMapTap,
              onCameraMove: _onCameraMove,
              onCameraEnd: _onCameraEnd,
              onLocationButtonPressed: (lat, lng, address) {
                setState(() {
                  _selectedLat = lat;
                  _selectedLng = lng;
                  _selectedAddress = address;
                  _hasSelection = true;
                });
              },
              fitToMarkers: false,
              showUserLocation: false, // We handle location separately
              controlsBottomOffset: 234,
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
      color: AvroClientColors.background,
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
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isLoading ? null : onUseCurrentLocation,
                  icon: const Icon(
                    Icons.navigation_rounded,
                    color: AvroClientColors.accent,
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
                  fillColor: AvroClientColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AvroClientColors.surface),
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
          color: AvroClientColors.background,
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
                color: AvroClientColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodyLarge.copyWith(
                color: AvroClientColors.textPrimary,
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

class _PickerPin extends StatelessWidget {
  const _PickerPin();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -22),
      child: const Icon(
        Icons.location_pin,
        color: AvroClientColors.accent,
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
