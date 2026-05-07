import '../../../../core/domain/entities/vehicle_session.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../../../core/utils/local_data_cleaner.dart';
import '../datasources/local_auth_datasource.dart';
import '../datasources/remote_auth_datasource.dart';

/// Implements [AuthRepository]: server validation + local persistence.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._local, this._remote, this._localDataCleaner);

  final LocalAuthDatasource _local;
  final RemoteAuthDatasource _remote;
  final LocalDataCleaner _localDataCleaner;
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  @override
  Future<VehicleSession?> getStoredSession() => _local.getSession();

  @override
  Future<VehicleSession> register(String pairingCode) async {
    final VehicleSession session = await _remote.register(pairingCode);
    await _local.saveSession(session);
    return session;
  }

  @override
  Future<void> clearSession() => _local.clearSession();

  @override
  Future<String?> getAccessToken() => _local.getAccessToken();

  @override
  Future<bool> refreshDeviceAuth() async {
    final VehicleSession? existing = await _local.getSession();
    if (existing == null) return false;
    final String? secret = existing.secret;
    if (secret == null || secret.isEmpty) return false;
    final String storedDeviceId = existing.deviceId.trim();
    final String fallbackDeviceId = (existing.vehicleId ?? '').trim();
    final bool looksLikeLegacyBackendUuid = _uuidPattern.hasMatch(storedDeviceId);
    final String apiDeviceId =
        looksLikeLegacyBackendUuid && fallbackDeviceId.isNotEmpty
        ? fallbackDeviceId
        : (storedDeviceId.isNotEmpty ? storedDeviceId : fallbackDeviceId);
    if (apiDeviceId.isEmpty) return false;
    try {
      final VehicleSession refreshed = await _remote.authenticateDevice(
        apiDeviceId: apiDeviceId,
        secret: secret,
        pairingCode: existing.pairingCode,
        screenType: existing.screenType,
        placement: existing.placement,
      );
      await _local.saveSession(refreshed);
      return true;
    } on AuthUnauthorizedException {
      await _local.clearSession();
      await _localDataCleaner.clearAllCachedData();
      return false;
    } catch (_) {
      return false;
    }
  }
}
