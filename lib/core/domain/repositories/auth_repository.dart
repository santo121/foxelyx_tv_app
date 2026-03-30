import '../entities/vehicle_session.dart';

/// Pure Dart contract – no Flutter/HTTP imports.
/// Used to register buses and check if the current device/vehicle can show ads.
abstract class AuthRepository {
  /// Returns the stored session if the user is already logged in, else null.
  Future<VehicleSession?> getStoredSession();

  /// Register with server using device ID and vehicle registration number.
  /// On success, session is saved locally. Throws on invalid/unauthorized vehicle.
  Future<VehicleSession> register(String deviceId, String registrationNumber);

  /// Clear stored session (e.g. logout).
  Future<void> clearSession();
}
