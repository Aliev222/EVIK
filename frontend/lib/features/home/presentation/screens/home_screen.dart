import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/bootstrap/app_bootstrap.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../map/data/yandex_map_provider.dart';
import '../../../map/presentation/widgets/yandex_map_view.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/repositories/order_repository.dart';
import '../../../order/presentation/state/order_state_notifier.dart';
import '../state/app_flow_notifier.dart';

class _UiText {
  static const h1 = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  static const h2 = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 23,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const body = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const caption = TextStyle(
    color: EvikColors.textSecondaryDark,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _phone = TextEditingController(text: '+7 (999) 123-45-67');
  final _otp = TextEditingController();
  final _addressSearch = TextEditingController();
  final _comment = TextEditingController();

  String _fromAddress = 'Р В РЎС™Р В РЎвЂўР РЋРІР‚В Р В РЎВР В Р’ВµР РЋР С“Р РЋРІР‚С™Р В РЎвЂўР В РЎвЂ”Р В РЎвЂўР В Р’В»Р В РЎвЂўР В Р’В¶Р В Р’ВµР В Р вЂ¦Р В РЎвЂР В Р’Вµ';
  String? _toAddress;
  bool _pickFrom = false;
  String _vehicleType = 'Р В Р Р‹Р В Р’ВµР В РўвЂР В Р’В°Р В Р вЂ¦';
  int _lockedWheels = 0;
  bool _running = true;
  String _tariff = 'Р В Р Р‹Р РЋРІР‚С™Р В Р’В°Р В Р вЂ¦Р В РўвЂР В Р’В°Р РЋР вЂљР РЋРІР‚С™';

  static const _suggestions = <String>[
    'Р В РІР‚С”Р В Р’ВµР РЋР С“Р В Р вЂ¦Р В Р’В°Р РЋР РЏ Р РЋРЎвЂњР В Р’В»Р В РЎвЂР РЋРІР‚В Р В Р’В°, 15',
    'Р В РЎв„ўР В РЎвЂР РЋР вЂљР В РЎвЂўР В Р вЂ Р В Р’В°, 78Р В РЎвЂ™',
    'Р В РЎС›Р В Р’В¦ Р вЂ™Р’В«Р В Р Р‹Р В РЎвЂўР В РЎвЂќР В РЎвЂўР В Р’В»Р вЂ™Р’В», Р В РІР‚С”Р В Р’ВµР РЋРІР‚С™Р В Р вЂ¦Р РЋР РЏР РЋР РЏ, 14',
    'Р В РЎвЂ™Р РЋР РЉР РЋР вЂљР В РЎвЂўР В РЎвЂ”Р В РЎвЂўР РЋР вЂљР РЋРІР‚С™, Р РЋРІР‚С™Р В Р’ВµР РЋР вЂљР В РЎВР В РЎвЂР В Р вЂ¦Р В Р’В°Р В Р’В» B',
    'Р В Р’В®Р В Р’В¶Р В Р вЂ¦Р РЋРІР‚в„–Р В РІвЂћвЂ“ Р В Р вЂ Р В РЎвЂўР В РЎвЂќР В Р’В·Р В Р’В°Р В Р’В»',
  ];

  static const _vehicleTypes = <String>[
    'Р В Р Р‹Р В Р’ВµР В РўвЂР В Р’В°Р В Р вЂ¦',
    'Р В РЎв„ўР РЋР вЂљР В РЎвЂўР РЋР С“Р РЋР С“Р В РЎвЂўР В Р вЂ Р В Р’ВµР РЋР вЂљ',
    'Р В РЎС™Р В РЎвЂР В Р вЂ¦Р В РЎвЂР В Р вЂ Р РЋР РЉР В Р вЂ¦',
    'Р В Р’В¤Р РЋРЎвЂњР РЋР вЂљР В РЎвЂ“Р В РЎвЂўР В Р вЂ¦'
  ];

  static const _tariffs = <_Tariff>[
    _Tariff('Р В Р Р‹Р РЋРІР‚С™Р В Р’В°Р В Р вЂ¦Р В РўвЂР В Р’В°Р РЋР вЂљР РЋРІР‚С™', 3900, '12 Р В РЎВР В РЎвЂР В Р вЂ¦'),
    _Tariff('Р В РЎв„ўР В РЎвЂўР В РЎВР РЋРІР‚С›Р В РЎвЂўР РЋР вЂљР РЋРІР‚С™', 4900, '10 Р В РЎВР В РЎвЂР В Р вЂ¦'),
    _Tariff('Р В Р’В­Р В РЎвЂќР РЋР С“Р В РЎвЂ”Р РЋР вЂљР В Р’ВµР РЋР С“Р РЋР С“', 6200, '7 Р В РЎВР В РЎвЂР В Р вЂ¦'),
  ];

  _Tariff get _activeTariff => _tariffs.firstWhere((t) => t.name == _tariff,
      orElse: () => _tariffs.first);

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _addressSearch.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _resetClient() {
    setState(() {
      _fromAddress = 'Р В РЎС™Р В РЎвЂўР РЋРІР‚В Р В РЎВР В Р’ВµР РЋР С“Р РЋРІР‚С™Р В РЎвЂўР В РЎвЂ”Р В РЎвЂўР В Р’В»Р В РЎвЂўР В Р’В¶Р В Р’ВµР В Р вЂ¦Р В РЎвЂР В Р’Вµ';
      _toAddress = null;
      _pickFrom = false;
      _vehicleType = 'Р В Р Р‹Р В Р’ВµР В РўвЂР В Р’В°Р В Р вЂ¦';
      _lockedWheels = 0;
      _running = true;
      _tariff = 'Р В Р Р‹Р РЋРІР‚С™Р В Р’В°Р В Р вЂ¦Р В РўвЂР В Р’В°Р РЋР вЂљР РЋРІР‚С™';
      _comment.clear();
    });
    ref.read(appFlowProvider.notifier).setClientStage(ClientHomeStage.idle);
  }

  void _submitOrder() {
    ref.read(orderStateNotifierProvider.notifier).submitOrder(
          const CreateOrderCommand(
            userId: 'demo-user',
            pickup: Coordinate(lat: 55.751244, lng: 37.618423),
            dropoff: Coordinate(lat: 55.761244, lng: 37.628423),
          ),
        );
    ref.read(appFlowProvider.notifier).startSearch();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);
    return Scaffold(
      backgroundColor: EvikColors.darkBackground,
      body: switch (flow.authStep) {
        AuthStep.role => const _RoleScreen(),
        AuthStep.phone => _PhoneScreen(controller: _phone),
        AuthStep.sms => _OtpScreen(controller: _otp),
        AuthStep.success => const _SuccessScreen(),
        AuthStep.app => _MainShell(
            fromAddress: _fromAddress,
            toAddress: _toAddress,
            pickFrom: _pickFrom,
            addressSearch: _addressSearch,
            comment: _comment,
            vehicleType: _vehicleType,
            lockedWheels: _lockedWheels,
            running: _running,
            selectedTariff: _tariff,
            suggestions: _suggestions,
            vehicleTypes: _vehicleTypes,
            tariffs: _tariffs,
            activeTariff: _activeTariff,
            onPickField: (value) => setState(() => _pickFrom = value),
            onPickSuggestion: (value) => setState(() {
              if (_pickFrom) {
                _fromAddress = value;
              } else {
                _toAddress = value;
              }
            }),
            onVehicleType: (value) => setState(() => _vehicleType = value),
            onLockedWheels: (value) =>
                setState(() => _lockedWheels = value.clamp(0, 4)),
            onRunning: (value) => setState(() => _running = value),
            onTariff: (value) => setState(() => _tariff = value),
            onReset: _resetClient,
            onSubmitOrder: _submitOrder,
          ),
      },
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell({
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.comment,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.suggestions,
    required this.vehicleTypes,
    required this.tariffs,
    required this.activeTariff,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReset,
    required this.onSubmitOrder,
  });

  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final TextEditingController comment;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final List<String> suggestions;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final _Tariff activeTariff;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReset;
  final VoidCallback onSubmitOrder;

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  bool _menuOpen = false;

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _closeMenu() => setState(() => _menuOpen = false);

  void _goTab(AppTab tab) {
    ref.read(appFlowProvider.notifier).setTab(tab);
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    final home = flow.isDriver
        ? _DriverHome(
            stage: flow.driverStage,
            fromAddress: widget.fromAddress,
            toAddress: widget.toAddress,
            vehicleType: widget.vehicleType,
            lockedWheels: widget.lockedWheels,
            running: widget.running,
            selectedTariff: widget.selectedTariff,
            tariffPrice: widget.activeTariff.price,
            comment: widget.comment.text,
          )
        : _ClientHome(
            stage: flow.clientStage,
            fromAddress: widget.fromAddress,
            toAddress: widget.toAddress,
            pickFrom: widget.pickFrom,
            addressSearch: widget.addressSearch,
            comment: widget.comment,
            vehicleType: widget.vehicleType,
            lockedWheels: widget.lockedWheels,
            running: widget.running,
            selectedTariff: widget.selectedTariff,
            suggestions: widget.suggestions,
            vehicleTypes: widget.vehicleTypes,
            tariffs: widget.tariffs,
            activeTariff: widget.activeTariff,
            onStartAddress: notifier.showAddressSelection,
            onConfirmAddress: notifier.confirmAddress,
            onPickField: widget.onPickField,
            onPickSuggestion: widget.onPickSuggestion,
            onVehicleType: widget.onVehicleType,
            onLockedWheels: widget.onLockedWheels,
            onRunning: widget.onRunning,
            onTariff: widget.onTariff,
            onReview: () =>
                notifier.setClientStage(ClientHomeStage.orderReview),
            onSubmitOrder: widget.onSubmitOrder,
            onRetry: notifier.retrySearch,
            onReset: widget.onReset,
          );

    final body = switch (flow.currentTab) {
      AppTab.home => home,
      AppTab.history => const _HistoryScreen(),
      AppTab.profile => _ProfileScreen(isDriver: flow.isDriver),
    };

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 8,
            left: 8,
            child: _GlassSurface(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(12),
              blurSigma: 12,
              tint: Colors.white.withValues(alpha: 0.56),
              child: IconButton(
                onPressed: _toggleMenu,
                icon: const Icon(Icons.menu, color: EvikColors.textPrimaryDark),
                tooltip: '\u041c\u0435\u043d\u044e',
              ),
            ),
          ),
          if (_menuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                child: Container(color: Colors.black.withValues(alpha: 0.38)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _GlassSurface(
                width: MediaQuery.of(context).size.width * 0.5,
                height: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 28, 12, 16),
                blurSigma: 16,
                tint: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(0),
                border: const Border(
                  right: BorderSide(color: EvikColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (flow.isDriver) ...[
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: EvikColors.surfaceLight,
                            child: Icon(Icons.person,
                                color: EvikColors.textPrimaryLight),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  flow.isDriver
                                      ? '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044f'
                                      : '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043a\u043b\u0438\u0435\u043d\u0442\u0430',
                                  style: _UiText.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              const Text(
                                  '\u0424\u043e\u0442\u043e \u0431\u0443\u0434\u0435\u0442 \u0438\u0437 \u0434\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u043e\u0432',
                                  style: _UiText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DrawerItem(
                        label: '\u0413\u043b\u0430\u0432\u043d\u0430\u044f',
                        icon: Icons.home_outlined,
                        onTap: () => _goTab(AppTab.home)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                        label: '\u041f\u0440\u043e\u0444\u0438\u043b\u044c',
                        icon: Icons.person_outline,
                        onTap: () => _goTab(AppTab.profile)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                        label: '\u0418\u0441\u0442\u043e\u0440\u0438\u044f',
                        icon: Icons.history,
                        onTap: () => _goTab(AppTab.history)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                      label:
                          '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438',
                      icon: Icons.settings_outlined,
                      onTap: () {
                        _closeMenu();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                '\u0420\u0430\u0437\u0434\u0435\u043b \u00ab\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438\u00bb \u0432 \u0440\u0430\u0437\u0440\u0430\u0431\u043e\u0442\u043a\u0435')));
                      },
                    ),
                    const SizedBox(height: 8),
                    _DrawerItem(
                      label:
                          '\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430',
                      icon: Icons.support_agent_outlined,
                      onTap: () {
                        _closeMenu();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                '\u0420\u0430\u0437\u0434\u0435\u043b \u00ab\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430\u00bb \u0432 \u0440\u0430\u0437\u0440\u0430\u0431\u043e\u0442\u043a\u0435')));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(
      {required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: EvikColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EvikColors.borderDark),
        ),
        child: Row(
          children: [
            Icon(icon, color: EvikColors.textPrimaryDark, size: 20),
            const SizedBox(width: 10),
            Text(label, style: _UiText.body),
          ],
        ),
      ),
    );
  }
}

class _RoleScreen extends ConsumerWidget {
  const _RoleScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              SizedBox(
                height: 330,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: -240,
                      left: -28,
                      right: -28,
                      child: Container(
                        height: 520,
                        decoration: BoxDecoration(
                          color: EvikColors.accent.withValues(alpha: 0.98),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 34,
                      child: Image.asset(
                        'assets/img/roleevik.png',
                        width: 320,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                  '\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0440\u043e\u043b\u044c',
                  textAlign: TextAlign.center,
                  style: _UiText.h1),
              const SizedBox(height: 8),
              const Text(
                '\u041c\u044b \u043d\u0430\u0441\u0442\u0440\u043e\u0438\u043c \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441 \u043f\u043e\u0434 \u0432\u0430\u0448 \u0441\u0446\u0435\u043d\u0430\u0440\u0438\u0439.',
                textAlign: TextAlign.center,
                style: _UiText.caption,
              ),
              const SizedBox(height: 16),
              _RoleCard(
                title: '\u041a\u043b\u0438\u0435\u043d\u0442',
                subtitle:
                    '\u0412\u044b\u0437\u0432\u0430\u0442\u044c \u044d\u0432\u0430\u043a\u0443\u0430\u0442\u043e\u0440',
                selected: flow.role == UserRole.client,
                onTap: () => notifier.selectRole(UserRole.client),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                title: '\u0412\u043e\u0434\u0438\u0442\u0435\u043b\u044c',
                subtitle:
                    '\u041f\u0440\u0438\u043d\u0438\u043c\u0430\u0442\u044c \u0437\u0430\u043a\u0430\u0437\u044b',
                selected: flow.role == UserRole.driver,
                onTap: () => notifier.selectRole(UserRole.driver),
              ),
              const SizedBox(height: 24),
              _ActionButton.primary(
                text:
                    '\u041f\u0440\u043e\u0434\u043e\u043b\u0436\u0438\u0442\u044c',
                enabled: flow.role != null,
                onTap: notifier.continueFromRole,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneScreen extends ConsumerWidget {
  const _PhoneScreen({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => ref.read(appFlowProvider.notifier).logout(),
            icon:
                const Icon(Icons.arrow_back, color: EvikColors.textPrimaryDark),
          ),
          const Spacer(flex: 2),
          const Text(
              '\u0412\u0445\u043e\u0434 \u043f\u043e \u043d\u043e\u043c\u0435\u0440\u0443 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0430',
              style: _UiText.h1),
          const SizedBox(height: 8),
          const Text(
              '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043d\u043e\u043c\u0435\u0440, \u043c\u044b \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u043c \u043a\u043e\u0434 \u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f.',
              style: _UiText.caption),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            style: _UiText.body,
            decoration: const InputDecoration(hintText: '+7 (___) ___-__-__'),
          ),
          const Spacer(flex: 3),
          _ActionButton.primary(
            text:
                '\u041f\u043e\u043b\u0443\u0447\u0438\u0442\u044c \u043a\u043e\u0434',
            onTap: () =>
                ref.read(appFlowProvider.notifier).submitPhone(controller.text),
          ),
        ],
      ),
    );
  }
}

class _OtpScreen extends ConsumerStatefulWidget {
  const _OtpScreen({required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<_OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<_OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(4, (_) => TextEditingController());
    _focusNodes = List.generate(4, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < 4; i++) {
        _controllers[i].text = i < chars.length ? chars[i] : '';
      }
      if (chars.length >= 4) {
        _focusNodes[3].unfocus();
      } else {
        _focusNodes[chars.length].requestFocus();
      }
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _onBackspace(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return;
    }
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  String get _code => _controllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => ref.read(appFlowProvider.notifier).logout(),
            icon:
                const Icon(Icons.arrow_back, color: EvikColors.textPrimaryDark),
          ),
          const Spacer(flex: 2),
          const Text(
              '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043a\u043e\u0434 \u0438\u0437 SMS',
              style: _UiText.h1),
          const SizedBox(height: 8),
          Text(
            '\u041a\u043e\u0434 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u043d\u0430 ${flow.phone.isEmpty ? '+7 (999) 123-45-67' : flow.phone}',
            style: _UiText.caption,
          ),
          const SizedBox(height: 24),
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 12),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      _onBackspace(index, event);
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: _UiText.h2,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: EvikColors.surfaceDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: _focusNodes[index].hasFocus
                                  ? EvikColors.borderLight
                                  : EvikColors.borderDark),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: _focusNodes[index].hasFocus
                                  ? EvikColors.borderLight
                                  : EvikColors.borderDark),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: EvikColors.borderLight),
                        ),
                      ),
                      onChanged: (value) => _onChanged(index, value),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  ref.read(appFlowProvider.notifier).backToPhoneEntry(),
              child: const Text(
                '\u0418\u0437\u043c\u0435\u043d\u0438\u0442\u044c \u043d\u043e\u043c\u0435\u0440 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0430',
                style: TextStyle(color: EvikColors.textPrimaryDark),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                ref.read(appFlowProvider.notifier).submitPhone(
                      flow.phone.isEmpty ? '+7 (999) 123-45-67' : flow.phone,
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '\u041a\u043e\u0434 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u043f\u043e\u0432\u0442\u043e\u0440\u043d\u043e',
                    ),
                  ),
                );
              },
              child: const Text(
                '\u041d\u0435 \u043f\u0440\u0438\u0448\u0451\u043b \u043a\u043e\u0434? \u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u0441\u043d\u043e\u0432\u0430',
                style: TextStyle(color: EvikColors.textPrimaryDark),
              ),
            ),
          ),
          const Spacer(flex: 3),
          _ActionButton.primary(
            text:
                '\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044c',
            enabled: _code.length == 4,
            onTap: () => ref.read(appFlowProvider.notifier).submitSms(_code),
          ),
        ],
      ),
    );
  }
}

