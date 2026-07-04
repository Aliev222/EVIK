import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/review/domain/entities/review.dart';
import 'package:tow_truck_frontend/features/review/presentation/providers/review_provider.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';

// Provider for driver profile data
final driverProfileProvider = FutureProvider.autoDispose<Driver?>((ref) async {
  final authState = ref.watch(authProvider);
  final driverId = authState.user?.id;

  if (driverId == null) return null;

  final repository = ref.watch(httpDriverRepositoryProvider);
  return await repository.getDriver(driverId);
});

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driverProfileAsync = ref.watch(driverProfileProvider);

    return driverProfileAsync.when(
      data: (driver) => _buildProfileContent(context, ref, driver),
      loading: () => _buildLoadingContent(context, ref),
      error: (error, stack) => _buildErrorContent(context, ref, error),
    );
  }

  static Widget _buildLoadingContent(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AvroDriverColors.background,
      appBar: AppBar(
        title: Text(
          'Профиль',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AvroDriverColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: const Center(
        child: CircularProgressIndicator(
          color: AvroDriverColors.accent,
        ),
      ),
    );
  }

  static Widget _buildErrorContent(BuildContext context, WidgetRef ref, Object error) {
    return Scaffold(
      backgroundColor: AvroDriverColors.background,
      appBar: AppBar(
        title: Text(
          'Профиль',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AvroDriverColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AvroDriverColors.error,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Ошибка загрузки профиля',
              style: EvikTypography.h3.copyWith(
                color: AvroDriverColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Попробуйте перезайти в приложение',
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroDriverColors.grayHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _getVehicleDisplayText(Driver? driver) {
    if (driver == null) return 'Данные об автомобиле не указаны';

    final hasModel = driver.vehicleModel.isNotEmpty == true;
    final hasNumber = driver.vehicleNumber.isNotEmpty == true;

    if (hasModel && hasNumber) {
      return '${driver.vehicleModel} • ${driver.vehicleNumber}';
    } else if (hasModel) {
      return driver.vehicleModel;
    } else if (hasNumber) {
      return driver.vehicleNumber;
    } else {
      return 'Данные об автомобиле не указаны';
    }
  }

  Widget _buildProfileContent(BuildContext context, WidgetRef ref, Driver? driver) {
    return Scaffold(
      backgroundColor: AvroDriverColors.background,
      appBar: AppBar(
        title: Text(
          'Профиль',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AvroDriverColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          children: [
            // Header с информацией о водителе
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AvroDriverColors.background,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AvroDriverColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        driver?.fullName?.isNotEmpty == true
                            ? driver!.fullName![0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AvroDriverColors.background,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver?.fullName?.isNotEmpty == true
                              ? driver!.fullName!
                              : 'Водитель',
                          style: EvikTypography.h3.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: AvroDriverColors.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              driver?.rating != null && driver!.rating > 0
                                  ? driver.rating.toStringAsFixed(1)
                                  : '—',
                              style: EvikTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              driver?.totalOrders != null
                                  ? '• ${driver!.totalOrders} заказов'
                                  : '• Нет заказов',
                              style: EvikTypography.bodySmall.copyWith(
                                color: AvroDriverColors.grayHint,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          driver?.phone?.isNotEmpty == true
                              ? driver!.phone!
                              : 'Телефон не указан',
                          style: EvikTypography.bodyMedium.copyWith(
                            color: AvroDriverColors.grayHint,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AvroDriverColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Стаж:\nне указан',
                      style: EvikTypography.bodySmall.copyWith(
                        color: AvroDriverColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Меню опций
            ...[
              _ProfileMenuItem(
                icon: Icons.local_shipping_outlined,
                title: 'Мой эвакуатор',
                subtitle: _getVehicleDisplayText(driver),
                onTap: () => _openVehicleInfo(context),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.description_outlined,
                title: 'Документы',
                subtitle: 'Загрузите документы в разделе верификации',
                onTap: () => _showDriverFeature(context, 'Документы', const [
                  'Загрузите документы в разделе верификации',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.notifications_outlined,
                title: 'Уведомления',
                subtitle: 'Новые заказы, выплаты',
                onTap: () => _showDriverFeature(context, 'Уведомления', const [
                  'Новые заказы: включены',
                  'Выплаты: включены',
                  'Новости сервиса: отключены',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.credit_card_outlined,
                title: 'Реквизиты',
                subtitle: 'Карта не привязана',
                onTap: () => _showDriverFeature(context, 'Реквизиты', const [
                  'Карта не привязана',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.security_outlined,
                title: 'Страхование',
                subtitle: 'Страховка не загружена',
                onTap: () => _showDriverFeature(context, 'Страхование', const [
                  'Страховка не загружена',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.star_outlined,
                title: 'Отзывы',
                subtitle: _getReviewsSubtitle(context, ref, driver?.userId),
                onTap: () => _showDriverReviews(context, ref, driver?.userId),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.support_agent_outlined,
                title: 'Поддержка водителей',
                subtitle: '24/7 • Приоритетная линия',
                onTap: () =>
                    _showDriverFeature(context, 'Поддержка водителей', const [
                  'Чат с диспетчером',
                  'support@avro.app',
                  'Вопрос по выплатам',
                ]),
              ),
            ],

            const SizedBox(height: 32),

            // Кнопка выхода
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AvroDriverColors.background,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Выход'),
                        content: const Text('Вы уверены что хотите выйти?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ref.read(authProvider.notifier).signOut();
                            },
                            child: const Text(
                              'Выйти',
                              style: TextStyle(color: AvroDriverColors.error),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Выйти из аккаунта',
                        style: TextStyle(
                          color: AvroDriverColors.error,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVehicleInfo(BuildContext context) => _showDriverFeature(
        context,
        'Мой эвакуатор',
        const [
          'Информация об автомобиле',
          'Загружается из профиля...',
        ],
      );

  String _getReviewsSubtitle(BuildContext context, WidgetRef ref, String? driverId) {
    if (driverId == null) return 'Отзывы недоступны';

    return 'Загрузка отзывов...';
  }

  void _showDriverReviews(BuildContext context, WidgetRef ref, String? driverId) {
    if (driverId == null) return;

    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverReviewsSheet(driverId: driverId),
    );
  }

  void _showDriverFeature(
    BuildContext context,
    String title,
    List<String> options,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverFeatureSheet(
        title: title,
        options: options,
      ),
    );
  }
}

class _DriverFeatureSheet extends StatelessWidget {
  const _DriverFeatureSheet({
    required this.title,
    required this.options,
  });

  final String title;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AvroDriverColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: EvikTypography.h3)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...options.map(
              (option) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: AvroDriverColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AvroDriverColors.border),
                ),
                child: Text(
                  option,
                  style: EvikTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AvroDriverColors.background,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AvroDriverColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: AvroDriverColors.grayHint,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: EvikTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: EvikTypography.bodySmall.copyWith(
                          color: AvroDriverColors.grayHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AvroDriverColors.grayHint,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverReviewsSheet extends ConsumerWidget {
  const _DriverReviewsSheet({required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(driverReviewsProvider(driverId));

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: AvroDriverColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Отзывы',
                      style: EvikTypography.h3,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AvroDriverColors.border),

            // Reviews content
            Expanded(
              child: reviewsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AvroDriverColors.error,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ошибка загрузки отзывов',
                        style: EvikTypography.h3.copyWith(
                          color: AvroDriverColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Попробуйте позже',
                        style: EvikTypography.bodyMedium.copyWith(
                          color: AvroDriverColors.grayHint,
                        ),
                      ),
                    ],
                  ),
                ),
                data: (reviews) {
                  if (reviews.items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.star_outline,
                            color: AvroDriverColors.grayHint,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Отзывов пока нет',
                            style: EvikTypography.h3.copyWith(
                              color: AvroDriverColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Первые отзывы появятся после завершения заказов',
                            style: EvikTypography.bodyMedium.copyWith(
                              color: AvroDriverColors.grayHint,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Stats header
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _ReviewStat(
                              label: 'Средний рейтинг',
                              value: reviews.ratingAverage > 0
                                  ? reviews.ratingAverage.toStringAsFixed(1)
                                  : '—',
                              icon: Icons.star,
                            ),
                            _ReviewStat(
                              label: 'Всего отзывов',
                              value: reviews.total.toString(),
                              icon: Icons.reviews,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AvroDriverColors.border),

                      // Reviews list
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: reviews.items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final review = reviews.items[index];
                            return _ReviewCard(review: review);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStat extends StatelessWidget {
  const _ReviewStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: AvroDriverColors.accent,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: EvikTypography.h2.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: EvikTypography.bodySmall.copyWith(
            color: AvroDriverColors.grayHint,
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroDriverColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AvroDriverColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.clientName ?? 'Клиент',
                  style: EvikTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.stars ? Icons.star : Icons.star_border,
                    size: 16,
                    color: AvroDriverColors.accent,
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (review.text.isNotEmpty) ...[
            Text(
              review.text,
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroDriverColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            _formatDate(review.createdAt),
            style: EvikTypography.bodySmall.copyWith(
              color: AvroDriverColors.grayHint,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
