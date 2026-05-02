import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';

class NavigationService {
  /// Opens route in external navigation app (Yandex Navigator or Maps)
  static Future<bool> openRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String? orderName,
  }) async {
    try {
      // Try Yandex Navigator first (better for Russian users)
      final yandexNavUrl = Uri(
        scheme: 'yandexnavi',
        path: 'build_route_on_map',
        queryParameters: {
          'lat_to': toLat.toString(),
          'lon_to': toLng.toString(),
          'lat_from': fromLat.toString(),
          'lon_from': fromLng.toString(),
        },
      );

      if (await canLaunchUrl(yandexNavUrl)) {
        await launchUrl(yandexNavUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      // Fallback to Yandex Maps web interface
      final yandexMapsUrl = Uri.parse(
        'https://yandex.ru/maps/?rtext=$fromLat,$fromLng~$toLat,$toLng&rtt=auto'
      );

      if (await canLaunchUrl(yandexMapsUrl)) {
        await launchUrl(yandexMapsUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      // Last fallback to Google Maps (universal)
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