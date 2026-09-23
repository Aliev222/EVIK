import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/client/presentation/widgets/location_picker_body.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';

/// Local request UI for roadside services. It intentionally stays independent
/// from the towing [OrderFlowNotifier] until partner dispatch is available.
class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  late final _RoadsideService _service = _RoadsideService.fromTitle(widget.title);
  final Map<String, _ServiceOption> _answers = {};
  MapLocation? _location;
  int _fuelLiters = 10;
  String _fuelComment = '';
  int _questionIndex = 0;
  bool _openedLocationInitially = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openedLocationInitially) return;
    _openedLocationInitially = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _chooseLocation());
  }

  @override
  void initState() {
    super.initState();
    _answers['fuel_liters'] = const _ServiceOption(
      'fuel_liters',
      '10 л',
      Icons.water_drop_rounded,
    );
  }

  Future<void> _chooseLocation() async {
    final location = await Navigator.of(context).push<MapLocation>(
      MaterialPageRoute(builder: (_) => _ServiceLocationPicker(initialLocation: _location)),
    );
    if (mounted && location != null) setState(() => _location = location);
  }

  void _continue() {
    if (_location == null) {
      _chooseLocation();
      return;
    }
    if (_questionIndex < _service.questions.length - 1) {
      setState(() => _questionIndex += 1);
    } else {
      setState(() => _questionIndex += 1);
    }
  }

  void _back() {
    if (_questionIndex > 0) {
      setState(() => _questionIndex -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _unavailable() => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Услуга временно недоступна. Попробуйте позже.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final review = _questionIndex == _service.questions.length;
    final question = review ? null : _service.questions[_questionIndex];
    final canContinue = review || (_location != null && _answers.containsKey(question!.id));
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        scrolledUnderElevation: 0,
        leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        title: Text(widget.title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: review
                    ? _Review(
                        service: _service,
                        location: _location!,
                        answers: _answers,
                        fuelComment: _fuelComment,
                        editLocation: _chooseLocation,
                        editAnswers: () => setState(() => _questionIndex = 0),
                      )
                    : _QuestionStep(
                        service: _service,
                        question: question!,
                        selected: _answers[question.id],
                        location: _location,
                        index: _questionIndex,
                        editLocation: _chooseLocation,
                        onSelect: (option) => setState(() => _answers[question.id] = option),
                        fuelLiters: _fuelLiters,
                        onFuelLitersChanged: (liters) => setState(() {
                          _fuelLiters = liters;
                          _answers['fuel_liters'] = _ServiceOption(
                            'fuel_liters',
                            '$liters л',
                            Icons.water_drop_rounded,
                          );
                        }),
                        fuelComment: _fuelComment,
                        onFuelCommentChanged: (comment) => _fuelComment = comment,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canContinue ? (review ? _unavailable : _continue) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvroClientColors.accent,
                    disabledBackgroundColor: AvroClientColors.surface,
                    foregroundColor: AvroClientColors.background,
                    disabledForegroundColor: AvroClientColors.textSecondary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(review ? 'Вызвать мастера' : 'Продолжить',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceLocationPicker extends ConsumerWidget {
  const _ServiceLocationPicker({this.initialLocation});
  final MapLocation? initialLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LocationPickerBody(
        title: 'Где нужна помощь?',
        addressLabel: 'Место оказания услуги',
        initialLocation: initialLocation,
        initialAddress: 'Выберите точку на карте',
        confirmText: 'Подтвердить адрес',
        onLocationConfirmed: (location) => Navigator.of(context).pop(location),
        onBack: () => Navigator.of(context).pop(),
      );
}

class _QuestionStep extends StatelessWidget {
  const _QuestionStep({
    required this.service, required this.question, required this.selected,
    required this.location, required this.index, required this.editLocation,
    required this.onSelect,
    required this.fuelLiters,
    required this.onFuelLitersChanged,
    required this.fuelComment,
    required this.onFuelCommentChanged,
  });
  final _RoadsideService service;
  final _ServiceQuestion question;
  final _ServiceOption? selected;
  final MapLocation? location;
  final int index;
  final VoidCallback editLocation;
  final ValueChanged<_ServiceOption> onSelect;
  final int fuelLiters;
  final ValueChanged<int> onFuelLitersChanged;
  final String fuelComment;
  final ValueChanged<String> onFuelCommentChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceHero(service: service),
          const SizedBox(height: 24),
          _LocationCard(location: location, onTap: editLocation),
          const SizedBox(height: 28),
          Text('ШАГ ${index + 1} ИЗ ${service.questions.length}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AvroClientColors.accent)),
          const SizedBox(height: 8),
          Text(question.title,
              style: GoogleFonts.inter(fontSize: 25, height: 1.12, fontWeight: FontWeight.w800, color: AvroClientColors.textPrimary)),
          if (question.hint != null) ...[
            const SizedBox(height: 8),
            Text(question.hint!, style: GoogleFonts.inter(fontSize: 15, height: 1.4, color: AvroClientColors.textSecondary)),
          ],
          const SizedBox(height: 18),
          if (question.options.isNotEmpty)
            ...question.options.map((option) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ChoiceCard(option: option, selected: selected?.id == option.id, onTap: () => onSelect(option)),
                )),
          if (question.usesFuelSlider) ...[
            const SizedBox(height: 4),
            _FuelLitersSlider(liters: fuelLiters, onChanged: onFuelLitersChanged),
          ],
          if (question.showsFuelComment) ...[
            const SizedBox(height: 8),
            Text('Комментарий к заказу', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              onChanged: onFuelCommentChanged,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Например: нужен АИ-95, подъезд со двора',
                filled: true,
                fillColor: AvroClientColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ],
      );
}

class _Review extends StatelessWidget {
  const _Review({required this.service, required this.location, required this.answers, required this.fuelComment, required this.editLocation, required this.editAnswers});
  final _RoadsideService service;
  final MapLocation location;
  final Map<String, _ServiceOption> answers;
  final String fuelComment;
  final VoidCallback editLocation;
  final VoidCallback editAnswers;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceHero(service: service),
          const SizedBox(height: 28),
          Text('Проверьте заявку', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Мастер увидит адрес и выбранные параметры.', style: GoogleFonts.inter(fontSize: 15, color: AvroClientColors.textSecondary)),
          const SizedBox(height: 20),
          _ReviewCard(title: 'Где нужна помощь', value: location.displayAddress, icon: Icons.location_on_outlined, onEdit: editLocation),
          const SizedBox(height: 12),
          _ReviewCard(
            title: 'Что выбрано',
            value: [
              ...service.questions.map((question) => answers[question.id]!.label),
              if (service.title == 'Подвоз топлива') answers['fuel_liters']!.label,
              if (fuelComment.trim().isNotEmpty) 'Комментарий: ${fuelComment.trim()}',
            ].join('\n'),
            icon: Icons.tune_rounded,
            onEdit: editAnswers,
          ),
        ],
      );
}

class _FuelLitersSlider extends StatelessWidget {
  const _FuelLitersSlider({required this.liters, required this.onChanged});

  final int liters;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        decoration: BoxDecoration(
          color: AvroClientColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Количество', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('$liters л', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AvroClientColors.accent)),
              ],
            ),
            Slider(
              value: liters.toDouble(),
              min: 5,
              max: 40,
              divisions: 7,
              label: '$liters л',
              activeColor: AvroClientColors.accent,
              onChanged: (value) => onChanged(value.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('5 л', style: GoogleFonts.inter(fontSize: 13, color: AvroClientColors.textSecondary)),
                Text('40 л', style: GoogleFonts.inter(fontSize: 13, color: AvroClientColors.textSecondary)),
              ],
            ),
          ],
        ),
      );

}

class _ServiceHero extends StatelessWidget {
  const _ServiceHero({required this.service});
  final _RoadsideService service;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AvroClientColors.accent.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset(service.asset, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(service.title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2), Text(service.subtitle, style: GoogleFonts.inter(fontSize: 14, color: AvroClientColors.textSecondary)),
        ])),
      ]);
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.onTap});
  final MapLocation? location;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final set = location != null;
    return Material(
      color: set ? AvroClientColors.accent.withValues(alpha: .08) : AvroClientColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Icon(set ? Icons.location_on_rounded : Icons.add_location_alt_outlined, color: AvroClientColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(set ? 'Адрес выбран' : 'Укажите место помощи', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(set ? location!.displayAddress : 'Выберите точку на карте', maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: AvroClientColors.textSecondary)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AvroClientColors.textSecondary),
        ])),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.option, required this.selected, required this.onTap});
  final _ServiceOption option;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AvroClientColors.accent.withValues(alpha: .08) : AvroClientColors.background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? AvroClientColors.accent : AvroClientColors.surface, width: selected ? 2 : 1)),
            child: Row(children: [
              Icon(option.icon, color: selected ? AvroClientColors.accent : AvroClientColors.textSecondary), const SizedBox(width: 14),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(option.label, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              ])),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? AvroClientColors.accent : AvroClientColors.textSecondary),
            ]),
          ),
        ),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.title, required this.value, required this.icon, required this.onEdit});
  final String title, value;
  final IconData icon;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity, padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AvroClientColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AvroClientColors.accent), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 13, color: AvroClientColors.textSecondary)), const SizedBox(height: 5),
            Text(value, style: GoogleFonts.inter(fontSize: 15, height: 1.35, fontWeight: FontWeight.w700)),
          ])),
          TextButton(onPressed: onEdit, child: const Text('Изменить')),
        ]),
      );
}