class _SuccessScreen extends ConsumerWidget {
  const _SuccessScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 50, 24, 20),
      child: Column(
        children: [
          const Spacer(),
          const Icon(Icons.check_circle_outline,
              color: EvikColors.textPrimaryDark, size: 88),
          const SizedBox(height: 12),
          const Text('Р В РІР‚в„ўР РЋРІР‚В¦Р В РЎвЂўР В РўвЂ Р В Р вЂ Р РЋРІР‚в„–Р В РЎвЂ”Р В РЎвЂўР В Р’В»Р В Р вЂ¦Р В Р’ВµР В Р вЂ¦',
              style: TextStyle(
                color: EvikColors.textPrimaryDark,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              )),
          const Spacer(),
          _ActionButton.primary(
            text: 'Р В РЎСџР В Р’ВµР РЋР вЂљР В Р’ВµР В РІвЂћвЂ“Р РЋРІР‚С™Р В РЎвЂ Р В РЎвЂќ Р В РЎвЂќР В Р’В°Р РЋР вЂљР РЋРІР‚С™Р В Р’Вµ',
            onTap: () => ref.read(appFlowProvider.notifier).finishAuth(),
          ),
        ],
      ),
    );
  }
}

class _ClientHome extends StatelessWidget {
  const _ClientHome({
    required this.stage,
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.comment,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.suggestions,
    required this.vehicleTypes,
    required this.tariffs,
    required this.activeTariff,
    required this.onStartAddress,
    required this.onConfirmAddress,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReview,
    required this.onSubmitOrder,
    required this.onRetry,
    required this.onReset,
  });

