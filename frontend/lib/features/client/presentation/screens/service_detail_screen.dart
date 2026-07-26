import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';

class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  double? _lat;
  double? _lng;
  String _address = 'Определяем местоположение...';
  bool _loading = true;
  bool _locationUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final permission = await LocationService.requestLocationPermission();

    if (!mounted) return;

    if (permission != PermissionResult.granted) {
      setState(() {
        _loading = false;
        _locationUnavailable = true;
        _address = 'Местоположение недоступно';
      });
      return;
    }

    try {
      final pos = await LocationService.getCurrentPositionWithFallback();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      final addr = await OpenStreetMapService.reverseGeocode(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      setState(() {
        _address = addr ?? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _locationUnavailable = true;
        _address = 'Местоположение недоступно';
      });
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Скоро будет доступно',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AvroClientColors.background,
            ),
          ),
          backgroundColor: AvroClientColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final displayLat = _lat ?? AppConstants.moscowLat;
    final displayLng = _lng ?? AppConstants.moscowLng;
    final showLocationWarning = _locationUnavailable && !_loading;
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AvroClientColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AvroClientColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AvroClientColors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 44, color: AvroClientColors.accent),
              ),
              const SizedBox(height: 20),
              Text(
                widget.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AvroClientColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AvroClientColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (showLocationWarning) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AvroClientColors.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_off_rounded, size: 20, color: AvroClientColors.background),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Местоположение недоступно',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AvroClientColors.background),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: EvikOsmMapView(
                    key: const ValueKey('service_detail_map'),
                    initialLat: displayLat,
                    initialLng: displayLng,
                    initialZoom: 15,
                    showControls: false,
                    showLocationButton: false,
                    showUserLocation: false,
                    fitToMarkers: false,
                    markers: [
                      EvikMapMarker(
                        lat: displayLat,
                        lng: displayLng,
                        title: _address,
                        color: AvroClientColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AvroClientColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _loading ? 'Определяем адрес...' : _address,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AvroClientColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _showComingSoon,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvroClientColors.accent,
                    foregroundColor: AvroClientColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.build_outlined, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Вызвать мастера',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse('https://t.me/avro_partners')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AvroClientColors.accent,
                    side: const BorderSide(color: AvroClientColors.accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.handshake_outlined, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Стать партнёром',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Скоро здесь появятся\nмастера вашего города',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AvroClientColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
