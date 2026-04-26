import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/skeleton_card.dart';

enum WalletState { loading, empty, loaded, error }

class ClientWalletScreen extends StatefulWidget {
  const ClientWalletScreen({super.key});

  @override
  State<ClientWalletScreen> createState() => _ClientWalletScreenState();
}

class _ClientWalletScreenState extends State<ClientWalletScreen> {
  WalletState _state = WalletState.loaded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        title: Text(
          'Способы оплаты',
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
        actions: [
          _WalletStateAction(
            label: 'Empty',
            onTap: () => setState(() => _state = WalletState.empty),
          ),
          _WalletStateAction(
            label: 'Loading',
            onTap: () => setState(() => _state = WalletState.loading),
          ),
          _WalletStateAction(
            label: 'Error',
            onTap: () => setState(() => _state = WalletState.error),
          ),
          _WalletStateAction(
            label: 'Loaded',
            onTap: () => setState(() => _state = WalletState.loaded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1, color: EvikColors.gray200),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case WalletState.loading:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          children: const [
            SkeletonCard(height: 136),
            SkeletonCard(height: 136),
            SkeletonCard(height: 66),
            SkeletonCard(height: 84),
          ],
        );
      case WalletState.empty:
        return EmptyState(
          icon: Icons.credit_card_outlined,
          title: 'Нет способов оплаты',
          subtitle: 'Добавьте карту или другой способ',
          buttonText: 'Добавить карту',
          onButtonTap: _addPaymentMethod,
        );
      case WalletState.error:
        return ErrorState(
          message: 'Способы оплаты временно недоступны.',
          onRetry: () => setState(() => _state = WalletState.loading),
        );
      case WalletState.loaded:
        return _LoadedWalletContent(onAddCard: _addPaymentMethod);
    }
  }

  void _addPaymentMethod() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddCardBottomSheet(),
    );
  }
}

class _LoadedWalletContent extends StatelessWidget {
  const _LoadedWalletContent({required this.onAddCard});

  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('СОХРАНЁННЫЕ КАРТЫ', style: EvikTypography.sectionLabel),
          const SizedBox(height: 10),
          const _BankCard(
            cardMask: '•••• •••• •••• 4242',
            expiresAt: 'До 12/27',
            scheme: 'Visa',
            selected: true,
          ),
          const SizedBox(height: 12),
          const _BankCard(
            cardMask: '•••• •••• •••• 5678',
            expiresAt: 'До 08/26',
            scheme: 'MC',
            selected: false,
            darkSecondary: true,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onAddCard,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EvikColors.gray300),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: EvikColors.gray100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: EvikColors.accentOrange,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Добавить карту',
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('ПРОМОКОД', style: EvikTypography.sectionLabel),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: EvikColors.primaryWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EvikColors.gray200),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'EVIK2025',
                    style: EvikTypography.bodyLarge.copyWith(
                      color: EvikColors.gray500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: EvikButton(
                  text: 'Применить',
                  small: true,
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Промокод применен.'),
                        backgroundColor: EvikColors.successGreen,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F6EF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBCE6D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(
                  'Скидка 10% на следующую поездку',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('ПОСЛЕДНИЕ ПЛАТЕЖИ', style: EvikTypography.sectionLabel),
          const SizedBox(height: 10),
          const _PaymentRow(
            title: 'Эвакуация · Тверская',
            date: '23 апр',
            amount: '-2 300 ₽',
          ),
          const Divider(height: 18, color: EvikColors.gray200),
          const _PaymentRow(
            title: 'Эвакуация · Садовое',
            date: '19 апр',
            amount: '-1 800 ₽',
          ),
        ],
      ),
    );
  }
}

class _AddCardBottomSheet extends StatefulWidget {
  const _AddCardBottomSheet();

  @override
  State<_AddCardBottomSheet> createState() => _AddCardBottomSheetState();
}

