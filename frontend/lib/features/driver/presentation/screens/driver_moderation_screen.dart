import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_moderation_provider.dart';

class DriverModerationScreen extends ConsumerWidget {
  const DriverModerationScreen({
    super.key,
    this.document,
    this.errorMessage,
    this.isLoading = false,
    this.showMissingState = false,
  });

  final DriverVerificationDocument? document;
  final String? errorMessage;
  final bool isLoading;
  final bool showMissingState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final moderationAsync = user == null
        ? const AsyncValue<DriverVerificationDocument?>.data(null)
        : ref.watch(watchDriverModerationProvider(user.id));

    if (isLoading) {
      return const _ModerationScaffold(
        child: _StatusCard(
          icon: Icons.hourglass_top_rounded,
          title: 'Проверяем статус',
          description: 'Загружаем данные модерации.',
          child: Padding(
            padding: EdgeInsets.only(top: 18),
            child: CircularProgressIndicator(color: EvikColors.accent),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return _ModerationScaffold(
        child: _StatusCard(
          icon: Icons.error_outline_rounded,
          title: 'Не удалось загрузить статус',
          description: errorMessage!,
        ),
      );
    }

    if (document != null) {
      return _buildFromDocument(context, document!);
    }

    return moderationAsync.when(
      data: (liveDocument) {
        if (liveDocument == null) {
          return _ModerationScaffold(
            child: _StatusCard(
              icon: Icons.assignment_late_rounded,
              title: showMissingState
                  ? 'Заявка еще не отправлена'
                  : 'Документы еще не найдены',
              description: showMissingState
                  ? 'Чтобы получить доступ к водительскому кабинету, завершите onboarding и отправьте документы на модерацию.'
                  : 'Верификационный документ не найден. Завершите onboarding или повторите вход.',
            ),
          );
        }

        return _buildFromDocument(context, liveDocument);
      },
      loading: () => const _ModerationScaffold(
        child: _StatusCard(
          icon: Icons.hourglass_top_rounded,
          title: 'Проверяем статус',
          description: 'Загружаем данные модерации.',
          child: Padding(
            padding: EdgeInsets.only(top: 18),
            child: CircularProgressIndicator(color: EvikColors.accent),
          ),
        ),
      ),
      error: (error, _) => const _ModerationScaffold(
        child: _StatusCard(
          icon: Icons.error_outline_rounded,
          title: 'Ошибка загрузки',
          description:
              'Не удалось получить статус модерации. Проверьте соединение и попробуйте позже.',
        ),
      ),
    );
  }

  Widget _buildFromDocument(
    BuildContext context,
    DriverVerificationDocument document,
  ) {
    return switch (document.status) {
      DriverModerationStatus.pending => const _ModerationScaffold(
          child: _StatusCard(
            icon: Icons.fact_check_rounded,
            title: 'Документы на проверке',
            description:
                'Мы получили ваши документы и уже передали их модератору. Обычно проверка занимает от нескольких минут до рабочего дня.',
            child: Padding(
              padding: EdgeInsets.only(top: 18),
              child: LinearProgressIndicator(
                minHeight: 8,
                borderRadius: BorderRadius.all(Radius.circular(999)),
                backgroundColor: Color(0xFFE2DDD5),
                valueColor: AlwaysStoppedAnimation<Color>(EvikColors.accent),
              ),
            ),
          ),
        ),
      DriverModerationStatus.rejected => _ModerationScaffold(
          child: _StatusCard(
            icon: Icons.gpp_bad_rounded,
            title: 'Проверка не пройдена',
            description: document.rejectionReason?.trim().isNotEmpty == true
                ? document.rejectionReason!
                : 'Модератор отклонил заявку. Уточните причину и подготовьте новые документы.',
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _contactSupport(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EvikColors.textPrimaryDark,
                    side: const BorderSide(color: Color(0xFFD8D2C7)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Обратиться в поддержку',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      DriverModerationStatus.approved => const _ModerationScaffold(
          child: _StatusCard(
            icon: Icons.verified_rounded,
            title: 'Документы одобрены',
            description:
                'Проверка успешно завершена. Водительский кабинет будет открыт автоматически.',
          ),
        ),
    };
  }

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@evik.app',
      queryParameters: {
        'subject': 'Проблема с модерацией водителя',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось открыть поддержку на этом устройстве.'),
      ),
    );
  }
}

class _ModerationScaffold extends StatelessWidget {
  const _ModerationScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
    this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFF1EEE8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              icon,
              size: 38,
              color: EvikColors.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: EvikColors.textPrimaryDark,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: EvikColors.textSecondaryDark,
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
