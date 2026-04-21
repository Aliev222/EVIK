import 'package:flutter/material.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_tokens.dart';
import '../../../../core/widgets/app_state_card.dart';

class IdleOrderView extends StatelessWidget {
  const IdleOrderView({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AppStateCard(
      key: const ValueKey<String>('idle'),
      icon: Icons.local_shipping_outlined,
      title: 'Готовы вызвать эвакуатор',
      subtitle:
          'Проверьте маршрут, выберите параметры автомобиля и отправьте заказ в один тап.',
      primaryLabel: 'Создать заказ',
      onPrimary: onCreate,
    );
  }
}

class SearchingOrderView extends StatelessWidget {
  const SearchingOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('searching'),
      icon: Icons.radar_outlined,
      title: 'Ищем ближайший экипаж',
      subtitle:
          'Подбираем свободный эвакуатор рядом с вами. Обычно это занимает меньше минуты.',
      footer: Padding(
        padding: EdgeInsets.only(top: EvikSpacing.xs),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            valueColor: AlwaysStoppedAnimation<Color>(EvikColors.accent),
          ),
        ),
      ),
    );
  }
}

class AcceptedOrderView extends StatelessWidget {
  const AcceptedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('accepted'),
      icon: Icons.task_alt_outlined,
      title: 'Водитель назначен',
      subtitle:
          'Заказ подтвержден. На следующем проходе добавим карточку водителя, ETA и номер машины.',
      accentColor: Color(0xFF2C6E49),
    );
  }
}

class ArrivedOrderView extends StatelessWidget {
  const ArrivedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('arrived'),
      icon: Icons.place_outlined,
      title: 'Эвакуатор на месте',
      subtitle:
          'Экран уже дает четкий статус. Дальше можно будет показать контакт и инструкции клиенту.',
      accentColor: Color(0xFF2C6E49),
    );
  }
}

class InProgressOrderView extends StatelessWidget {
  const InProgressOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('in-progress'),
      icon: Icons.route_outlined,
      title: 'Заказ в работе',
      subtitle:
          'Машина уже в пути. Здесь хорошо лягут живые события, таймлайн и текущий этап заказа.',
      accentColor: Color(0xFF2C6E49),
    );
  }
}

class CompletedOrderView extends StatelessWidget {
  const CompletedOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('completed'),
      icon: Icons.verified_outlined,
      title: 'Заказ завершен',
      subtitle:
          'Финальный экран стал чище и спокойнее. Позже сюда можно добавить чек, оценку и повторный вызов.',
      accentColor: Color(0xFF2C6E49),
    );
  }
}

class CancelledOrderView extends StatelessWidget {
  const CancelledOrderView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppStateCard(
      key: ValueKey<String>('cancelled'),
      icon: Icons.close_rounded,
      title: 'Заказ отменен',
      subtitle:
          'Пользователь сразу видит итог без лишнего шума. Здесь можно будет добавить понятную причину отмены.',
      accentColor: EvikColors.danger,
    );
  }
}

class NoDriverFoundOrderView extends StatelessWidget {
  const NoDriverFoundOrderView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppStateCard(
      key: const ValueKey<String>('no-driver-found'),
      icon: Icons.search_off_rounded,
      title: 'Свободных экипажей пока нет',
      subtitle:
          'Можно повторить поиск через пару секунд. На следующем этапе добавим альтернативное время подачи.',
      primaryLabel: 'Повторить поиск',
      onPrimary: onRetry,
      accentColor: EvikColors.danger,
    );
  }
}
