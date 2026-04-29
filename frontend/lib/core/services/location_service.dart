import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants/app_constants.dart';
import '../../features/order/domain/entities/order.dart';

class LocationService {
  static LocationService? _instance;

  LocationService._();

  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }

  factory LocationService() => instance;

  // Яндекс Геокодер API ключ (нужно получить на https://developer.tech.yandex.ru/)
  static const String _routerApiKey = 'YOUR_YANDEX_ROUTER_API_KEY';

  /// Получить текущее местоположение пользователя
  Future<LocationModel?> getCurrentLocation() async {
    try {
      // Проверяем разрешения
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requestedPermission = await Geolocator.requestPermission();
        if (requestedPermission == LocationPermission.denied) {
          throw LocationException('Доступ к геолокации отклонен');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw LocationException('Доступ к геолокации запрещен навсегда');
      }

      // Получаем позицию
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Получаем адрес по координатам
      final address = await _getAddressByCoordinates(
        position.latitude,
        position.longitude,
      );

      return LocationModel(
        lat: position.latitude,
        lng: position.longitude,
        address: address ?? 'Неизвестный адрес',
      );
    } catch (e) {
      throw LocationException('Ошибка получения геолокации: $e');
    }
  }

  /// Получить координаты по адресу (геокодирование)
  Future<LocationModel?> getLocationByAddress(String address) async {
    if (address.trim().isEmpty) return null;

    try {
      // В MVP версии - мок данные для геокодирования
      // В продакшене нужно использовать Яндекс Геокодер API

      // Пример для тестирования (Москва, Красная площадь)
      if (address.toLowerCase().contains('красная площадь')) {
        return const LocationModel(
          lat: 55.753595,
          lng: 37.620393,
          address: 'Красная площадь, Москва',
        );
      }

      // TODO: Интегрировать с Яндекс Геокодер API
      return await _mockGeocode(address);
    } catch (e) {
      throw LocationException('Ошибка геокодирования: $e');
    }
  }

  /// Получить адрес по координатам (обратное геокодирование)
  Future<String?> _getAddressByCoordinates(double lat, double lng) async {
    try {
      final apiKey = AppConstants.yandexGeocoderApiKey;
      if (apiKey.isEmpty || apiKey == 'YOUR_DEV_GEOCODER_KEY_HERE') {
        return 'Москва, ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      final uri = Uri.https('geocode-maps.yandex.ru', '/1.x/', {
        'apikey': apiKey,
        'geocode': '$lng,$lat',
        'format': 'json',
        'kind': 'house',
        'results': '1',
        'lang': 'ru_RU',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'Москва, ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final collection =
          payload['response']?['GeoObjectCollection'] as Map<String, dynamic>?;
      final members = collection?['featureMember'] as List<dynamic>?;
      final first = members?.isNotEmpty == true
          ? members!.first as Map<String, dynamic>
          : null;
      final geoObject = first?['GeoObject'] as Map<String, dynamic>?;
      final meta = geoObject?['metaDataProperty']?['GeocoderMetaData']
          as Map<String, dynamic>?;
      final address = meta?['text']?.toString().trim();

      if (address == null || address.isEmpty) {
        return 'Москва, ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      return address;
    } catch (e) {
      return null;
    }
  }

  /// Рассчитать расстояние по дорогам между двумя точками
  Future<double?> calculateRouteDistance({
    required LocationModel from,
    required LocationModel to,
  }) async {
    try {
      // В MVP версии - используем приблизительный расчет
      // TODO: Интегрировать с Яндекс Маршрутизатор API

      final straightDistance = Geolocator.distanceBetween(
        from.lat,
        from.lng,
        to.lat,
        to.lng,
      );

      // Конвертируем в километры и добавляем 25% на дороги
      return (straightDistance / 1000) * 1.25;
    } catch (e) {
      return null;
    }
  }

  /// Проверить, включены ли службы геолокации
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Получить поток изменений местоположения (для водителей)
  Stream<Position> getLocationStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // обновлять каждые 10 метров
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Мок геокодирования для MVP (заглушка)
  Future<LocationModel?> _mockGeocode(String address) async {
    // Имитация задержки API
    await Future.delayed(const Duration(milliseconds: 500));

    // Простой мок для тестирования
    final mockLocations = {
      'москва': const LocationModel(
        lat: 55.7558,
        lng: 37.6173,
        address: 'Москва, Россия',
      ),
      'спб': const LocationModel(
        lat: 59.9311,
        lng: 30.3609,
        address: 'Санкт-Петербург, Россия',
      ),
      'екатеринбург': const LocationModel(
        lat: 56.8431,
        lng: 60.6454,
        address: 'Екатеринбург, Россия',
      ),
    };

    final normalizedAddress = address.toLowerCase();

    for (final entry in mockLocations.entries) {
      if (normalizedAddress.contains(entry.key)) {
        return entry.value;
      }
    }

    // Если не нашли в моке, возвращаем случайную точку в Москве
    return LocationModel(
      lat: 55.7558 + ((-1 + 2 * (DateTime.now().millisecond / 1000)) * 0.1),
      lng: 37.6173 + ((-1 + 2 * (DateTime.now().microsecond / 1000000)) * 0.1),
      address: address,
    );
  }

  /// Рассчитать время в пути
  Future<int?> calculateEstimatedTime({
    required LocationModel from,
    required LocationModel to,
  }) async {
    try {
      final distance = await calculateRouteDistance(from: from, to: to);
      if (distance == null) return null;

      // Средняя скорость в городе 25 км/ч
      final timeInHours = distance / 25;
      return (timeInHours * 60).round(); // в минутах
    } catch (e) {
      return null;
    }
  }
}

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => 'LocationException: $message';
}
