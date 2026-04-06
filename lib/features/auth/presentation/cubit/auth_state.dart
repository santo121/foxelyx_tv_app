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

final class AuthMacLoaded extends AuthState {
  const AuthMacLoaded({required this.deviceIdentifier});

  /// Hardware MAC when readable; otherwise Android ID / iOS IDFV (or unavailable).
  final String deviceIdentifier;

  @override
  List<Object?> get props => [deviceIdentifier];
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
