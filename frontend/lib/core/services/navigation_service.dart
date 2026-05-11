import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';

class NavigationService {
  static Future<bool> openRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String? orderName,
  }) async {
    try {
      return NavigationLauncher.openTo(
        toLat: toLat,
        toLng: toLng,
        fromLat: fromLat,
        fromLng: fromLng,
        destinationName: orderName,
      );
    } catch (e) {
      if (!AppConstants.isProduction) {
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

class NavigationLauncher {
  static const String _preferredNavigatorKey = 'preferred_navigation_app';

  static Future<bool> openTo({
    required double toLat,
    required double toLng,
    double? fromLat,
    double? fromLng,
    String? destinationName,
  }) async {
    final candidates = <Uri>[
      Uri.parse(
        'yandexnavi://build_route_on_map?lat_to=$toLat&lon_to=$toLng',
      ),
      Uri.parse(
        'dgis://2gis.ru/routeSearch/rsType/car/to/$toLng,$toLat',
      ),
      if (Platform.isAndroid)
        Uri.parse('google.navigation:q=$toLat,$toLng')
      else
        Uri.parse(
            'comgooglemaps://?daddr=$toLat,$toLng&directionsmode=driving'),
      Uri.https('www.google.com', '/maps/dir/', <String, String>{
        'api': '1',
        'destination': '$toLat,$toLng',
        if (fromLat != null && fromLng != null) 'origin': '$fromLat,$fromLng',
        'travelmode': 'driving',
      }),
    ];

    for (final uri in candidates) {
      if (!await canLaunchUrl(uri)) continue;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }

    return false;
  }

  static Future<bool> openPreferredOrChoose({
    required BuildContext context,
    required double toLat,
    required double toLng,
    double? fromLat,
    double? fromLng,
    String? destinationName,
  }) async {
    final preferred = await getPreferredNavigator();
    if (preferred != null) {
      final launched = await openWith(
        preferred,
        toLat: toLat,
        toLng: toLng,
        fromLat: fromLat,
        fromLng: fromLng,
        destinationName: destinationName,
      );
      if (launched) return true;
    }

    if (!context.mounted) return false;
    final choice = await showNavigatorPicker(context);
    if (choice == null) return false;

    if (choice.remember) {
      await setPreferredNavigator(choice.app);
    }

    return openWith(
      choice.app,
      toLat: toLat,
      toLng: toLng,
      fromLat: fromLat,
      fromLng: fromLng,
      destinationName: destinationName,
    );
  }

  static Future<bool> openWith(
    NavigationApp app, {
    required double toLat,
    required double toLng,
    double? fromLat,
    double? fromLng,
    String? destinationName,
  }) async {
    final uri = _uriFor(app, toLat: toLat, toLng: toLng);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }

    final fallbackUri =
        Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': '$toLat,$toLng',
      if (fromLat != null && fromLng != null) 'origin': '$fromLat,$fromLng',
      'travelmode': 'driving',
    });

    if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      return true;
    }

    return false;
  }

  static Future<NavigationApp?> getPreferredNavigator() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_preferredNavigatorKey);
    for (final app in NavigationApp.values) {
      if (app.name == value) return app;
    }
    return null;
  }

  static Future<void> setPreferredNavigator(NavigationApp app) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredNavigatorKey, app.name);
  }

  static Future<void> clearPreferredNavigator() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_preferredNavigatorKey);
  }

  static Future<NavigatorChoice?> showNavigatorPicker(
    BuildContext context,
  ) async {
    return showModalBottomSheet<NavigatorChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _NavigatorPickerSheet(),
    );
  }

  static Uri _uriFor(
    NavigationApp app, {
    required double toLat,
    required double toLng,
  }) {
    return switch (app) {
      NavigationApp.yandex => Uri.parse(
          'yandexnavi://build_route_on_map?lat_to=$toLat&lon_to=$toLng',
        ),
      NavigationApp.dgis => Uri.parse(
          'dgis://2gis.ru/routeSearch/rsType/car/to/$toLng,$toLat',
        ),
      NavigationApp.google => Platform.isAndroid
          ? Uri.parse('google.navigation:q=$toLat,$toLng')
          : Uri.parse(
              'comgooglemaps://?daddr=$toLat,$toLng&directionsmode=driving',
            ),
    };
  }
}

enum NavigationApp {
  yandex('Яндекс Навигатор', Icons.navigation_rounded),
  dgis('2ГИС', Icons.map_rounded),
  google('Google Maps', Icons.public_rounded);

  const NavigationApp(this.label, this.icon);

  final String label;
  final IconData icon;
}

class NavigatorChoice {
  const NavigatorChoice({
    required this.app,
    required this.remember,
  });

  final NavigationApp app;
  final bool remember;
}

class _NavigatorPickerSheet extends StatefulWidget {
  const _NavigatorPickerSheet();

  @override
  State<_NavigatorPickerSheet> createState() => _NavigatorPickerSheetState();
}

class _NavigatorPickerSheetState extends State<_NavigatorPickerSheet> {
  bool _remember = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Открыть маршрут',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...NavigationApp.values.map(
              (app) => ListTile(
                minLeadingWidth: 24,
                contentPadding: EdgeInsets.zero,
                leading: Icon(app.icon, color: const Color(0xFFFF6B35)),
                title: Text(app.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(
                  NavigatorChoice(app: app, remember: _remember),
                ),
              ),
            ),
            const Divider(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (value) => setState(() => _remember = value ?? true),
              title: const Text('Использовать всегда'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
}
