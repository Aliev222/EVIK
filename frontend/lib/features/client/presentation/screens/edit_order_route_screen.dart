import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tow_truck_frontend/core/config/build_flags.dart';
import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/widgets/location_picker_body.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

/// A separate navigator keeps the live order underneath both draft screens.
Future<void> editOrderRoute(BuildContext context, Order order) async {
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => EditOrderRouteScreen(order: order),
  ));
}

class EditOrderRouteScreen extends ConsumerStatefulWidget {
  const EditOrderRouteScreen({super.key, required this.order});
  final Order order;
  @override
  ConsumerState<EditOrderRouteScreen> createState() =>
      _EditOrderRouteScreenState();
}

class _EditOrderRouteScreenState extends ConsumerState<EditOrderRouteScreen> {
  late LocationModel _pickup = widget.order.pickupLocation;
  bool _busy = false;
  bool get _destinationOnly => widget.order.status == OrderStatus.evacuating;
  static final _audit = developmentFeatureEnabled(
      requested: const bool.fromEnvironment('EVIK_UI_AUDIT'),
      releaseMode: kReleaseMode);

  MapLocation _map(LocationModel p) =>
      MapLocation(latitude: p.lat, longitude: p.lng, address: p.address);
  LocationModel _location(MapLocation p) => LocationModel(
      lat: p.latitude, lng: p.longitude, address: p.displayAddress);

  Future<void> _confirm(
      BuildContext pageContext, MapLocation destination) async {
    if (_busy) return;
    setState(() => _busy = true);
    final dropoff = _location(destination);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final quote = _audit
          ? <String, dynamic>{'quote_id': 'preview', 'price_total': 210000}
          : await (repo as HttpOrderRepository)
              .quoteRouteChange(widget.order.id, _pickup, dropoff);
      if (!mounted || !pageContext.mounted) return;
      final accepted = await showDialog<bool>(
          context: pageContext,
          builder: (ctx) => AlertDialog(
                title: const Text('Подтвердить маршрут'),
                content: Text('${_pickup.address}\n↓\n${dropoff.address}\n\n'
                    'Новая стоимость: ${((quote['price_total'] as num) / 100).toStringAsFixed(0)} ₽'
                    '${_audit ? '\nДемонстрационная цена — UI-аудит' : ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Назад')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Подтвердить')),
                ],
              ));
      if (accepted != true || !mounted) return;
      final updated = _audit
          ? widget.order.copyWith(
              pickupLocation: _pickup,
              dropoffLocation: dropoff,
              estimatedPrice: 2100,
              finalPrice: 2100)
          : await (repo as HttpOrderRepository)
              .confirmRouteChange(widget.order.id, quote['quote_id'] as String);
      if (!mounted) return;
      ref.read(orderFlowProvider.notifier).applyRouteChange(updated);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted || !pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(SnackBar(
          content: Text(error is ApiClientException
              ? error.message
              : 'Не удалось изменить маршрут. Заказ сохранён. Попробуйте ещё раз.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (inner) => _destinationOnly
                ? _destination(inner)
                : LocationPickerBody(
                    title: 'Откуда забрать автомобиль?',
                    addressLabel: 'Адрес подачи',
                    onBack: () => Navigator.of(context).pop(),
                    initialLocation: _map(_pickup),
                    initialAddress: _pickup.address,
                    confirmText: 'Далее — куда отвезти',
                    onLocationConfirmed: (p) {
                      _pickup = _location(p);
                      Navigator.of(inner)
                          .push(MaterialPageRoute<void>(builder: _destination));
                    },
                  )),
      );

  Widget _destination(BuildContext inner) => LocationPickerBody(
        title: 'Куда отвезти автомобиль?',
        addressLabel: 'Адрес доставки',
        onBack: () => _destinationOnly
            ? Navigator.of(context).pop()
            : Navigator.of(inner).pop(),
        initialLocation: _map(widget.order.dropoffLocation),
        initialAddress: widget.order.dropoffLocation.address,
        confirmText: _busy ? 'Рассчитываем…' : 'Рассчитать новую стоимость',
        onLocationConfirmed: (p) => _confirm(inner, p),
      );
}
