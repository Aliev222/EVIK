import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

class OfflineSosScreen extends ConsumerStatefulWidget {
  const OfflineSosScreen({super.key});

  @override
  ConsumerState<OfflineSosScreen> createState() => _OfflineSosScreenState();
}

class _OfflineSosScreenState extends ConsumerState<OfflineSosScreen> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  void _initLocation() {
    Geolocator.getLastKnownPosition().then((pos) {
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
    });
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _currentPosition = pos);
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _call(String number) {
    launchUrl(Uri.parse('tel:$number'));
  }

  void _copyCoordinates() {
    if (_currentPosition == null) return;
    final text =
        '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}';
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Координаты скопированы'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _retry() {
    setState(() => _isRetrying = true);
    ref.read(authProvider.notifier).retrySession();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentPosition?.latitude;
    final lng = _currentPosition?.longitude;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/img/load.png',
                  width: 100,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  'Авро',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AvroClientColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AvroClientColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: AvroClientColors.error, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Нет подключения к сети',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AvroClientColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GPS-координаты доступны',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AvroClientColors.tabInactive,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AvroClientColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.my_location_rounded,
                        color: AvroClientColors.accent,
                        size: 28,
                      ),
                      const SizedBox(height: 10),
                      if (lat != null && lng != null) ...[
                        Text(
                          '${_formatCoord(lat)}° N, ${_formatCoord(lng)}° E',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AvroClientColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            color: AvroClientColors.tabInactive,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else ...[
                        Text(
                          'Определение координат...',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AvroClientColors.tabInactive,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'обновляется в реальном времени',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AvroClientColors.tabInactive,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _SosButton(
                  label: 'Позвонить 112',
                  icon: Icons.phone_rounded,
                  color: AvroClientColors.error,
                  onTap: () => _call('112'),
                ),
                const SizedBox(height: 10),
                _SosButton(
                  label: 'ГАИ / ГИБДД',
                  icon: Icons.local_police_rounded,
                  color: AvroClientColors.info,
                  onTap: () => _call('102'),
                ),
                const SizedBox(height: 10),
                _SosButton(
                  label: 'Скорая помощь',
                  icon: Icons.local_hospital_rounded,
                  color: AvroClientColors.error,
                  onTap: () => _call('103'),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _copyCoordinates,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Скопировать координаты'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AvroClientColors.textSecondary,
                    side: BorderSide(color: AvroClientColors.surface),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isRetrying ? null : _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AvroClientColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isRetrying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Повторить вход',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCoord(double value) {
    final deg = value.abs().floor();
    final min = ((value.abs() - deg) * 60);
    return '$deg°${min.toStringAsFixed(2)}';
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
