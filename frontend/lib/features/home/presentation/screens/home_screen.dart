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

  String _fromAddress = 'Моё местоположение';
  String? _toAddress;
  bool _pickFrom = false;
  String _vehicleType = 'Седан';
  int _lockedWheels = 0;
  bool _running = true;
  String _tariff = 'Стандарт';

  static const _suggestions = <String>[
    'Лесная улица, 15',
    'Кирова, 78А',
    'ТЦ «Сокол», Летняя, 14',
    'Аэропорт, терминал B',
    'Южный вокзал',
  ];

  static const _vehicleTypes = <String>[
    'Седан',
    'Кроссовер',
    'Минивэн',
    'Фургон'
  ];

  static const _tariffs = <_Tariff>[
    _Tariff('Стандарт', 3900, '12 мин'),
    _Tariff('Комфорт', 4900, '10 мин'),
    _Tariff('Экспресс', 6200, '7 мин'),
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
      _fromAddress = 'Моё местоположение';
      _toAddress = null;
      _pickFrom = false;
      _vehicleType = 'Седан';
      _lockedWheels = 0;
      _running = true;
      _tariff = 'Стандарт';
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
        ? _DriverHome(stage: flow.driverStage)
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
            onNext: () =>
                notifier.setClientStage(ClientHomeStage.driverEnRoute),
            onArrived: () =>
                notifier.setClientStage(ClientHomeStage.driverArrived),
            onComplete: () =>
                notifier.setClientStage(ClientHomeStage.completed),
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
            child: Container(
              decoration: BoxDecoration(
                color: EvikColors.darkBackground.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EvikColors.borderDark),
              ),
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
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5,
                height: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 28, 12, 16),
                decoration: const BoxDecoration(
                  color: EvikColors.darkBackground,
                  border:
                      Border(right: BorderSide(color: EvikColors.borderDark)),
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
          const Text('Вход выполнен',
              style: TextStyle(
                color: EvikColors.textPrimaryDark,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              )),
          const Spacer(),
          _ActionButton.primary(
            text: 'Перейти к карте',
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
    required this.onNext,
    required this.onArrived,
    required this.onComplete,
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
  final VoidCallback onNext;
  final VoidCallback onArrived;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final overlay = switch (stage) {
      ClientHomeStage.idle => _Panel(
          child: _ActionButton.primary(
              text: 'Вызвать эвакуатор', onTap: onStartAddress),
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
          toAddress: toAddress ?? 'Не выбран адрес',
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
              const Text('Нет доступных водителей',
                  style: TextStyle(
                      color: EvikColors.textPrimaryDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _ActionButton.primary(text: 'Повторить поиск', onTap: onRetry),
              const SizedBox(height: 8),
              _ActionButton.cancel(text: 'Отмена', onTap: onReset),
            ],
          ),
        ),
      ClientHomeStage.driverFound =>
        _DriverFoundPanel(onCancel: onReset, onNext: onNext),
      ClientHomeStage.driverEnRoute => _StatusPanel(
          title: 'Эвакуатор в пути',
          subtitle: 'Водитель едет к вам.',
          primaryText: 'Водитель прибыл',
          onPrimary: onArrived,
          secondaryText: 'Отменить',
          onSecondary: onReset,
        ),
      ClientHomeStage.driverArrived => _StatusPanel(
          title: 'Водитель прибыл',
          subtitle: 'Можно передавать автомобиль.',
          primaryText: 'Завершить заказ',
          onPrimary: onComplete,
          secondaryText: 'Отменить',
          onSecondary: onReset,
        ),
      ClientHomeStage.completed => _StatusPanel(
          title: 'Заказ завершён',
          subtitle: 'Спасибо, что выбрали EVIK.',
          primaryText: 'Новый заказ',
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
          const Text('Выбор адреса',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: addressSearch,
              style: const TextStyle(color: EvikColors.textPrimaryDark),
              decoration: const InputDecoration(hintText: 'Поиск адреса')),
          const SizedBox(height: 12),
          _AddressItem(
              title: 'Откуда',
              value: fromAddress,
              selected: pickFrom,
              priority: false,
              onTap: () => onPickField(true)),
          const SizedBox(height: 8),
          _AddressItem(
              title: 'Куда',
              value: toAddress ?? 'Укажите адрес назначения',
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
            text: 'Подтвердить адрес',
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
          const Text('Параметры заказа',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: vehicleTypes
                  .map((t) => ChoiceChip(
                      label: Text(t),
                      selected: t == vehicleType,
                      onSelected: (_) => onVehicleType(t)))
                  .toList()),
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
                        child: Text('Заблокированные колёса',
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
                        child: Text('Автомобиль на ходу',
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
                  hintText: 'Комментарий к заказу (необязательно)')),
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
                      Text('${t.price} ₽ • ${t.eta}',
                          style: TextStyle(
                              color: selectedTariff == t.name
                                  ? EvikColors.textPrimaryLight
                                  : EvikColors.textSecondaryDark)),
                    ],
                  ),
                ),
              )),
          _ActionButton.primary(text: 'Продолжить', onTap: onReview),
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
          const Text('Подтверждение заказа',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pair('Откуда', fromAddress),
          pair('Куда', toAddress),
          pair('Авто', vehicleType),
          pair('Колёса', '$lockedWheels'),
          pair('На ходу', running ? 'Да' : 'Нет'),
          pair('Тариф', '${tariff.name}, ${tariff.price} ₽'),
          const SizedBox(height: 10),
          _ActionButton.primary(text: 'Вызвать эвакуатор', onTap: onSubmit),
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
          Text('Ищем эвакуатор...',
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
  const _DriverFoundPanel({required this.onCancel, required this.onNext});
  final VoidCallback onCancel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Водитель найден',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('Рейтинг: 4.9',
              style: TextStyle(color: EvikColors.textSecondaryDark)),
          const Text('ETA: 12 мин',
              style: TextStyle(color: EvikColors.textSecondaryDark)),
          const Text('Расстояние: 3.4 км',
              style: TextStyle(color: EvikColors.textSecondaryDark)),
          const Text('Номер машины: РЗЗ6С8 799',
              style: TextStyle(color: EvikColors.textSecondaryDark)),
          const SizedBox(height: 12),
          _ActionButton.primary(text: 'Продолжить', onTap: onNext),
          const SizedBox(height: 8),
          _ActionButton.cancel(text: 'Отменить', onTap: onCancel),
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
    this.secondaryText,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String primaryText;
  final VoidCallback onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

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
          if (secondaryText != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            _ActionButton.cancel(text: secondaryText!, onTap: onSecondary),
          ],
        ],
      ),
    );
  }
}

