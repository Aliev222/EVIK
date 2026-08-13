import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/features/account/presentation/providers/account_deletion_provider.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

/// Card with privacy policy and terms of service links.
class LegalLinksTile extends StatelessWidget {
  const LegalLinksTile({
    super.key,
    required this.backgroundColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.iconColor,
  });

  final Color backgroundColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final Color iconColor;

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Failed to open $url: $error');
    }
  }

  Widget _row({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String url,
  }) {
    return InkWell(
      onTap: () => _openLink(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textPrimaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: textSecondaryColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _row(
            context: context,
            icon: Icons.privacy_tip_outlined,
            title: 'Политика конфиденциальности',
            url: AppConstants.privacyPolicyUrl,
          ),
          Divider(
            height: 1,
            color: textSecondaryColor.withValues(alpha: 0.2),
          ),
          _row(
            context: context,
            icon: Icons.assignment_outlined,
            title: 'Условия использования',
            url: AppConstants.termsOfServiceUrl,
          ),
        ],
      ),
    );
  }
}

/// Destructive tile that deletes the current user's account.
/// Guards, out-of-wallet balances and active orders produce a 409,
/// whose backend message is shown to the user.
class DeleteAccountEntry extends ConsumerStatefulWidget {
  const DeleteAccountEntry({
    super.key,
    required this.backgroundColor,
    required this.destructiveColor,
    required this.warningMessage,
    this.iconColor,
  });

  final Color backgroundColor;
  final Color destructiveColor;
  final String warningMessage;
  final Color? iconColor;

  @override
  ConsumerState<DeleteAccountEntry> createState() => _DeleteAccountEntryState();
}

class _DeleteAccountEntryState extends ConsumerState<DeleteAccountEntry> {
  Future<void> _onDeletePressed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аккаунт'),
        content: Text(widget.warningMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Удалить',
              style: TextStyle(
                color: widget.destructiveColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(accountDeletionProvider.notifier);
    notifier.reset();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    await notifier.deleteAccount();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final deletionState = ref.read(accountDeletionProvider);
    switch (deletionState.status) {
      case AccountDeletionStatus.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аккаунт удалён')),
        );
        ref.read(authProvider.notifier).signOut();
      case AccountDeletionStatus.conflict:
      case AccountDeletionStatus.error:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Не удалось удалить аккаунт'),
            content: Text(
              deletionState.message ?? 'Попробуйте ещё раз позже.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      case AccountDeletionStatus.idle:
      case AccountDeletionStatus.loading:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.destructiveColor.withValues(alpha: 0.45),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onDeletePressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete_outline,
                  color: widget.iconColor ?? widget.destructiveColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Удалить аккаунт',
                  style: TextStyle(
                    color: widget.destructiveColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}