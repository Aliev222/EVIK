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
  const OfflineSosScreen({super.key, this.isSosOnly = false});

  /// When true the screen is opened from the app's SOS entry (home slider /
  /// profile tab) and renders a focused emergency screen instead of the
  /// offline-login retry flow.
  final bool isSosOnly;

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

    if (widget.isSosOnly) {
      return _buildSosOnly(context, lat, lng);
    }

    return _buildOfflineLogin(context, lat, lng);
  }

  /// Offline-login retry flow (shown when a persisted session can't be
  /// restored without a network connection). Coordinates and emergency-call
  /// buttons remain available because GPS and tel: work offline.
  Widget _buildOfflineLogin(BuildContext context, double? lat, double? lng) {
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
                _SosCoordsCard(
                  lat: lat,
                  lng: lng,
                  title: 'GPS-координаты',
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

  /// Focused emergency screen: real GPS coordinates, honest note, and direct
  /// dial buttons. No server, no SMS — GPS and tel: work fully offline.
  Widget _buildSosOnly(BuildContext context, double? lat, double? lng) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AvroClientColors.textPrimary,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      'Экстренная связь',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AvroClientColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AvroClientColors.sosRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'SOS',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AvroClientColors.sosRed,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AvroClientColors.sosRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.gps_fixed_rounded,
                            size: 22,
                            color: AvroClientColors.sosRed,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ваши координаты определяются по GPS и работают '
                              'без интернета. Назовите их спасателям.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AvroClientColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SosCoordsCard(
                      lat: lat,
                      lng: lng,
                      title: 'Ваши координаты',
                    ),
                    const SizedBox(height: 24),
                    _SosButton(
                      label: 'Позвонить 112',
                      icon: Icons.phone_rounded,
                      color: AvroClientColors.sosRed,
                      onTap: () => _call('112'),
                    ),
                    const SizedBox(height: 10),
                    _SosButton(
                      label: 'Скорая помощь 103',
                      icon: Icons.local_hospital_rounded,
                      color: AvroClientColors.error,
                      onTap: () => _call('103'),
                    ),
                    const SizedBox(height: 10),
                    _SosButton(
                      label: 'ГАИ / ГИБДД 102',
                      icon: Icons.local_police_rounded,
                      color: AvroClientColors.info,
                      onTap: () => _call('102'),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

class _SosCoordsCard extends StatelessWidget {
  const _SosCoordsCard({required this.lat, required this.lng, required this.title});

  final double? lat;
  final double? lng;
  final String title;

  @override
  Widget build(BuildContext context) {
    final degree = lat != null && lng != null
        ? '${_format(lat!.abs())}° N, ${_format(lng!.abs())}° E'
        : null;
    return Container(
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
              degree!,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AvroClientColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: AvroClientColors.tabInactive,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Text(
              'Определяем координаты…',
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
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AvroClientColors.tabInactive,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'обновляется в реальном времени',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AvroClientColors.tabInactive,
            ),
          ),
        ],
      ),
    );
  }

  static String _format(double value) {
    final deg = value.abs().floor();
    final min = ((value.abs() - deg) * 60);
    return '$deg°${min.toStringAsFixed(2)}';
  }
}
