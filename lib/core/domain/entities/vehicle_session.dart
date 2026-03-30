/// Pure Dart entity – no Flutter/HTTP imports.
/// Represents a bus/vehicle registered with the Kerala local transport app.
class VehicleSession {
  const VehicleSession({
    required this.deviceId,
    required this.registrationNumber,
    this.vehicleId,
    this.registeredAtMs,
  });

  final String deviceId;
  final String registrationNumber;
  final String? vehicleId;
  final int? registeredAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'registrationNumber': registrationNumber,
        'vehicleId': vehicleId,
        'registeredAtMs': registeredAtMs,
      };

  static VehicleSession fromJson(Map<String, dynamic> json) {
    return VehicleSession(
      deviceId: json['deviceId'] as String,
      registrationNumber: json['registrationNumber'] as String,
      vehicleId: json['vehicleId'] as String?,
      registeredAtMs: json['registeredAtMs'] as int?,
    );
  }
}
