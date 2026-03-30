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

  /// Load device ID and emit so the login form can show it (read-only).
  Future<void> loadDeviceId() async {
    try {
      final String deviceId = await _deviceInfo.getDeviceId();
      if (!isClosed) emit(AuthDeviceIdLoaded(deviceId: deviceId));
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AuthCubit.loadDeviceId error: $e\n$st');
      }
      if (!isClosed) emit(AuthError('Could not read device ID.'));
    }
  }

  /// Register with server using current device ID and vehicle registration number.
  /// On success, session is saved locally and [AuthAuthenticated] is emitted.
  Future<void> register(String registrationNumber) async {
    final String regNo = registrationNumber.trim();
    if (regNo.isEmpty) {
      emit(const AuthError('Please enter the vehicle registration number.'));
      return;
    }

    String deviceId;
    final AuthState current = state;
    if (current is AuthDeviceIdLoaded) {
      deviceId = current.deviceId;
    } else {
      emit(const AuthLoading());
      try {
        deviceId = await _deviceInfo.getDeviceId();
      } catch (e) {
        if (!isClosed) emit(AuthError('Could not read device ID.'));
        return;
      }
    }

    emit(const AuthLoading());
    try {
      final VehicleSession session =
          await _authRepository.register(deviceId, regNo);
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
