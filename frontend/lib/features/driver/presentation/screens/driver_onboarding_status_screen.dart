import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_onboarding_status_provider.dart';

class DriverOnboardingStatusScreen extends ConsumerWidget {
  const DriverOnboardingStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverOnboardingStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Подключение водителя')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Не удалось загрузить статус: $e')),
        data: (data) {
          final steps =
              (data['steps'] as List?)?.whereType<Map>().toList() ?? const [];
          final offer = data['offer'] is Map
              ? Map<String, dynamic>.from(data['offer'])
              : const <String, dynamic>{};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Профиль → налоговый тип → оферта → документы → модерация → налоговая проверка → расчёты'),
              const SizedBox(height: 16),
              if (offer['status'] == 'required') ...[
                Text('Актуальная оферта: версия ${offer['version']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (offer['document_url'] != null)
                  SelectableText(offer['document_url'].toString()),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: () async {
                      await acceptCurrentDriverOffer(ref);
                    },
                    child: const Text('Принять оферту')),
              ],
              ...steps.map((step) => ListTile(
                    leading: Icon(step['status'] == 'completed' ||
                            step['status'] == 'accepted'
                        ? Icons.check_circle
                        : Icons.lock_outline),
                    title: Text(step['id']?.toString() ?? 'Шаг'),
                    subtitle: Text(step['reason']?.toString() ??
                        step['status']?.toString() ??
                        'не завершён'),
                  )),
            ],
          );
        },
      ),
    );
  }
}