  final ClientHomeStage stage;
  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final TextEditingController comment;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final List<String> suggestions;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final _Tariff activeTariff;
  final VoidCallback onStartAddress;
  final VoidCallback onConfirmAddress;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReview;
  final VoidCallback onSubmitOrder;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final overlay = switch (stage) {
      ClientHomeStage.idle => _Panel(
          child: _ActionButton.primary(
              text: 'Р В РІР‚в„ўР РЋРІР‚в„–Р В Р’В·Р В Р вЂ Р В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р РЋР РЉР В Р вЂ Р В Р’В°Р В РЎвЂќР РЋРЎвЂњР В Р’В°Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљ', onTap: onStartAddress),
        ),
      ClientHomeStage.addressSelection => _AddressPanel(
          fromAddress: fromAddress,
          toAddress: toAddress,
          pickFrom: pickFrom,
          addressSearch: addressSearch,
          suggestions: suggestions,
          onPickField: onPickField,
          onPickSuggestion: onPickSuggestion,
          onConfirmAddress: onConfirmAddress,
        ),
      ClientHomeStage.orderParameters => _OrderParamsPanel(
          vehicleType: vehicleType,
          lockedWheels: lockedWheels,
          running: running,
          comment: comment,
          selectedTariff: selectedTariff,
          vehicleTypes: vehicleTypes,
          tariffs: tariffs,
          onVehicleType: onVehicleType,
          onLockedWheels: onLockedWheels,
          onRunning: onRunning,
          onTariff: onTariff,
          onReview: onReview,
        ),
      ClientHomeStage.orderReview => _ReviewPanel(
          fromAddress: fromAddress,
          toAddress: toAddress ?? 'Р В РЎСљР В Р’Вµ Р В Р вЂ Р РЋРІР‚в„–Р В Р’В±Р РЋР вЂљР В Р’В°Р В Р вЂ¦ Р В Р’В°Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“',
          vehicleType: vehicleType,
          lockedWheels: lockedWheels,
          running: running,
          tariff: activeTariff,
          onSubmit: onSubmitOrder,
        ),
      ClientHomeStage.searching => const _SearchingPanel(),
      ClientHomeStage.noDrivers => _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Р В РЎСљР В Р’ВµР РЋРІР‚С™ Р В РўвЂР В РЎвЂўР РЋР С“Р РЋРІР‚С™Р РЋРЎвЂњР В РЎвЂ”Р В Р вЂ¦Р РЋРІР‚в„–Р РЋРІР‚В¦ Р В Р вЂ Р В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р В Р’ВµР В РІвЂћвЂ“',
                  style: TextStyle(
                      color: EvikColors.textPrimaryDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _ActionButton.primary(text: 'Р В РЎСџР В РЎвЂўР В Р вЂ Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљР В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В РЎвЂ”Р В РЎвЂўР В РЎвЂР РЋР С“Р В РЎвЂќ', onTap: onRetry),
              const SizedBox(height: 8),
              _ActionButton.cancel(text: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В Р’В°', onTap: onReset),
            ],
          ),
        ),
      ClientHomeStage.driverFound => _DriverFoundPanel(onCancel: onReset),
      ClientHomeStage.driverEnRoute => _DriverFoundPanel(onCancel: onReset),
      ClientHomeStage.driverArrived => _DriverFoundPanel(onCancel: onReset),
      ClientHomeStage.completed => _StatusPanel(
          title: 'Р В РІР‚вЂќР В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В· Р В Р’В·Р В Р’В°Р В Р вЂ Р В Р’ВµР РЋР вЂљР РЋРІвЂљВ¬Р РЋРІР‚ВР В Р вЂ¦',
          subtitle: 'Р В Р Р‹Р В РЎвЂ”Р В Р’В°Р РЋР С“Р В РЎвЂР В Р’В±Р В РЎвЂў, Р РЋРІР‚РЋР РЋРІР‚С™Р В РЎвЂў Р В Р вЂ Р РЋРІР‚в„–Р В Р’В±Р РЋР вЂљР В Р’В°Р В Р’В»Р В РЎвЂ EVIK.',
          primaryText: 'Р В РЎСљР В РЎвЂўР В Р вЂ Р РЋРІР‚в„–Р В РІвЂћвЂ“ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
          onPrimary: onReset,
        ),
    };

    return Stack(
      children: [
        const Positioned.fill(child: _MapLayer()),
        Positioned(left: 16, right: 16, bottom: 22, child: overlay),
      ],
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel({
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.suggestions,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onConfirmAddress,
  });

  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final List<String> suggestions;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final VoidCallback onConfirmAddress;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Р В РІР‚в„ўР РЋРІР‚в„–Р В Р’В±Р В РЎвЂўР РЋР вЂљ Р В Р’В°Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“Р В Р’В°',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: addressSearch,
              style: const TextStyle(color: EvikColors.textPrimaryDark),
              decoration: const InputDecoration(hintText: 'Р В РЎСџР В РЎвЂўР В РЎвЂР РЋР С“Р В РЎвЂќ Р В Р’В°Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“Р В Р’В°')),
          const SizedBox(height: 12),
          _AddressItem(
              title: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎвЂќР РЋРЎвЂњР В РўвЂР В Р’В°',
              value: fromAddress,
              selected: pickFrom,
              priority: false,
              onTap: () => onPickField(true)),
          const SizedBox(height: 8),
          _AddressItem(
              title: 'Р В РЎв„ўР РЋРЎвЂњР В РўвЂР В Р’В°',
              value: toAddress ?? 'Р В Р в‚¬Р В РЎвЂќР В Р’В°Р В Р’В¶Р В РЎвЂР РЋРІР‚С™Р В Р’Вµ Р В Р’В°Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“ Р В Р вЂ¦Р В Р’В°Р В Р’В·Р В Р вЂ¦Р В Р’В°Р РЋРІР‚РЋР В Р’ВµР В Р вЂ¦Р В РЎвЂР РЋР РЏ',
              selected: !pickFrom,
              priority: true,
              onTap: () => onPickField(false)),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView.separated(
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => InkWell(
                onTap: () => onPickSuggestion(suggestions[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: EvikColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EvikColors.borderDark)),
                  child: Text(suggestions[i],
                      style:
                          const TextStyle(color: EvikColors.textPrimaryDark)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton.primary(
            text: 'Р В РЎСџР В РЎвЂўР В РўвЂР РЋРІР‚С™Р В Р вЂ Р В Р’ВµР РЋР вЂљР В РўвЂР В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В Р’В°Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“',
            enabled: toAddress != null && toAddress!.trim().isNotEmpty,
            onTap: onConfirmAddress,
          ),
        ],
      ),
    );
  }
}

