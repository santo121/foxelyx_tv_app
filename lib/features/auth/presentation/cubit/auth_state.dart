import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/vehicle_session.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthDeviceIdLoaded extends AuthState {
  const AuthDeviceIdLoaded({required this.deviceId});

  final String deviceId;

  @override
  List<Object?> get props => [deviceId];
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.session});

  final VehicleSession session;

  @override
  List<Object?> get props => [session];
}

final class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
