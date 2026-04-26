import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tariff_model.dart';

class TariffRepository {
  const TariffRepository();

  Future<Tariff> getCurrentTariff() async {
    return _defaultTariff;
  }

  Future<void> updateTariff(Tariff tariff) async {
    // Tariff administration is owned by the backend; the app keeps a local
    // fallback until an HTTP endpoint is exposed.
  }

  Stream<Tariff> watchTariff() {
    return Stream<Tariff>.value(_defaultTariff);
  }
}

const _defaultTariff = Tariff(
  baseFare: 500.0,
  pricePerKm: 25.0,
  minimumFare: 800.0,
  vehicleMultipliers: VehicleMultipliers(
    light: 1.0,
    suv: 1.2,
    minibus: 1.5,
    truck: 2.0,
  ),
);

final tariffRepositoryProvider = Provider<TariffRepository>((ref) {
  return const TariffRepository();
});

final currentTariffProvider = FutureProvider<Tariff>((ref) {
  final repository = ref.watch(tariffRepositoryProvider);
  return repository.getCurrentTariff();
});

final watchTariffProvider = StreamProvider<Tariff>((ref) {
  final repository = ref.watch(tariffRepositoryProvider);
  return repository.watchTariff();
});

final tariffsProvider = Provider<AsyncValue<List<Tariff>>>((ref) {
  final tariffAsync = ref.watch(watchTariffProvider);

  return tariffAsync.when(
    data: (tariff) => AsyncValue.data([tariff]),
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});
