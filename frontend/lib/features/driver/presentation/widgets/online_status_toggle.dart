import 'package:flutter/material.dart';

class OnlineStatusToggle extends StatelessWidget {
  const OnlineStatusToggle({
    super.key,
    required this.isOnline,
    required this.isLoading,
    required this.onlineSince,
    required this.onToggle,
  });

  final bool isOnline;
  final bool isLoading;
  final DateTime? onlineSince;
  final Future<void> Function() onToggle;

  @override
  Widget build(BuildContext context) {
    final color = isLoading
        ? const Color(0xFFF5A623)
        : isOnline
            ? const Color(0xFF2E9B62)
            : const Color(0xFF98A2B3);
    final label = isLoading
        ? 'Подключаемся...'
        : isOnline
            ? 'В сети'
            : 'Не в сети';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isOnline && onlineSince != null)
                Text(
                  'Онлайн ${_formatDuration(DateTime.now().difference(onlineSince!))}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF667085),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Switch(
            value: isOnline,
            onChanged: isLoading
                ? null
                : (_) async {
                    if (isOnline) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Завершить рабочий день?'),
                            content: const Text(
                              'Вы перестанете получать новые заказы, но сможете вернуться онлайн в любой момент.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Нет'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Завершить'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirmed != true) {
                        return;
                      }
                    }

                    await onToggle();
                  },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) {
      return '$minutesм';
    }
    return '$hoursч $minutesм';
  }
}
