import 'package:flutter/material.dart';

import 'promaps_view_simple.dart';

class ProMapsView extends StatefulWidget {
  const ProMapsView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onTap,
    this.markers = const [],
    this.showUserLocation = true,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final void Function(double lat, double lng)? onTap;
  final List<ProMapMarker> markers;
  final bool showUserLocation;

  @override
  State<ProMapsView> createState() => _ProMapsViewState();
}

class _ProMapsViewState extends State<ProMapsView> {
  @override
  Widget build(BuildContext context) {
    return ProMapsViewSimple(
      initialLat: widget.initialLat,
      initialLng: widget.initialLng,
      initialZoom: widget.initialZoom,
      onTap: widget.onTap,
      markers: widget.markers,
    );
  }
}