class _DriverHome extends ConsumerWidget {
  const _DriverHome({required this.stage});
  final DriverHomeStage stage;

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
                Row(children: [
                  const Expanded(
                      child: Text('Статус водителя',
                          style: TextStyle(
                              color: EvikColors.textPrimaryDark,
                              fontWeight: FontWeight.w700))),
                  Switch(value: online, onChanged: notifier.toggleDriverOnline),
                ]),
                const SizedBox(height: 8),
                if (stage == DriverHomeStage.online)
                  _ActionButton.secondary(
                      text: 'Симулировать новый заказ',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.newOrder)),
                if (stage == DriverHomeStage.newOrder) ...[
                  _ActionButton.primary(
                      text: 'Принять заказ',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.accepted)),
                  const SizedBox(height: 8),
                  _ActionButton.cancel(
                      text: 'Отклонить',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.online)),
                ],
                if (stage == DriverHomeStage.accepted)
                  _ActionButton.primary(
                      text: 'Выехал к клиенту',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.enRoute)),
                if (stage == DriverHomeStage.enRoute)
                  _ActionButton.primary(
                      text: 'Прибыл',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.arrived)),
                if (stage == DriverHomeStage.arrived)
                  _ActionButton.primary(
                      text: 'Завершить заказ',
                      onTap: () =>
                          notifier.setDriverStage(DriverHomeStage.completed)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen();
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('История заказов',
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
      DocumentStatus.missing => 'Не загружено',
      DocumentStatus.pending => 'На проверке',
      DocumentStatus.approved => 'Подтверждено',
      DocumentStatus.rejected => 'Отклонено',
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
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: EvikColors.darkBackground.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EvikColors.borderDark),
      ),
      child: child,
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

class _Tariff {
  const _Tariff(this.name, this.price, this.eta);
  final String name;
  final int price;
  final String eta;
}
