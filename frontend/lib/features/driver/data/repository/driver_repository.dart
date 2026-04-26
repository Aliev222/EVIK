import '../../domain/entities/driver.dart';

abstract class DriverRepository {
  Future<Driver?> getDriver(String userId);
  Future<void> createDriver(Driver driver);
  Future<void> updateDriver(Driver driver);
  Future<void> updateDriverLocation(String userId, DriverLocation location);
  Future<void> setDriverOnlineStatus(String userId, bool isOnline);
  Stream<Driver?> watchDriver(String userId);
  Stream<List<Driver>> watchOnlineDrivers();
}
