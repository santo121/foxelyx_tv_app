/// Pure Dart entity – no Flutter/HTTP imports.
/// Represents a bus/vehicle registered with the Kerala local transport app.
class VehicleSession {
  const VehicleSession({
    required this.deviceId,
    required this.pairingCode,
    this.vehicleId,
    this.macAddress,
    this.registeredAtMs,
    this.accessToken,
    this.secret,
  });

  /// Device id issued by `/devices/pair` `data.deviceId`.
  /// Used for `/auth/device` re-auth with the stored secret.
  final String deviceId;

  /// Code entered at login to pair this device with a vehicle.
  final String pairingCode;

  /// Public device id from `/auth/device` `data.device.deviceId` (e.g. `DEV-6987`).
  /// Used for routes such as `GET /api/devices/:deviceId/playlist`.
  final String? vehicleId;

  /// Legacy: MAC from older API shapes. New sessions leave this null.
  final String? macAddress;
  final int? registeredAtMs;

  /// JWT from `/auth/device` `data.access_token` after successful pairing.
  final String? accessToken;
  final String? secret;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'deviceId': deviceId,
    'pairingCode': pairingCode,
    'vehicleId': vehicleId,
    'macAddress': macAddress,
    'registeredAtMs': registeredAtMs,
    'accessToken': accessToken,
    'secret': secret,
  };

  static VehicleSession fromJson(Map<String, dynamic> json) {
    final String pairing =
        json['pairingCode'] as String? ??
        json['registrationNumber'] as String? ??
        '';
    return VehicleSession(
      deviceId: json['deviceId'] as String,
      pairingCode: pairing,
      vehicleId: json['vehicleId'] as String?,
      macAddress: json['macAddress'] as String? ?? json['vehicleId'] as String?,
      registeredAtMs: json['registeredAtMs'] as int?,
      accessToken:
          json['accessToken'] as String? ?? json['access_token'] as String?,
      secret: json['secret'] as String?,
    );
  }

  VehicleSession copyWith({
    String? deviceId,
    String? pairingCode,
    String? vehicleId,
    String? macAddress,
    int? registeredAtMs,
    String? accessToken,
    String? secret,
  }) {
    return VehicleSession(
      deviceId: deviceId ?? this.deviceId,
      pairingCode: pairingCode ?? this.pairingCode,
      vehicleId: vehicleId ?? this.vehicleId,
      macAddress: macAddress ?? this.macAddress,
      registeredAtMs: registeredAtMs ?? this.registeredAtMs,
      accessToken: accessToken ?? this.accessToken,
      secret: secret ?? this.secret,
    );
  }
}
