import 'package:flutter/material.dart';

import '../../../../core/theme/evik_colors.dart';

class IdleOrderView extends StatelessWidget {
  const IdleOrderView({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onCreate,
        child: const Text('Создать заказ'),
      ),
    );
  }
}

class SearchingOrderView extends StatelessWidget {
  const SearchingOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(EvikColors.accent),
      ),
    );
  }
}

class AcceptedOrderView extends StatelessWidget {
  const AcceptedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Водитель принял заказ'));
  }
}

class ArrivedOrderView extends StatelessWidget {
  const ArrivedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Водитель прибыл'));
  }
}

class InProgressOrderView extends StatelessWidget {
  const InProgressOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Эвакуация выполняется'));
  }
}

class CompletedOrderView extends StatelessWidget {
  const CompletedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Заказ завершён'));
  }
}

class CancelledOrderView extends StatelessWidget {
  const CancelledOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Заказ отменён'));
  }
}

class NoDriverFoundOrderView extends StatelessWidget {
  const NoDriverFoundOrderView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Нет доступных эвакуаторов'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}
