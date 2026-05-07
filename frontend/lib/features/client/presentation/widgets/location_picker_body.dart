import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../map/domain/entities/map_location.dart';
import 'promaps_location_picker.dart';

class LocationPickerBody extends ConsumerWidget {
  const LocationPickerBody({
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
  Widget build(BuildContext context, WidgetRef ref) {
    return ProMapsLocationPicker(
      title: title,
      addressLabel: addressLabel,
      initialLocation: initialLocation,
      initialAddress: initialAddress,
      confirmText: confirmText,
      onLocationConfirmed: onLocationConfirmed,
    );
  }
}
