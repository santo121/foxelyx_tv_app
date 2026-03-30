import '../../../../core/domain/entities/vehicle_session.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../datasources/local_auth_datasource.dart';
import '../datasources/remote_auth_datasource.dart';

/// Implements [AuthRepository]: server validation + local persistence.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._local, this._remote);

  final LocalAuthDatasource _local;
  final RemoteAuthDatasource _remote;

  @override
  Future<VehicleSession?> getStoredSession() => _local.getSession();

  @override
  Future<VehicleSession> register(
    String deviceId,
    String registrationNumber,
  ) async {
    final VehicleSession session =
        await _remote.register(deviceId, registrationNumber);
    await _local.saveSession(session);
    return session;
  }

  @override
  Future<void> clearSession() => _local.clearSession();
}
