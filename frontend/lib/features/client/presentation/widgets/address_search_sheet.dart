import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';

class AddressSearchSheet extends StatefulWidget {
  const AddressSearchSheet({
    super.key,
    required this.isSelectingPickup,
    this.onLocationSelected,
    this.onCurrentLocation,
  });

  final bool isSelectingPickup;
  final ValueChanged<MapLocation>? onLocationSelected;
  final VoidCallback? onCurrentLocation;

  @override
  State<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<AddressSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  List<AddressSuggestion> _suggestions = const <AddressSuggestion>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSelectingPickup ? 'Адрес забора' : 'Адрес доставки',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Введите адрес',
              filled: true,
              fillColor: AvroClientColors.surface,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AvroClientColors.surface),
              ),
            ),
            onChanged: _onChanged,
            onSubmitted: _search,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: const Text('Текущее место'),
                onPressed: widget.onCurrentLocation,
              ),
              ActionChip(
                avatar: const Icon(Icons.location_city, size: 18),
                label: const Text('Красная площадь'),
                onPressed: () => widget.onLocationSelected?.call(
                  const MapLocation(
                    latitude: 55.7539,
                    longitude: 37.6208,
                    address: 'Красная площадь, Москва',
                  ),
                ),
              ),
            ],
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    title: Text(suggestion.title),
                    subtitle: Text(suggestion.subtitle ?? ''),
                    onTap: () =>
                        widget.onLocationSelected?.call(suggestion.location),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  void _search(String query) {
    if (!mounted) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = const <AddressSuggestion>[];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _suggestions = List<AddressSuggestion>.generate(3, (index) {
          return AddressSuggestion(
            title: '$trimmed, ${index + 1}',
            subtitle: 'Москва',
            location: MapLocation(
              latitude: 55.75 + index * 0.01,
              longitude: 37.61 + index * 0.01,
              address: '$trimmed, ${index + 1}',
            ),
          );
        });
      });
    });
  }
}

class AddressSuggestion {
  const AddressSuggestion({
    required this.title,
    required this.location,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final MapLocation location;
}
