import 'package:shared_preferences/shared_preferences.dart';

/// Считает суммарное время водителя на смене за текущие сутки.
///
/// Накопленное время (вне текущей активной смены) и начало текущей смены
/// хранятся локально, поэтому накопление переживает перезапуск приложения.
/// Как только суммарное время за сутки достигает [longShiftDuration],
/// однократно сигнализирует тревогу (звук «долго на смене»).
class DriverShiftTracker {
  DriverShiftTracker();

  static const Duration longShiftDuration = Duration(hours: 6);

  static const String _kDate = 'driver_shift.date';
  static const String _kAccumulated = 'driver_shift.accumulated_seconds';
  static const String _kShiftStart = 'driver_shift.shift_started_at';
  static const String _kAlerted = 'driver_shift.long_alerted';

  /// Момент начала текущей (незавершённой) смены, либо null если водитель не
  /// на смене. Восстанавливается при инициализации, чтобы пережить рестарт.
  DateTime? _shiftStartedAt;

  /// Накопленные секунды на смене за текущие сутки (без активной смены).
  int _accumulatedSeconds = 0;
  String _dayKey = '';
  bool _longShiftAlerted = false;

  bool get isOnShift => _shiftStartedAt != null;

  /// Восстанавливает состояние из локального хранилища.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _dayKey = _dateKey(DateTime.now());
    if (prefs.getString(_kDate) != _dayKey) {
      await _resetForNewDay(prefs);
      return;
    }
    _accumulatedSeconds = prefs.getInt(_kAccumulated) ?? 0;
    _longShiftAlerted = prefs.getBool(_kAlerted) ?? false;
    final startMs = prefs.getInt(_kShiftStart);
    if (startMs != null) {
      _shiftStartedAt = DateTime.fromMillisecondsSinceEpoch(startMs);
    }
  }

  /// Начало смены.
  Future<void> onShiftStarted() async {
    final prefs = await SharedPreferences.getInstance();
    _ensureDay(prefs);
    _shiftStartedAt ??= DateTime.now();
    await prefs.setInt(_kShiftStart, _shiftStartedAt!.millisecondsSinceEpoch);
  }

  /// Завершение смены: время активной смены прибавляется к общему за сутки.
  Future<void> onShiftEnded() async {
    final prefs = await SharedPreferences.getInstance();
    _ensureDay(prefs);
    final start = _shiftStartedAt;
    if (start != null) {
      _accumulatedSeconds += DateTime.now().difference(start).inSeconds;
      await prefs.setInt(_kAccumulated, _accumulatedSeconds);
    }
    _shiftStartedAt = null;
    await prefs.remove(_kShiftStart);
  }

  /// Проверяет, достигнуто ли суммарное время 6 часов; сигналит один раз за
  /// сутки. Возвращает true, если нужно воспроизвести звук «долго на смене».
  Future<bool> checkLongShift() async {
    final prefs = await SharedPreferences.getInstance();
    _ensureDay(prefs);
    if (_longShiftAlerted) return false;

    final total = totalShiftSeconds;
    if (total < longShiftDuration.inSeconds) return false;

    _longShiftAlerted = true;
    await prefs.setBool(_kAlerted, true);
    return true;
  }

  /// Суммарное время на смене за сутки в секундах (включая активную смену).
  int get totalShiftSeconds {
    var total = _accumulatedSeconds;
    final start = _shiftStartedAt;
    if (start != null) {
      total += DateTime.now().difference(start).inSeconds;
    }
    return total < 0 ? 0 : total;
  }

  void _ensureDay(SharedPreferences prefs) {
    final today = _dateKey(DateTime.now());
    if (_dayKey == today) return;
    // Наступил новый день — сбрасываем суточные счётчики.
    final wasOnShift = _shiftStartedAt != null;
    _dayKey = today;
    _accumulatedSeconds = 0;
    _longShiftAlerted = false;
    _shiftStartedAt = wasOnShift ? DateTime.now() : null;
    prefs
      ..setString(_kDate, today)
      ..setInt(_kAccumulated, 0)
      ..setBool(_kAlerted, false);
    if (_shiftStartedAt == null) {
      prefs.remove(_kShiftStart);
    } else {
      prefs.setInt(_kShiftStart, _shiftStartedAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _resetForNewDay(SharedPreferences prefs) async {
    _dayKey = _dateKey(DateTime.now());
    _accumulatedSeconds = 0;
    _longShiftAlerted = false;
    _shiftStartedAt = null;
    await Future.wait(<Future<bool>>[
      prefs.setString(_kDate, _dayKey),
      prefs.setInt(_kAccumulated, 0),
      prefs.setBool(_kAlerted, false),
      prefs.remove(_kShiftStart),
    ]);
  }

  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