class _OrderParamsPanel extends StatelessWidget {
  const _OrderParamsPanel({
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.comment,
    required this.selectedTariff,
    required this.vehicleTypes,
    required this.tariffs,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReview,
  });

  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final TextEditingController comment;
  final String selectedTariff;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Р В РЎСџР В Р’В°Р РЋР вЂљР В Р’В°Р В РЎВР В Р’ВµР РЋРІР‚С™Р РЋР вЂљР РЋРІР‚в„– Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р В Р’В°',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vehicleTypes
                .map(
                  (t) => _VehicleTypeChip(
                    label: t,
                    selected: t == vehicleType,
                    onTap: () => onVehicleType(t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: EvikColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EvikColors.borderDark)),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Р В РІР‚вЂќР В Р’В°Р В Р’В±Р В Р’В»Р В РЎвЂўР В РЎвЂќР В РЎвЂР РЋР вЂљР В РЎвЂўР В Р вЂ Р В Р’В°Р В Р вЂ¦Р В Р вЂ¦Р РЋРІР‚в„–Р В Р’Вµ Р В РЎвЂќР В РЎвЂўР В Р’В»Р РЋРІР‚ВР РЋР С“Р В Р’В°',
                            style:
                                TextStyle(color: EvikColors.textPrimaryDark))),
                    IconButton(
                        onPressed: () => onLockedWheels(lockedWheels - 1),
                        icon: const Icon(Icons.remove,
                            color: EvikColors.textPrimaryDark)),
                    Text('$lockedWheels',
                        style: const TextStyle(
                            color: EvikColors.textPrimaryDark,
                            fontWeight: FontWeight.w700)),
                    IconButton(
                        onPressed: () => onLockedWheels(lockedWheels + 1),
                        icon: const Icon(Icons.add,
                            color: EvikColors.textPrimaryDark)),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(
                        child: Text('Р В РЎвЂ™Р В Р вЂ Р РЋРІР‚С™Р В РЎвЂўР В РЎВР В РЎвЂўР В Р’В±Р В РЎвЂР В Р’В»Р РЋР Р‰ Р В Р вЂ¦Р В Р’В° Р РЋРІР‚В¦Р В РЎвЂўР В РўвЂР РЋРЎвЂњ',
                            style:
                                TextStyle(color: EvikColors.textPrimaryDark))),
                    Switch(value: running, onChanged: onRunning),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
              controller: comment,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(color: EvikColors.textPrimaryDark),
              decoration: const InputDecoration(
                  hintText: 'Р В РЎв„ўР В РЎвЂўР В РЎВР В РЎВР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°Р РЋР вЂљР В РЎвЂР В РІвЂћвЂ“ Р В РЎвЂќ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р РЋРЎвЂњ (Р В Р вЂ¦Р В Р’ВµР В РЎвЂўР В Р’В±Р РЋР РЏР В Р’В·Р В Р’В°Р РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР Р‰Р В Р вЂ¦Р В РЎвЂў)')),
          const SizedBox(height: 10),
          ...tariffs.map((t) => GestureDetector(
                onTap: () => onTariff(t.name),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedTariff == t.name
                        ? EvikColors.accent
                        : EvikColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selectedTariff == t.name
                            ? EvikColors.borderLight
                            : EvikColors.borderDark),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(t.name,
                              style: TextStyle(
                                  color: selectedTariff == t.name
                                      ? EvikColors.textPrimaryLight
                                      : EvikColors.textPrimaryDark,
                                  fontWeight: FontWeight.w700))),
                      Text('${t.price} Р Р†РІР‚С™Р вЂ¦ Р Р†Р вЂљРЎС› ${t.eta}',
                          style: TextStyle(
                              color: selectedTariff == t.name
                                  ? EvikColors.textPrimaryLight
                                  : EvikColors.textSecondaryDark)),
                    ],
                  ),
                ),
              )),
          _ActionButton.primary(text: 'Р В РЎСџР РЋР вЂљР В РЎвЂўР В РўвЂР В РЎвЂўР В Р’В»Р В Р’В¶Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰', onTap: onReview),
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.tariff,
    required this.onSubmit,
  });

  final String fromAddress;
  final String toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final _Tariff tariff;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final estimate = _estimateOrderPrice(
      tariffName: tariff.name,
      basePrice: tariff.price,
      vehicleType: vehicleType,
      lockedWheels: lockedWheels,
      running: running,
    );

    Widget pair(String left, String right) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
                width: 110,
                child: Text(left,
                    style:
                        const TextStyle(color: EvikColors.textSecondaryDark))),
            Expanded(
                child: Text(right,
                    style: const TextStyle(
                        color: EvikColors.textPrimaryDark,
                        fontWeight: FontWeight.w600))),
          ]),
        );

    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Р В РЎСџР В РЎвЂўР В РўвЂР РЋРІР‚С™Р В Р вЂ Р В Р’ВµР РЋР вЂљР В Р’В¶Р В РўвЂР В Р’ВµР В Р вЂ¦Р В РЎвЂР В Р’Вµ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р В Р’В°',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pair('Р В РЎвЂєР РЋРІР‚С™Р В РЎвЂќР РЋРЎвЂњР В РўвЂР В Р’В°', fromAddress),
          pair('Р В РЎв„ўР РЋРЎвЂњР В РўвЂР В Р’В°', toAddress),
          pair('Р В РЎвЂ™Р В Р вЂ Р РЋРІР‚С™Р В РЎвЂў', vehicleType),
          pair('Р В РЎв„ўР В РЎвЂўР В Р’В»Р РЋРІР‚ВР РЋР С“Р В Р’В°', '$lockedWheels'),
          pair('Р В РЎСљР В Р’В° Р РЋРІР‚В¦Р В РЎвЂўР В РўвЂР РЋРЎвЂњ', running ? 'Р В РІР‚СњР В Р’В°' : 'Р В РЎСљР В Р’ВµР РЋРІР‚С™'),
          pair('\u0422\u0430\u0440\u0438\u0444', '${tariff.name}, ${tariff.price} \u20bd'),
          pair('\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c', '${estimate.totalPrice} \u20bd'),
          const SizedBox(height: 4),
          Text(
            '\u041f\u0440\u0435\u0434\u0432\u0430\u0440\u0438\u0442\u0435\u043b\u044c\u043d\u0430\u044f \u0441\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c: ${estimate.summary}',
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton.primary(text: 'Р В РІР‚в„ўР РЋРІР‚в„–Р В Р’В·Р В Р вЂ Р В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р РЋР РЉР В Р вЂ Р В Р’В°Р В РЎвЂќР РЋРЎвЂњР В Р’В°Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљ', onTap: onSubmit),
        ],
      ),
    );
  }
}

