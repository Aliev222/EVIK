enum DriverWorkState {
  offline,           // Водитель не в сети
  online,            // В сети, ожидает заказы
  hasActiveOrder,    // Принял заказ, едет к клиенту
  navigatingToDropoff, // Едет к точке назначения
}

extension DriverWorkStateExtension on DriverWorkState {
  String get displayName {
    switch (this) {
      case DriverWorkState.offline:
        return 'Не в сети';
      case DriverWorkState.online:
        return 'В сети';
      case DriverWorkState.hasActiveOrder:
        return 'К клиенту';
      case DriverWorkState.navigatingToDropoff:
        return 'К месту назначения';
    }
  }

  bool get isWorking {
    return this != DriverWorkState.offline;
  }

  bool get canReceiveOrders {
    return this == DriverWorkState.online;
  }

  bool get hasActiveOrder {
    return this == DriverWorkState.hasActiveOrder ||
           this == DriverWorkState.navigatingToDropoff;
  }
}