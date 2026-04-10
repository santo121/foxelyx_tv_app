import '../entities/vehicle_session.dart';

/// Pure Dart contract – no Flutter/HTTP imports.
/// Used to register buses and check if the current device/vehicle can show ads.
abstract class AuthRepository {
  /// Returns the stored session if the user is already logged in, else null.
  Future<VehicleSession?> getStoredSession();

  /// Pair with [pairingCode], then authenticate the device. Session is saved on success.
  Future<VehicleSession> register(String pairingCode);

  /// Clear stored session (e.g. logout).
  Future<void> clearSession();

  /// JWT from the last successful `/auth/device` response (WebSocket, API headers).
  /// Null if not logged in or legacy session without a token.
  Future<String?> getAccessToken();

  /// Re-authenticates current device using stored credentials (deviceId + secret).
  /// Returns true when a new valid auth session is persisted.
  Future<bool> refreshDeviceAuth();
}
