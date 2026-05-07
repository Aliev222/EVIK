import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import 'promaps_service.dart';

class NavigationService {
  /// Opens route in ProMaps first, then falls back to OS-level navigation.
  static Future<bool> openRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String? orderName,
  }) async {
    try {
      final proMapsUri = Uri.parse(
        ProMapsService.getEmbedMapUrl(lat: toLat, lng: toLng, zoom: 16),
      );

      if (await canLaunchUrl(proMapsUri)) {
        await launchUrl(proMapsUri, mode: LaunchMode.externalApplication);
        return true;
      }

      String googleMapsUrl;
      if (Platform.isAndroid) {
        googleMapsUrl = 'google.navigation:q=$toLat,$toLng';
      } else {
        googleMapsUrl = 'https://maps.google.com/maps?daddr=$toLat,$toLng';
      }

      final googleUri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(googleUri)) {
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
        return true;
      }

      return false;
    } catch (e) {
      if (!AppConstants.isProduction) {
        // Use Flutter's debugPrint in non-production
        debugPrint('NavigationService error: $e');
      }
      return false;
    }
  }

  /// Opens turn-by-turn navigation to specific address
  static Future<bool> startNavigation({
    required double toLat,
    required double toLng,
    String? destinationName,
  }) async {
    return openRoute(
      fromLat: 0, // Will use current location
      fromLng: 0,
      toLat: toLat,
      toLng: toLng,
      orderName: destinationName,
    );
  }
}