class _AddCardBottomSheetState extends State<_AddCardBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _holderController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _cardController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Карта добавлена.'),
        backgroundColor: EvikColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Добавить карту', style: EvikTypography.h3),
                const SizedBox(height: 16),
                _CardInput(
                  controller: _cardController,
                  label: 'Номер карты',
                  hint: '0000-0000-0000-0000',
                  icon: Icons.credit_card,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                    const _GroupedDigitsFormatter(
                      groupSize: 4,
                      separator: '-',
                    ),
                  ],
                  validator: (value) {
                    final digits = value?.replaceAll('-', '') ?? '';
                    return digits.length == 16 ? null : 'Введите 16 цифр карты';
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CardInput(
                        controller: _expiryController,
                        label: 'Срок',
                        hint: 'MM/YY',
                        icon: Icons.calendar_today_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          const _GroupedDigitsFormatter(
                            groupSize: 2,
                            separator: '/',
                          ),
                        ],
                        validator: (value) {
                          final digits = value?.replaceAll('/', '') ?? '';
                          if (digits.length != 4) return 'MM/YY';
                          final month = int.tryParse(digits.substring(0, 2));
                          if (month == null || month < 1 || month > 12) {
                            return 'Месяц 01-12';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CardInput(
                        controller: _cvvController,
                        label: 'CVV',
                        hint: '123',
                        icon: Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        validator: (value) =>
                            (value?.length ?? 0) == 3 ? null : '3 цифры',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CardInput(
                  controller: _holderController,
                  label: 'Имя держателя',
                  hint: 'ALEXEY IVANOV',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value?.trim().length ?? 0) >= 3
                      ? null
                      : 'Введите имя держателя',
                ),
                const SizedBox(height: 18),
                EvikButton(
                  text: 'Добавить карту',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardInput extends StatelessWidget {
  const _CardInput({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: EvikColors.gray500),
        filled: true,
        fillColor: EvikColors.gray50,
        errorMaxLines: 2,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EvikColors.errorRed),
        ),
      ),
    );
  }
}

class _GroupedDigitsFormatter extends TextInputFormatter {
  const _GroupedDigitsFormatter({
    required this.groupSize,
    required this.separator,
  });

  final int groupSize;
  final String separator;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % groupSize == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _WalletStateAction extends StatelessWidget {
  const _WalletStateAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: EvikColors.accentOrange,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  const _BankCard({
    required this.cardMask,
    required this.expiresAt,
    required this.scheme,
    required this.selected,
    this.darkSecondary = false,
  });

  final String cardMask;
  final String expiresAt;
  final String scheme;
  final bool selected;
  final bool darkSecondary;

  @override
  Widget build(BuildContext context) {
    final base =
        darkSecondary ? const Color(0xFF3C475B) : const Color(0xFF111827);

    return Container(
      height: 136,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? EvikColors.accentOrange : Colors.transparent,
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -28,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 30,
                    height: 22,
                    decoration: BoxDecoration(
                      color: EvikColors.gray200.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.credit_card,
                        color: Color(0xFFF6C23E), size: 16),
                  ),
                  Text(
                    scheme,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: EvikColors.primaryWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                cardMask,
                style: EvikTypography.h3.copyWith(
                  color: EvikColors.primaryWhite,
                  fontSize: 30 / 2,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    expiresAt,
                    style: EvikTypography.bodySmall
                        .copyWith(color: const Color(0xFFCBD5E1)),
                  ),
                  if (selected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: EvikColors.accentOrange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 14, color: EvikColors.primaryWhite),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.title,
    required this.date,
    required this.amount,
  });

  final String title;
  final String date;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: EvikTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(date,
                  style: EvikTypography.bodySmall
                      .copyWith(color: EvikColors.gray500)),
            ],
          ),
        ),
        Text(amount,
            style: EvikTypography.h3
                .copyWith(fontSize: 30 / 2, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