class _SearchingPanel extends StatelessWidget {
  const _SearchingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      EvikColors.textPrimaryDark))),
          SizedBox(height: 12),
          Text('Р В Р’ВР РЋРІР‚В°Р В Р’ВµР В РЎВ Р РЋР РЉР В Р вЂ Р В Р’В°Р В РЎвЂќР РЋРЎвЂњР В Р’В°Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљ...',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DriverFoundPanel extends StatelessWidget {
  const _DriverFoundPanel({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Р В РІР‚в„ўР В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР Р‰ Р В Р вЂ¦Р В Р’В°Р В РІвЂћвЂ“Р В РўвЂР В Р’ВµР В Р вЂ¦',
            style: TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
            ),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF4F4F4F), Color(0xFF1C1C1C)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.72),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Р В РЎвЂ™Р В Р’В»Р В Р’ВµР В РЎвЂќР РЋР С“Р В Р’ВµР В РІвЂћвЂ“ Р В Р Р‹Р В РЎВР В РЎвЂР РЋР вЂљР В Р вЂ¦Р В РЎвЂўР В Р вЂ ',
                        style: TextStyle(
                          color: EvikColors.textPrimaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Р В Р’В­Р В Р вЂ Р В Р’В°Р В РЎвЂќР РЋРЎвЂњР В Р’В°Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљ Hyundai HD78',
                        style: TextStyle(
                          color: EvikColors.textSecondaryDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _MiniInfo(
                            icon: Icons.star_rounded,
                            text: '4.9 Р РЋР вЂљР В Р’ВµР В РІвЂћвЂ“Р РЋРІР‚С™Р В РЎвЂР В Р вЂ¦Р В РЎвЂ“',
                          ),
                          _MiniInfo(
                            icon: Icons.route_rounded,
                            text: '3.4 Р В РЎвЂќР В РЎВ Р В РўвЂР В РЎвЂў Р В Р вЂ Р В Р’В°Р РЋР С“',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: _KeyInfoCard(
                  label: 'Р В РЎСџР РЋР вЂљР В РЎвЂР В Р’ВµР В РўвЂР В Р’ВµР РЋРІР‚С™ Р РЋРІР‚РЋР В Р’ВµР РЋР вЂљР В Р’ВµР В Р’В·',
                  value: '12 Р В РЎВР В РЎвЂР В Р вЂ¦',
                  accent: Color(0xFF19E5E5),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _KeyInfoCard(
                  label: 'Р В РЎСљР В РЎвЂўР В РЎВР В Р’ВµР РЋР вЂљ Р В РЎВР В Р’В°Р РЋРІвЂљВ¬Р В РЎвЂР В Р вЂ¦Р РЋРІР‚в„–',
                  value: 'Р В Р’В 336Р В Р Р‹Р В РІР‚в„ў 799',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Р В Р’В§Р РЋРІР‚С™Р В РЎвЂў Р В РЎвЂ”Р РЋР вЂљР В РЎвЂўР В РЎвЂР РЋР С“Р РЋРІР‚В¦Р В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™ Р РЋР С“Р В Р’ВµР В РІвЂћвЂ“Р РЋРІР‚РЋР В Р’В°Р РЋР С“',
                  style: TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Р В РІР‚в„ўР В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР Р‰ Р РЋРЎвЂњР В Р’В¶Р В Р’Вµ Р В Р’ВµР В РўвЂР В Р’ВµР РЋРІР‚С™ Р В РЎвЂќ Р В Р вЂ Р В Р’В°Р В РЎВ. Р В Р Р‹Р В Р’В»Р В Р’ВµР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’Вµ Р В Р’В·Р В Р’В° Р В Р вЂ Р РЋР вЂљР В Р’ВµР В РЎВР В Р’ВµР В Р вЂ¦Р В Р’ВµР В РЎВ Р В РЎвЂ”Р РЋР вЂљР В РЎвЂР В Р’В±Р РЋРІР‚в„–Р РЋРІР‚С™Р В РЎвЂР РЋР РЏ Р В РЎвЂ Р В Р вЂ¦Р В РЎвЂўР В РЎВР В Р’ВµР РЋР вЂљР В РЎвЂўР В РЎВ Р В РЎВР В Р’В°Р РЋРІвЂљВ¬Р В РЎвЂР В Р вЂ¦Р РЋРІР‚в„–, Р В РўвЂР В РЎвЂўР В РЎвЂ”Р В РЎвЂўР В Р’В»Р В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР Р‰Р В Р вЂ¦Р РЋРІР‚в„–Р РЋРІР‚В¦ Р В РўвЂР В Р’ВµР В РІвЂћвЂ“Р РЋР С“Р РЋРІР‚С™Р В Р вЂ Р В РЎвЂР В РІвЂћвЂ“ Р В РЎвЂўР РЋРІР‚С™ Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В° Р РЋР С“Р В Р’ВµР В РІвЂћвЂ“Р РЋРІР‚РЋР В Р’В°Р РЋР С“ Р В Р вЂ¦Р В Р’Вµ Р РЋРІР‚С™Р РЋР вЂљР В Р’ВµР В Р’В±Р РЋРЎвЂњР В Р’ВµР РЋРІР‚С™Р РЋР С“Р РЋР РЏ.',
                  style: TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ActionButton.cancel(
            text: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
            onTap: () => _showCancelWarning(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelWarning(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          title: const Text(
            'Р В РЎвЂєР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·?',
            style: TextStyle(
              color: EvikColors.textPrimaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Р В РІР‚СћР РЋР С“Р В Р’В»Р В РЎвЂ Р В Р вЂ Р В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР Р‰ Р РЋРЎвЂњР В Р’В¶Р В Р’Вµ Р В РЎвЂ”Р РЋР вЂљР В РЎвЂўР В Р’ВµР РЋРІР‚В¦Р В Р’В°Р В Р’В» Р В Р’В±Р В РЎвЂўР В Р’В»Р РЋР Р‰Р РЋРІвЂљВ¬Р В Р’Вµ Р В РЎвЂ”Р В РЎвЂўР В Р’В»Р В РЎвЂўР В Р вЂ Р В РЎвЂР В Р вЂ¦Р РЋРІР‚в„– Р В РЎвЂ”Р РЋРЎвЂњР РЋРІР‚С™Р В РЎвЂ Р В РЎвЂќ Р В Р вЂ Р В Р’В°Р В РЎВ, Р В РЎвЂўР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В Р’В° Р В РЎВР В РЎвЂўР В Р’В¶Р В Р’ВµР РЋРІР‚С™ Р В РЎвЂ”Р В РЎвЂўР В Р вЂ¦Р В РЎвЂР В Р’В·Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р РЋР вЂљР В Р’ВµР В РІвЂћвЂ“Р РЋРІР‚С™Р В РЎвЂР В Р вЂ¦Р В РЎвЂ“ Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°.',
            style: TextStyle(
              color: EvikColors.textSecondaryDark,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Р В РЎвЂєР РЋР С“Р РЋРІР‚С™Р В Р’В°Р РЋРІР‚С™Р РЋР Р‰Р РЋР С“Р РЋР РЏ'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: EvikColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Р В РІР‚СњР В Р’В°, Р В РЎвЂўР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      onCancel();
    }
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: EvikColors.textSecondaryDark),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: EvikColors.textSecondaryDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _KeyInfoCard extends StatelessWidget {
  const _KeyInfoCard({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final background = accent != null
        ? accent!.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = accent != null
        ? accent!.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.52);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.subtitle,
    required this.primaryText,
    required this.onPrimary,
  });

  final String title;
  final String subtitle;
  final String primaryText;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: EvikColors.textSecondaryDark)),
          const SizedBox(height: 12),
          _ActionButton.primary(text: primaryText, onTap: onPrimary),
        ],
      ),
    );
  }
}

class _DriverHome extends ConsumerWidget {
  const _DriverHome({
    required this.stage,
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.tariffPrice,
    required this.comment,
  });

  final DriverHomeStage stage;
  final String fromAddress;
  final String? toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final int tariffPrice;
  final String comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appFlowProvider.notifier);
    final online = stage != DriverHomeStage.offline;

    return Stack(
      children: [
        const Positioned.fill(child: _MapLayer()),
        Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: _Panel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: online
                          ? const Color(0xFF11D8CC).withValues(alpha: 0.38)
                          : Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                  child: Row(children: [
                  const Expanded(
                      child: Text('Р В Р Р‹Р РЋРІР‚С™Р В Р’В°Р РЋРІР‚С™Р РЋРЎвЂњР РЋР С“ Р В Р вЂ Р В РЎвЂўР В РўвЂР В РЎвЂР РЋРІР‚С™Р В Р’ВµР В Р’В»Р РЋР РЏ',
                          style: TextStyle(
                              color: EvikColors.textPrimaryDark,
                              fontWeight: FontWeight.w700))),
                  _DriverShiftInlineToggle(
                    online: online,
                    onChanged: notifier.toggleDriverOnline,
                  ),
                  ]),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _DriverShiftBadge(online: online),
                ),
                const SizedBox(height: 10),
                Text(
                  online
                      ? 'Р В РІР‚в„ўР РЋРІР‚в„– Р В РЎвЂ”Р РЋР вЂљР В РЎвЂР В Р вЂ¦Р В РЎвЂР В РЎВР В Р’В°Р В Р’ВµР РЋРІР‚С™Р В Р’Вµ Р В Р вЂ¦Р В РЎвЂўР В Р вЂ Р РЋРІР‚в„–Р В Р’Вµ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р РЋРІР‚в„– Р В РЎвЂ Р В Р вЂ Р В РЎвЂР В РўвЂР В Р вЂ¦Р РЋРІР‚в„– Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°Р В РЎВ Р В РЎвЂ”Р В РЎвЂўР В Р’В±Р В Р’В»Р В РЎвЂР В Р’В·Р В РЎвЂўР РЋР С“Р РЋРІР‚С™Р В РЎвЂ.'
                      : 'Р В РІР‚в„ўР В РЎвЂќР В Р’В»Р РЋР вЂ№Р РЋРІР‚РЋР В РЎвЂР РЋРІР‚С™Р В Р’Вµ Р РЋР С“Р В РЎВР В Р’ВµР В Р вЂ¦Р РЋРЎвЂњ, Р РЋРІР‚РЋР РЋРІР‚С™Р В РЎвЂўР В Р’В±Р РЋРІР‚в„– Р В Р вЂ¦Р В Р’В°Р РЋРІР‚РЋР В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р В РЎвЂ”Р В РЎвЂўР В Р’В»Р РЋРЎвЂњР РЋРІР‚РЋР В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р В Р вЂ¦Р В РЎвЂўР В Р вЂ Р РЋРІР‚в„–Р В Р’Вµ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р РЋРІР‚в„–.',
                  style: const TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                if (stage == DriverHomeStage.online)
                  _ActionButton.secondary(
                      text: 'Р В Р Р‹Р В РЎвЂР В РЎВР РЋРЎвЂњР В Р’В»Р В РЎвЂР РЋР вЂљР В РЎвЂўР В Р вЂ Р В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р В Р вЂ¦Р В РЎвЂўР В Р вЂ Р РЋРІР‚в„–Р В РІвЂћвЂ“ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.newOrder)),
                if (stage == DriverHomeStage.newOrder) ...[
                  _DriverOrderCard(
                    title: 'Р В РЎСљР В РЎвЂўР В Р вЂ Р РЋРІР‚в„–Р В РІвЂћвЂ“ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                    subtitle:
                        'Р В РЎСџР РЋР вЂљР В РЎвЂўР В Р вЂ Р В Р’ВµР РЋР вЂљР РЋР Р‰Р РЋРІР‚С™Р В Р’Вµ Р В РЎВР В Р’В°Р РЋР вЂљР РЋРІвЂљВ¬Р РЋР вЂљР РЋРЎвЂњР РЋРІР‚С™ Р В РЎвЂ Р В Р вЂ Р РЋР С“Р В Р’Вµ Р В РЎвЂ”Р В Р’В°Р РЋР вЂљР В Р’В°Р В РЎВР В Р’ВµР РЋРІР‚С™Р РЋР вЂљР РЋРІР‚в„–, Р В РЎвЂќР В РЎвЂўР РЋРІР‚С™Р В РЎвЂўР РЋР вЂљР РЋРІР‚в„–Р В Р’Вµ Р РЋРЎвЂњР В РЎвЂќР В Р’В°Р В Р’В·Р В Р’В°Р В Р’В» Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™.',
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    vehicleType: vehicleType,
                    lockedWheels: lockedWheels,
                    running: running,
                    selectedTariff: selectedTariff,
                    tariffPrice: tariffPrice,
                    comment: comment,
                  ),
                  const SizedBox(height: 12),
                  _ActionButton.primary(
                      text: 'Р В РЎСџР РЋР вЂљР В РЎвЂР В Р вЂ¦Р РЋР РЏР РЋРІР‚С™Р РЋР Р‰ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.accepted)),
                  const SizedBox(height: 8),
                  _ActionButton.cancel(
                      text: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎвЂќР В Р’В»Р В РЎвЂўР В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.online)),
                ],
                if (stage == DriverHomeStage.accepted ||
                    stage == DriverHomeStage.enRoute ||
                    stage == DriverHomeStage.arrived) ...[
                  _DriverOrderCard(
                    title: 'Р В РЎвЂ™Р В РЎвЂќР РЋРІР‚С™Р В РЎвЂР В Р вЂ Р В Р вЂ¦Р РЋРІР‚в„–Р В РІвЂћвЂ“ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                    subtitle:
                        'Р В РЎС™Р В Р’В°Р РЋР вЂљР РЋРІвЂљВ¬Р РЋР вЂљР РЋРЎвЂњР РЋРІР‚С™ Р РЋРЎвЂњР В Р’В¶Р В Р’Вµ Р В РЎвЂ”Р В РЎвЂўР РЋР С“Р РЋРІР‚С™Р РЋР вЂљР В РЎвЂўР В Р’ВµР В Р вЂ¦. Р В Р Р‹Р В Р’В»Р В Р’ВµР В РўвЂР РЋРЎвЂњР В РІвЂћвЂ“Р РЋРІР‚С™Р В Р’Вµ Р В РЎвЂ”Р В РЎвЂў Р В РЎвЂќР В Р’В°Р РЋР вЂљР РЋРІР‚С™Р В Р’Вµ Р В РўвЂР В РЎвЂў Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°.',
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    vehicleType: vehicleType,
                    lockedWheels: lockedWheels,
                    running: running,
                    selectedTariff: selectedTariff,
                    tariffPrice: tariffPrice,
                    comment: comment,
                  ),
                  const SizedBox(height: 12),
                  _ActionButton.cancel(
                    text: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎВР В Р’ВµР В Р вЂ¦Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                    onTap: () =>
                        notifier.setDriverStage(DriverHomeStage.online),
                  ),
                  const SizedBox(height: 8),
                  _ActionButton.primary(
                    text: 'Р В РІР‚вЂќР В Р’В°Р В Р вЂ Р В Р’ВµР РЋР вЂљР РЋРІвЂљВ¬Р В РЎвЂР РЋРІР‚С™Р РЋР Р‰ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·',
                    onTap: () =>
                        notifier.setDriverStage(DriverHomeStage.completed),
                  ),
                ],
                if (stage == DriverHomeStage.completed)
                  const _DriverDoneCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverOrderCard extends StatelessWidget {
  const _DriverOrderCard({
    required this.title,
    required this.subtitle,
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.tariffPrice,
    required this.comment,
  });

  final String title;
  final String subtitle;
  final String fromAddress;
  final String? toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final int tariffPrice;
  final String comment;

  @override
  Widget build(BuildContext context) {
    final destination = (toAddress == null || toAddress!.isEmpty)
        ? 'Р В РЎвЂ™Р В РўвЂР РЋР вЂљР В Р’ВµР РЋР С“ Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В° Р РЋРЎвЂњР РЋРІР‚С™Р В РЎвЂўР РЋРІР‚РЋР В Р вЂ¦Р РЋР РЏР В Р’ВµР РЋРІР‚С™Р РЋР С“Р РЋР РЏ'
        : toAddress!;
    final note = comment.trim().isEmpty ? 'Р В РІР‚ВР В Р’ВµР В Р’В· Р В РЎвЂќР В РЎвЂўР В РЎВР В РЎВР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°Р РЋР вЂљР В РЎвЂР РЋР РЏ' : comment.trim();
    final estimate = _estimateOrderPrice(
      tariffName: selectedTariff,
      basePrice: tariffPrice,
      vehicleType: vehicleType,
      lockedWheels: lockedWheels,
      running: running,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _DriverRouteRow(
            icon: Icons.trip_origin_rounded,
            label: 'Р В РЎвЂєР РЋРІР‚С™Р В РЎвЂќР РЋРЎвЂњР В РўвЂР В Р’В°',
            value: fromAddress,
          ),
          const SizedBox(height: 10),
          _DriverRouteRow(
            icon: Icons.flag_rounded,
            label: 'Р В РЎв„ўР РЋРЎвЂњР В РўвЂР В Р’В°',
            value: destination,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DriverInfoChip(label: 'Р В РЎвЂ™Р В Р вЂ Р РЋРІР‚С™Р В РЎвЂў', value: vehicleType),
              _DriverInfoChip(
                label: 'Р В РЎв„ўР В РЎвЂўР В Р’В»Р РЋРІР‚ВР РЋР С“Р В Р’В°',
                value: lockedWheels == 0 ? 'Р В РЎСљР В Р’ВµР РЋРІР‚С™ Р В Р’В±Р В Р’В»Р В РЎвЂўР В РЎвЂќР В РЎвЂР РЋР вЂљР В РЎвЂўР В Р вЂ Р В РЎвЂќР В РЎвЂ' : '$lockedWheels',
              ),
              _DriverInfoChip(
                label: 'Р В Р Р‹Р В РЎвЂўР РЋР С“Р РЋРІР‚С™Р В РЎвЂўР РЋР РЏР В Р вЂ¦Р В РЎвЂР В Р’Вµ',
                value: running ? 'Р В РЎСљР В Р’В° Р РЋРІР‚В¦Р В РЎвЂўР В РўвЂР РЋРЎвЂњ' : 'Р В РЎСљР В Р’Вµ Р В Р вЂ¦Р В Р’В° Р РЋРІР‚В¦Р В РЎвЂўР В РўвЂР РЋРЎвЂњ',
              ),
              _DriverInfoChip(label: 'Р В РЎС›Р В Р’В°Р РЋР вЂљР В РЎвЂР РЋРІР‚С›', value: selectedTariff),
              _DriverInfoChip(
                label: '\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c',
                value: '${estimate.totalPrice} \u20bd',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Р В РЎв„ўР В РЎвЂўР В РЎВР В РЎВР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°Р РЋР вЂљР В РЎвЂР В РІвЂћвЂ“ Р В РЎвЂќР В Р’В»Р В РЎвЂР В Р’ВµР В Р вЂ¦Р РЋРІР‚С™Р В Р’В°',
                  style: TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  note,
                  style: const TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverRouteRow extends StatelessWidget {
  const _DriverRouteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: EvikColors.textPrimaryDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: EvikColors.textSecondaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverInfoChip extends StatelessWidget {
  const _DriverInfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: EvikColors.textPrimaryDark,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: EvikColors.textSecondaryDark),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _DriverDoneCard extends StatelessWidget {
  const _DriverDoneCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Р В РІР‚вЂќР В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В· Р В Р’В·Р В Р’В°Р В Р вЂ Р В Р’ВµР РЋР вЂљР РЋРІвЂљВ¬Р РЋРІР‚ВР В Р вЂ¦',
            style: TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Р В РЎСџР В РЎвЂўР В Р’ВµР В Р’В·Р В РўвЂР В РЎвЂќР В Р’В° Р В Р’В·Р В Р’В°Р В Р вЂ Р В Р’ВµР РЋР вЂљР РЋРІвЂљВ¬Р В Р’ВµР В Р вЂ¦Р В Р’В°. Р В РЎС™Р В РЎвЂўР В Р’В¶Р В Р вЂ¦Р В РЎвЂў Р В Р вЂ Р В Р’ВµР РЋР вЂљР В Р вЂ¦Р РЋРЎвЂњР РЋРІР‚С™Р РЋР Р‰Р РЋР С“Р РЋР РЏ Р В Р вЂ  Р В РЎвЂўР В Р вЂ¦Р В Р’В»Р В Р’В°Р В РІвЂћвЂ“Р В Р вЂ¦ Р В РЎвЂ Р В Р’В¶Р В РўвЂР В Р’В°Р РЋРІР‚С™Р РЋР Р‰ Р РЋР С“Р В Р’В»Р В Р’ВµР В РўвЂР РЋРЎвЂњР РЋР вЂ№Р РЋРІР‚В°Р В РЎвЂР В РІвЂћвЂ“ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·.',
            style: TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverShiftInlineToggle extends StatelessWidget {
  const _DriverShiftInlineToggle({
    required this.online,
    required this.onChanged,
  });

  final bool online;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = online
        ? const Color(0xFF11D8CC)
        : EvikColors.textSecondaryDark;

    return GestureDetector(
      onTap: () => onChanged(!online),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 62,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: online ? accent : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: online
                ? accent.withValues(alpha: 0.24)
                : Colors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: online ? 0.12 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment:
                  online ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  online ? Icons.check_rounded : Icons.close_rounded,
                  size: 16,
                  color: online
                      ? const Color(0xFF11D8CC)
                      : EvikColors.textSecondaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverShiftBadge extends StatelessWidget {
  const _DriverShiftBadge({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final accent = online
        ? const Color(0xFF11D8CC)
        : EvikColors.textSecondaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'Р В РЎСљР В Р’В° Р РЋР С“Р В РЎВР В Р’ВµР В Р вЂ¦Р В Р’Вµ' : 'Р В РЎвЂєР РЋРІР‚С›Р РЋРІР‚С›Р В Р’В»Р В Р’В°Р В РІвЂћвЂ“Р В Р вЂ¦',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen();
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('Р В Р’ВР РЋР С“Р РЋРІР‚С™Р В РЎвЂўР РЋР вЂљР В РЎвЂР РЋР РЏ Р В Р’В·Р В Р’В°Р В РЎвЂќР В Р’В°Р В Р’В·Р В РЎвЂўР В Р вЂ ',
          style: TextStyle(color: EvikColors.textPrimaryDark)));
}

class _ProfileScreen extends ConsumerWidget {
  const _ProfileScreen({required this.isDriver});
  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 56),
          const Text(
            '\u041f\u0440\u043e\u0444\u0438\u043b\u044c',
            textAlign: TextAlign.center,
            style: _UiText.h1,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EvikColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EvikColors.borderDark),
            ),
            child: isDriver
                ? const Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: EvikColors.surfaceLight,
                        child: Icon(Icons.person,
                            color: EvikColors.textPrimaryLight),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '\u0418\u0432\u0430\u043d \u0418\u0432\u0430\u043d\u043e\u0432',
                                style: _UiText.h2),
                            SizedBox(height: 4),
                            Text(
                                '\u0420\u0435\u0439\u0442\u0438\u043d\u0433: 4.9',
                                style: _UiText.caption),
                          ],
                        ),
                      ),
                    ],
                  )
                : const Text(
                    '\u0418\u0432\u0430\u043d \u0418\u0432\u0430\u043d\u043e\u0432',
                    style: _UiText.h2),
          ),
          if (isDriver) ...[
            const SizedBox(height: 16),
            ...flow.documents.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DocRow(
                    name: e.key,
                    status: e.value,
                    onTap: () {
                      final next = switch (e.value) {
                        DocumentStatus.missing => DocumentStatus.pending,
                        DocumentStatus.pending => DocumentStatus.approved,
                        DocumentStatus.approved => DocumentStatus.rejected,
                        DocumentStatus.rejected => DocumentStatus.missing,
                      };
                      notifier.updateDocumentStatus(e.key, next);
                    },
                  ),
                )),
          ],
          const Spacer(),
          _ActionButton.danger(
              text:
                  '\u0412\u044b\u0439\u0442\u0438 \u0438\u0437 \u0430\u043a\u043a\u0430\u0443\u043d\u0442\u0430',
              onTap: notifier.logout),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow(
      {required this.name, required this.status, required this.onTap});
  final String name;
  final DocumentStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      DocumentStatus.missing => 'Р В РЎСљР В Р’Вµ Р В Р’В·Р В Р’В°Р В РЎвЂ“Р РЋР вЂљР РЋРЎвЂњР В Р’В¶Р В Р’ВµР В Р вЂ¦Р В РЎвЂў',
      DocumentStatus.pending => 'Р В РЎСљР В Р’В° Р В РЎвЂ”Р РЋР вЂљР В РЎвЂўР В Р вЂ Р В Р’ВµР РЋР вЂљР В РЎвЂќР В Р’Вµ',
      DocumentStatus.approved => 'Р В РЎСџР В РЎвЂўР В РўвЂР РЋРІР‚С™Р В Р вЂ Р В Р’ВµР РЋР вЂљР В Р’В¶Р В РўвЂР В Р’ВµР В Р вЂ¦Р В РЎвЂў',
      DocumentStatus.rejected => 'Р В РЎвЂєР РЋРІР‚С™Р В РЎвЂќР В Р’В»Р В РЎвЂўР В Р вЂ¦Р В Р’ВµР В Р вЂ¦Р В РЎвЂў',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: EvikColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EvikColors.borderDark)),
        child: Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(color: EvikColors.textPrimaryDark))),
          Text(text,
              style: const TextStyle(color: EvikColors.textSecondaryDark)),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      blurSigma: 16,
      tint: Colors.white.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(16),
      child: child,
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
    this.tint,
    this.border,
    this.blurSigma = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxBorder? border;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(18);

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint ?? Colors.white.withValues(alpha: 0.62),
              borderRadius: radius,
              border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AddressItem extends StatelessWidget {
  const _AddressItem(
      {required this.title,
      required this.value,
      required this.selected,
      required this.priority,
      required this.onTap});
  final String title;
  final String value;
  final bool selected;
  final bool priority;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(horizontal: 12, vertical: priority ? 14 : 10),
        decoration: BoxDecoration(
          color: priority ? EvikColors.surfaceLight : EvikColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? EvikColors.borderLight : EvikColors.borderDark),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: priority
                      ? EvikColors.textSecondaryLight
                      : EvikColors.textSecondaryDark,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: priority
                      ? EvikColors.textPrimaryLight
                      : EvikColors.textPrimaryDark,
                  fontWeight: priority ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard(
      {required this.title,
      required this.subtitle,
      required this.selected,
      required this.onTap});
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: selected ? 1.02 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? EvikColors.surfaceLight.withValues(alpha: 0.98)
                : EvikColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? EvikColors.borderLight : EvikColors.borderDark,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  style: _UiText.h2.copyWith(
                      fontSize: 30 / 1.6,
                      color: selected
                          ? EvikColors.textPrimaryLight
                          : EvikColors.textPrimaryDark)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: _UiText.caption.copyWith(
                      color: selected
                          ? EvikColors.textSecondaryLight
                          : EvikColors.textSecondaryDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleTypeChip extends StatelessWidget {
  const _VehicleTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF19E5E5)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF10C9C9)
                  : Colors.white.withValues(alpha: 0.52),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF19E5E5).withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton._({
    required this.text,
    required this.onTap,
    required this.bg,
    required this.fg,
    required this.border,
    this.enabled = true,
  });

  factory _ActionButton.primary(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: Colors.white,
        fg: EvikColors.textPrimaryDark,
        border: EvikColors.borderDark,
      );

  factory _ActionButton.secondary(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: EvikColors.surfaceDark,
        fg: EvikColors.textSecondaryDark,
        border: EvikColors.borderDark,
      );

  factory _ActionButton.cancel(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: EvikColors.danger.withValues(alpha: 0.16),
        fg: EvikColors.danger,
        border: EvikColors.danger.withValues(alpha: 0.45),
      );

  factory _ActionButton.danger(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton.cancel(text: text, onTap: onTap, enabled: enabled);

  final String text;
  final VoidCallback? onTap;
  final bool enabled;
  final Color bg;
  final Color fg;
  final Color border;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.97 : 1,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: widget.enabled ? widget.onTap : null,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: widget.bg,
              foregroundColor: widget.fg,
              disabledBackgroundColor: Colors.white,
              disabledForegroundColor: EvikColors.textPrimaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: widget.enabled ? widget.border : EvikColors.borderDark,
                ),
              ),
            ),
            child: Text(widget.text,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _MapLayer extends ConsumerStatefulWidget {
  const _MapLayer();
  @override
  ConsumerState<_MapLayer> createState() => _MapLayerState();
}

class _MapLayerState extends ConsumerState<_MapLayer> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    Future.microtask(() => ref.read(mapProviderProvider).init());
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(mapProviderProvider);
    if (provider is YandexMapProvider && provider.isAvailable) {
      return YandexMapView(
          initialLat: 55.751244,
          initialLng: 37.618423,
          initialZoom: 13,
          onMapCreated: provider.attachMap);
    }
    return const YandexMapView(
        initialLat: 55.751244, initialLng: 37.618423, initialZoom: 13);
  }
}