class _RoadsideService {
  const _RoadsideService({required this.title, required this.subtitle, required this.icon, required this.asset, required this.questions});
  final String title, subtitle;
  final IconData icon;
  final String asset;
  final List<_ServiceQuestion> questions;
  factory _RoadsideService.fromTitle(String title) => switch (title) {
        'Не заводится' => _startEngine,
        'Автоэлектрик' => _electrician,
        'Подвоз топлива' => _fuel,
        'Разблокировка' => _unlock,
        _ => _tires,
      };
  static const _tires = _RoadsideService(title: 'Шиномонтаж', subtitle: 'Выездной сервис', icon: Icons.tire_repair_rounded, asset: 'assets/img/services/tire_service.png', questions: [
    _ServiceQuestion('tire_issue', 'Что случилось с колесом?', 'Выберите наиболее подходящий вариант', [
      _ServiceOption('puncture', 'Прокол или спускает', Icons.tire_repair_rounded), _ServiceOption('replace', 'Нужно заменить колесо', Icons.autorenew_rounded), _ServiceOption('seasonal', 'Сезонная замена', Icons.settings_suggest_rounded), _ServiceOption('other', 'Другое', Icons.more_horiz_rounded),
    ]),
    _ServiceQuestion('wheel_count', 'Сколько колёс требует помощи?', null, [
      _ServiceOption('one', 'Одно колесо', Icons.looks_one_rounded), _ServiceOption('two', 'Два колеса', Icons.looks_two_rounded), _ServiceOption('four', 'Три или четыре колеса', Icons.apps_rounded),
    ]),
  ]);
  static const _startEngine = _RoadsideService(title: 'Не заводится', subtitle: 'Запуск двигателя', icon: Icons.battery_charging_full_rounded, asset: 'assets/img/services/jump_start.png', questions: [
    _ServiceQuestion('start_issue', 'Как ведёт себя автомобиль?', null, [
      _ServiceOption('battery', 'Разрядился аккумулятор', Icons.battery_alert_rounded), _ServiceOption('starter', 'Стартер не крутит', Icons.power_settings_new_rounded), _ServiceOption('unknown', 'Не знаю, нужна диагностика', Icons.help_outline_rounded),
    ]),
    _ServiceQuestion('engine_type', 'Какой двигатель?', null, [
      _ServiceOption('petrol', 'Бензиновый', Icons.local_gas_station_rounded), _ServiceOption('diesel', 'Дизельный', Icons.oil_barrel_rounded), _ServiceOption('hybrid', 'Гибрид или электро', Icons.electric_car_rounded),
    ]),
  ]);
  static const _electrician = _RoadsideService(title: 'Автоэлектрик', subtitle: 'Диагностика и ремонт', icon: Icons.bolt_rounded, asset: 'assets/img/services/auto_electrician.png', questions: [
    _ServiceQuestion('electric_issue', 'Что не работает?', 'Это поможет мастеру подготовиться', [
      _ServiceOption('battery', 'Аккумулятор или зарядка', Icons.battery_charging_full_rounded), _ServiceOption('lights', 'Свет или электрика салона', Icons.lightbulb_outline_rounded), _ServiceOption('alarm', 'Сигнализация или замки', Icons.lock_outline_rounded), _ServiceOption('unknown', 'Нужна диагностика', Icons.manage_search_rounded),
    ]),
  ]);
  static const _fuel = _RoadsideService(title: 'Подвоз топлива', subtitle: 'Быстрая доставка', icon: Icons.local_gas_station_rounded, asset: 'assets/img/services/fuel_delivery.png', questions: [
    _ServiceQuestion('fuel_type', 'Какое топливо привезти?', 'Выберите марку, а в комментарии можно уточнить пожелания', [
      _ServiceOption('92', 'Бензин АИ-92', Icons.local_gas_station_rounded), _ServiceOption('95', 'Бензин АИ-95', Icons.local_gas_station_rounded), _ServiceOption('diesel', 'Дизель', Icons.oil_barrel_rounded),
    ], showsFuelComment: true, usesFuelSlider: true),
  ]);
  static const _unlock = _RoadsideService(title: 'Разблокировка', subtitle: 'Авто и сигнализация', icon: Icons.lock_open_rounded, asset: 'assets/img/services/car_unlock.png', questions: [
    _ServiceQuestion('unlock_issue', 'Что заблокировано?', null, [
      _ServiceOption('door', 'Не открывается дверь', Icons.door_front_door_outlined),
      _ServiceOption('alarm', 'Сигнализация не отключается', Icons.notifications_off_outlined),
      _ServiceOption('key', 'Потерян или остался ключ', Icons.key_rounded),
    ]),
  ]);
}

class _ServiceQuestion {
  const _ServiceQuestion(
    this.id,
    this.title,
    this.hint,
    this.options, {
    this.showsFuelComment = false,
    this.usesFuelSlider = false,
  });
  final String id, title;
  final String? hint;
  final List<_ServiceOption> options;
  final bool showsFuelComment;
  final bool usesFuelSlider;
}
class _ServiceOption {
  const _ServiceOption(this.id, this.label, this.icon);
  final String id, label;
  final IconData icon;
}
