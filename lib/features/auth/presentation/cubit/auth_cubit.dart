import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/vehicle_session.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../data/datasources/device_info_datasource.dart';
import '../../data/datasources/remote_auth_datasource.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository, this._deviceInfo) : super(const AuthInitial());

  final AuthRepository _authRepository;
  final DeviceInfoDatasource _deviceInfo;

  /// Load MAC or fallback device id and emit so the login form can show it (read-only).
  Future<void> loadMacAddress() async {
    try {
      final String id = await _deviceInfo.getDisplayDeviceIdentifier();
      if (!isClosed) emit(AuthMacLoaded(deviceIdentifier: id));
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AuthCubit.loadMacAddress error: $e\n$st');
      }
      if (!isClosed) emit(AuthError('Could not read MAC address.'));
    }
  }

  /// Pair with pairing code, then complete `/auth/device`. Emits [AuthAuthenticated] on success.
  Future<void> register(String pairingCode) async {
    final String code = pairingCode.trim();
    if (code.isEmpty) {
      emit(const AuthError('Please enter the pairing code.'));
      return;
    }

    emit(const AuthLoading());
    try {
      final VehicleSession session = await _authRepository.register(code);
      if (!isClosed) emit(AuthAuthenticated(session: session));
    } on AuthException catch (e) {
      if (!isClosed) emit(AuthError(e.message));
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AuthCubit.register error: $e\n$st');
      }
      if (!isClosed) {
        emit(AuthError(
          e.toString().contains('SocketException') || e.toString().contains('TimeoutException')
              ? 'Network error. Check connection and try again.'
              : 'Registration failed. Please try again.',
        ));
      }
    }
  }

  Future<void> logout() async {
    await _authRepository.clearSession();
    if (!isClosed) emit(const AuthInitial());
  }
}
