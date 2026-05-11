import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../map/presentation/widgets/evik_osm_map_view.dart';
import '../providers/order_flow_provider.dart';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({
    super.key,
    this.onProfilePressed,
  });

  final VoidCallback? onProfilePressed;

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderFlowProvider.notifier).detectCurrentLocation();
    });
  }

  void _openPickupSelection() {
    ref.read(orderFlowProvider.notifier).startOrderFlow();
    context.push('/order/pickup');
  }

  @override
  Widget build(BuildContext context) {
    final location =
        ref.watch(orderFlowProvider.select((state) => state.pickupLocation));
    final isLoading =
        ref.watch(orderFlowProvider.select((state) => state.isLoading));
    final address = _cleanAddress(location?.displayAddress);
    final lat = location?.latitude ?? AppConstants.moscowLat;
    final lng = location?.longitude ?? AppConstants.moscowLng;

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: Stack(
        children: [
          Positioned.fill(
            child: EvikOsmMapView(
              key: const ValueKey('client_home_map'),
              initialLat: lat,
              initialLng: lng,
              initialZoom: 15.5,
              markers: [
                EvikMapMarker(
                  lat: lat,
                  lng: lng,
                  title: address,
                  color: EvikColors.accentOrange,
                ),
              ],
              controlsBottomOffset: MediaQuery.paddingOf(context).bottom + 168,
              controlsBackgroundColor: EvikColors.primaryWhite,
              controlsIconColor: EvikColors.accentOrange,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 14,
            left: 20,
            right: 72,
            child: _AddressBadge(
              address: address,
              isLoading: isLoading,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 14,
            right: 18,
            child: _ProfileButton(
              onPressed: widget.onProfilePressed,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: _CallTowTruckButton(
              onPressed: _openPickupSelection,
            ),
          ),
        ],
      ),
    );
  }

  String _cleanAddress(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return 'Москва, ЦАО';
    if (text.contains('Р') || text.contains('СЃ')) return 'Москва, ЦАО';
    if (text == 'Адрес не указан') return 'Москва, ЦАО';
    return text;
  }
}

class _AddressBadge extends StatelessWidget {
  const _AddressBadge({
    required this.address,
    required this.isLoading,
  });

  final String address;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showMarker = constraints.maxWidth >= 64;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showMarker) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: EvikColors.accentOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  isLoading ? 'Определяем адрес...' : address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.primaryBlack,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: EvikColors.primaryBlack,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              'A',
              style: EvikTypography.bodyLarge.copyWith(
                color: EvikColors.primaryWhite,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallTowTruckButton extends StatelessWidget {
  const _CallTowTruckButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Material(
        color: EvikColors.accentOrange,
        borderRadius: BorderRadius.circular(16),
        elevation: 8,
        shadowColor: EvikColors.accentOrange.withValues(alpha: 0.28),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 220;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 18),
                child: Row(
                  children: [
                    if (!compact) ...[
                      const Icon(
                        Icons.local_shipping_rounded,
                        color: EvikColors.primaryWhite,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        'Вызвать эвакуатор',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.buttonText.copyWith(
                          color: EvikColors.primaryWhite,
                          fontSize: compact ? 13 : 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!compact)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              EvikColors.primaryWhite.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: EvikColors.primaryWhite,
                          size: 22,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
