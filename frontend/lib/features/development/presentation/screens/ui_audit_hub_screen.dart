import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/features/client/presentation/screens/client_app_shell.dart';
import 'package:tow_truck_frontend/features/driver/presentation/driver_screen.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:tow_truck_frontend/shared/widgets/offline_sos_screen.dart';

/// Development-only navigation hub for visual QA on a physical device or
/// simulator. The entry point is protected in [main.dart] by a dart-define
/// and cannot be enabled in a release binary.
class UiAuditHubScreen extends StatelessWidget {
  const UiAuditHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        title: const Text('UI-аудит Авро'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Только для разработки',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Открывай экран, делай скриншот, возвращайся сюда. '
            'Режим не включается в release-сборках.',
          ),
          const SizedBox(height: 22),
          _Section(
            title: 'Основа',
            children: [
              _AuditEntry(
                icon: Icons.person_outline_rounded,
                title: 'Выбор роли',
                subtitle: 'Первый запуск',
                onTap: () => _open(context, const RoleSelectionScreen()),
              ),
              _AuditEntry(
                icon: Icons.home_outlined,
                title: 'Главная клиента',
                subtitle: 'Карта, услуги и нижняя навигация',
                onTap: () => _open(context, const ClientAppShell()),
              ),
              _AuditEntry(
                icon: Icons.local_shipping_outlined,
                title: 'Главная водителя',
                subtitle: 'Смена, заказы и профиль',
                onTap: () => _open(context, const DriverScreen()),
              ),
              _AuditEntry(
                icon: Icons.sos_rounded,
                title: 'SOS',
                subtitle: 'Экстренный сценарий без входа',
                onTap: () => _open(
                  context,
                  const OfflineSosScreen(isSosOnly: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Заказ эвакуатора',
            children: [
              _AuditEntry(
                icon: Icons.location_on_outlined,
                title: '1. Точка А',
                subtitle: 'Где забрать автомобиль',
                onTap: () => context.push('/order/pickup'),
              ),
              _AuditEntry(
                icon: Icons.flag_outlined,
                title: '2. Точка Б',
                subtitle: 'Куда доставить автомобиль',
                onTap: () => context.push('/order/destination'),
              ),
              _AuditEntry(
                icon: Icons.directions_car_outlined,
                title: '3. Детали заказа',
                subtitle: 'Автомобиль, эвакуатор, цена и оплата',
                onTap: () => context.push('/order/vehicle'),
              ),
              _AuditEntry(
                icon: Icons.radar_rounded,
                title: '4. Поиск водителя',
                subtitle: 'Ожидание и отмена',
                onTap: () => context.push('/order/search'),
              ),
              _AuditEntry(
                icon: Icons.person_pin_circle_outlined,
                title: '5. Водитель найден',
                subtitle: 'Карточка и связь с водителем',
                onTap: () => context.push('/order/driver-info'),
              ),
              _AuditEntry(
                icon: Icons.route_outlined,
                title: '6. Трекинг заказа',
                subtitle: 'Карта, статусы и маршрут',
                onTap: () => context.push('/order/tracking'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _AuditEntry extends StatelessWidget {
  const _AuditEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AvroClientColors.accent),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
