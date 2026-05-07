import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../auth/presentation/providers/new_auth_provider.dart';
import '../../../onboarding/presentation/screens/role_selection_screen.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: EvikColors.gray50,
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
            color: EvikColors.primaryBlack,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: EvikColors.primaryWhite,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: EvikColors.accentOrange,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'А',
                      style: EvikTypography.h3.copyWith(
                        color: EvikColors.primaryWhite,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Алексей Иванов',
                            style:
                                EvikTypography.h3.copyWith(fontSize: 34 / 2)),
                        const SizedBox(height: 2),
                        Text('+7 (999) 123-45-67',
                            style: EvikTypography.bodyMedium
                                .copyWith(color: EvikColors.gray600)),
                        const SizedBox(height: 4),
                        Text('★★★★☆ 4.0 · 7 поездок',
                            style: EvikTypography.bodySmall.copyWith(
                                color: const Color(0xFFF59E0B),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: EvikColors.gray200),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _ProfileTile(
                    icon: Icons.person_outline,
                    title: 'Личные данные',
                    subtitle: 'Имя, телефон, email',
                    onTap: () => _openPersonalData(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.shield_outlined,
                    title: 'Безопасность',
                    subtitle: 'Пароль, двухфакторная',
                    onTap: () => _openSecurity(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.notifications_none,
                    title: 'Уведомления',
                    subtitle: 'SMS, Push-уведомления',
                    onTap: () => _openNotifications(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.location_on_outlined,
                    title: 'Мои адреса',
                    subtitle: 'Домашний, рабочий',
                    onTap: () => _openAddresses(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Экстренная связь',
                    subtitle: '112 · ГАИ · Скорая',
                    onTap: () => _openEmergency(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.chat_bubble_outline,
                    title: 'Поддержка',
                    subtitle: 'Чат, email, телефон',
                    onTap: () => _openSupport(context),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(newAuthProvider.notifier).signOut();
                        // Очищаем выбранную роль чтобы попасть на экран выбора роли
                        ref
                            .read(selectedOnboardingRoleProvider.notifier)
                            .state = null;
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: EvikColors.primaryWhite,
                        foregroundColor: EvikColors.primaryBlack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Выйти из аккаунта',
                          style: EvikTypography.h3.copyWith(fontSize: 36 / 2)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPersonalData(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _PersonalDataBottomSheet(),
    );
  }

  void _openSecurity(BuildContext context) => _showFeatureSheet(
        context,
        'Безопасность',
        Icons.shield_outlined,
        const ['Смена пароля', 'SMS-подтверждение', 'Активные устройства'],
      );

  void _openNotifications(BuildContext context) => _showFeatureSheet(
        context,
        'Уведомления',
        Icons.notifications_none,
        const ['Push-уведомления', 'SMS о заказах', 'Новости и акции'],
      );

  void _openAddresses(BuildContext context) => _showFeatureSheet(
        context,
        'Мои адреса',
        Icons.location_on_outlined,
        const ['Домашний адрес', 'Рабочий адрес', 'Добавить избранный адрес'],
      );

  void _openEmergency(BuildContext context) => _showFeatureSheet(
        context,
        'Экстренная связь',
        Icons.health_and_safety_outlined,
        const ['112', 'ГИБДД', 'Скорая помощь'],
      );

  void _openSupport(BuildContext context) => _showFeatureSheet(
        context,
        'Поддержка',
        Icons.chat_bubble_outline,
        const ['Чат с оператором', 'Позвонить в поддержку', 'Написать email'],
      );

  void _showFeatureSheet(
    BuildContext context,
    String title,
    IconData icon,
    List<String> options,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureBottomSheet(
        title: title,
        icon: icon,
        options: options,
      ),
    );
  }
}

class _PersonalDataBottomSheet extends StatefulWidget {
  const _PersonalDataBottomSheet();

  @override
  State<_PersonalDataBottomSheet> createState() =>
      _PersonalDataBottomSheetState();
}

class _PersonalDataBottomSheetState extends State<_PersonalDataBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Алексей Иванов');
    _phoneController = TextEditingController(text: '+7 (999) 123-45-67');
    _emailController = TextEditingController(text: 'alexey@example.com');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заполните имя и телефон.'),
          backgroundColor: EvikColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Личные данные сохранены.'),
        backgroundColor: EvikColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return _SheetFrame(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Личные данные', style: EvikTypography.h3),
            const SizedBox(height: 16),
            _SheetTextField(
              controller: _nameController,
              label: 'Имя',
              icon: Icons.person_outline,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _SheetTextField(
              controller: _phoneController,
              label: 'Телефон',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _SheetTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EvikColors.accentOrange,
                  foregroundColor: EvikColors.primaryWhite,
                  disabledBackgroundColor: EvikColors.gray300,
                  disabledForegroundColor: EvikColors.gray500,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: EvikColors.primaryWhite,
                        ),
                      )
                    : Text(
                        'Сохранить',
                        style: EvikTypography.buttonText.copyWith(
                          color: EvikColors.primaryWhite,
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

class _FeatureBottomSheet extends StatelessWidget {
  const _FeatureBottomSheet({
    required this.title,
    required this.icon,
    required this.options,
  });

  final String title;
  final IconData icon;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: EvikColors.gray100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: EvikColors.accentOrange),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: EvikTypography.h3)),
              ],
            ),
            const SizedBox(height: 16),
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  minTileHeight: 54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: EvikColors.gray50,
                  title: Text(
                    option,
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: Text(
                    'Скоро',
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray500,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$option будет доступно позже.')),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: child,
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: 1,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: EvikColors.gray500),
        filled: true,
        fillColor: EvikColors.gray50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.gray200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.accentOrange),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
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
    return Material(
      color: EvikColors.primaryWhite,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: EvikColors.gray100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: EvikColors.gray800),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: EvikTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: EvikTypography.bodySmall
                            .copyWith(color: EvikColors.gray700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: EvikColors.gray600),
            ],
          ),
        ),
      ),
    );
  }
}