class _OrderPriceEstimate {
  const _OrderPriceEstimate({
    required this.totalPrice,
    required this.summary,
  });

  final int totalPrice;
  final String summary;
}

_OrderPriceEstimate _estimateOrderPrice({
  required String tariffName,
  required int basePrice,
  required String vehicleType,
  required int lockedWheels,
  required bool running,
}) {
  final vehicleSurcharge = switch (vehicleType) {
    '\u041a\u0440\u043e\u0441\u0441\u043e\u0432\u0435\u0440' => 600,
    '\u041c\u0438\u043d\u0438\u0432\u044d\u043d' => 900,
    '\u0424\u0443\u0440\u0433\u043e\u043d' => 1200,
    _ => 0,
  };
  final wheelsSurcharge = lockedWheels * 350;
  final runningSurcharge = running ? 0 : 800;
  final total = basePrice + vehicleSurcharge + wheelsSurcharge + runningSurcharge;
  final parts = <String>[
    '$basePrice \u20bd \u0431\u0430\u0437\u043e\u0432\u044b\u0439 \u0442\u0430\u0440\u0438\u0444 $tariffName',
    if (vehicleSurcharge > 0) '$vehicleSurcharge \u20bd \u0437\u0430 \u0442\u0438\u043f \u0430\u0432\u0442\u043e',
    if (wheelsSurcharge > 0) '$wheelsSurcharge \u20bd \u0437\u0430 \u0437\u0430\u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u0430\u043d\u043d\u044b\u0435 \u043a\u043e\u043b\u0451\u0441\u0430',
    if (runningSurcharge > 0) '$runningSurcharge \u20bd \u0435\u0441\u043b\u0438 \u0430\u0432\u0442\u043e \u043d\u0435 \u043d\u0430 \u0445\u043e\u0434\u0443',
  ];
  return _OrderPriceEstimate(
    totalPrice: total,
    summary: parts.join(' + '),
  );
}

class _Tariff {
  const _Tariff(this.name, this.price, this.eta);
  final String name;
  final int price;
  final String eta;
}
