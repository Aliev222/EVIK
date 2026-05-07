import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/services/promaps_service.dart';
import '../../../../core/theme/evik_colors.dart';

class ProMapsView extends StatefulWidget {
  const ProMapsView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onMapCreated,
    this.onTap,
    this.markers = const [],
    this.showUserLocation = true,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final ValueChanged<WebViewController>? onMapCreated;
  final void Function(double lat, double lng)? onTap;
  final List<ProMapMarker> markers;
  final bool showUserLocation;

  @override
  State<ProMapsView> createState() => _ProMapsViewState();
}

class _ProMapsViewState extends State<ProMapsView> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(EvikColors.surfaceDark)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => _isLoading = false);
            }
          },
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            widget.onMapCreated?.call(_controller);
          },
        ),
      )
      ..addJavaScriptChannel(
        'MapEvents',
        onMessageReceived: (JavaScriptMessage message) {
          _handleMapEvent(message.message);
        },
      );

    _loadMap();
  }

  void _loadMap() {
    final lat = widget.initialLat ?? 55.7558; // Default Moscow
    final lng = widget.initialLng ?? 37.6173;

    final htmlContent = _generateMapHTML(lat, lng, widget.initialZoom);
    _controller.loadHtmlString(htmlContent);
  }

  String _generateMapHTML(double lat, double lng, double zoom) {
    final apiKey = 'pk_live_16a7094708ceae689162d22b0d541421236a609a1bd436a0';

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>ProMaps</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { height: 100%; }
        #map {
            height: 100vh;
            width: 100vw;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .loading {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        }
    </style>
    <script src="https://api.promaps.online/js/promaps.js?key=$apiKey"></script>
</head>
<body>
    <div id="map">
        <div class="loading">Загрузка карты...</div>
    </div>

    <script>
        let map;

        function initMap() {
            try {
                map = new ProMaps.Map('map', {
                    center: [$lat, $lng],
                    zoom: $zoom,
                    style: 'default'
                });

                map.on('load', function() {
                    console.log('Map loaded successfully');

                    // Add user location marker if requested
                    ${widget.showUserLocation ? '''
                    if (navigator.geolocation) {
                        navigator.geolocation.getCurrentPosition(function(position) {
                            const userMarker = new ProMaps.Marker([
                                position.coords.latitude,
                                position.coords.longitude
                            ])
                            .setIcon('/assets/user-location.png')
                            .addTo(map);
                        });
                    }
                    ''' : ''}
                });

                map.on('click', function(e) {
                    const latlng = e.latlng;
                    MapEvents.postMessage('tap:' + latlng.lat + ',' + latlng.lng);
                });

                // Add custom markers
                ${_generateMarkersJS()}

            } catch (error) {
                console.error('Map initialization failed:', error);
                document.getElementById('map').innerHTML =
                    '<div class="loading">Ошибка загрузки карты</div>';
            }
        }

        // Map control functions
        window.setCenter = function(lat, lng) {
            if (map) map.setCenter([lat, lng]);
        };

        window.setZoom = function(zoom) {
            if (map) map.setZoom(zoom);
        };

        window.addMarker = function(lat, lng, title) {
            if (map) {
                new ProMaps.Marker([lat, lng])
                    .setPopup(new ProMaps.Popup().setHTML(title))
                    .addTo(map);
            }
        };

        // Initialize map when ProMaps is ready
        if (typeof ProMaps !== 'undefined') {
            initMap();
        } else {
            window.addEventListener('load', initMap);
        }
    </script>
</body>
</html>
    ''';
  }

  String _generateMarkersJS() {
    if (widget.markers.isEmpty) return '';

    final markersJS = widget.markers.map((marker) => '''
      new ProMaps.Marker([${marker.lat}, ${marker.lng}])
        ${marker.title != null ? '.setPopup(new ProMaps.Popup().setHTML("${marker.title}"))' : ''}
        .addTo(map);
    ''').join('\n');

    return markersJS;
  }

  void _handleMapEvent(String message) {
    if (message.startsWith('tap:')) {
      final coords = message.substring(4).split(',');
      if (coords.length == 2) {
        final lat = double.tryParse(coords[0]);
        final lng = double.tryParse(coords[1]);
        if (lat != null && lng != null) {
          widget.onTap?.call(lat, lng);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      // Fallback for unsupported platforms
      return Container(
        decoration: const BoxDecoration(gradient: EvikColors.mapFallbackGradient),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: EvikColors.surfaceDark.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EvikColors.borderDark),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  color: EvikColors.textPrimaryDark,
                  size: 32,
                ),
                SizedBox(height: 8),
                Text(
                  'Карта недоступна',
                  style: TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'ProMaps доступна только на Android',
                  style: TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            decoration: const BoxDecoration(gradient: EvikColors.mapFallbackGradient),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Загрузка ProMaps...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Public methods for controlling the map
  Future<void> setCenter(double lat, double lng) async {
    await _controller.runJavaScript('setCenter($lat, $lng)');
  }

  Future<void> setZoom(double zoom) async {
    await _controller.runJavaScript('setZoom($zoom)');
  }

  Future<void> addMarker(double lat, double lng, {String? title}) async {
    await _controller.runJavaScript('addMarker($lat, $lng, "${title ?? ""}")');
  }
}

/// Маркер для ProMaps
class ProMapMarker {
  final double lat;
  final double lng;
  final String? title;
  final String? icon;

  const ProMapMarker({
    required this.lat,
    required this.lng,
    this.title,
    this.icon,
  });
}