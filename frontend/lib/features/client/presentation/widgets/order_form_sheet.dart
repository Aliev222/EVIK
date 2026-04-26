import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../order/domain/entities/order.dart';
import '../providers/client_order_provider.dart';

class OrderFormSheet extends ConsumerStatefulWidget {
  const OrderFormSheet({
    super.key,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.onSubmit,
  });

  final String pickupAddress;
  final String dropoffAddress;
  final VoidCallback? onSubmit;

  @override
  ConsumerState<OrderFormSheet> createState() => _OrderFormSheetState();
}

class _OrderFormSheetState extends ConsumerState<OrderFormSheet> {
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  VehicleType _vehicleType = VehicleType.light;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    final form = ref.read(clientOrderProvider).orderForm;
    _phoneController = TextEditingController(text: form.phoneNumber);
    _notesController = TextEditingController(text: form.notes);
    _vehicleType = form.vehicleType;
    _paymentMethod = form.paymentMethod;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientOrderProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: SizedBox(
                width: 40,
                child: Divider(thickness: 4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Детали заказа',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _address('Откуда', widget.pickupAddress),
            _address('Куда', widget.dropoffAddress),
            const SizedBox(height: 12),
            Semantics(
              label: 'Выбор типа транспорта',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VehicleType.values.map((type) {
                  final selected = type == _vehicleType;
                  return ChoiceChip(
                    label: Text(_vehicleLabel(type)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _vehicleType = type);
                      _updateForm();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                hintText: '+7 999 123 45 67',
              ),
              onChanged: (_) => _updateForm(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание проблемы',
                hintText: 'Например: не заводится после дождя',
              ),
              onChanged: (_) => _updateForm(),
            ),
            const SizedBox(height: 12),
            Row(
              children: PaymentMethod.values.map((method) {
                final selected = method == _paymentMethod;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                          method == PaymentMethod.cash ? 'Наличные' : 'Карта'),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _paymentMethod = method);
                        _updateForm();
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (state.estimatedPrice != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EvikColors.surfaceDark,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Примерная стоимость: ${state.estimatedPrice!.toStringAsFixed(0)}₽',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'Кнопка вызова эвакуатора',
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.isLoading ? null : widget.onSubmit,
                  child: state.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Подтвердить заказ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _address(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: EvikColors.textSecondaryDark)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _updateForm() {
    ref.read(clientOrderProvider.notifier).updateOrderForm(
          OrderFormData(
            vehicleType: _vehicleType,
            phoneNumber: _phoneController.text.trim(),
            paymentMethod: _paymentMethod,
            notes: _notesController.text.trim(),
            description: _notesController.text.trim(),
          ),
        );
  }

  String _vehicleLabel(VehicleType type) {
    return switch (type) {
      VehicleType.light => 'Легковой',
      VehicleType.suv => 'SUV',
      VehicleType.minibus => 'Минивэн',
      VehicleType.truck => 'Грузовой',
    };
  }
}
