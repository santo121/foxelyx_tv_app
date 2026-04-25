/// Pure Dart – `data` from POST `/api/devices/pair` when `success` is true.
class DevicePairData {
  const DevicePairData({
    required this.deviceId,
    required this.secret,
    this.screenType,
    this.placement,
  });

  final String deviceId;
  final String secret;
  final String? screenType;
  final String? placement;

  /// Parses the API envelope's `data` map (not the full response body).
  factory DevicePairData.fromResponseData(Map<String, dynamic> json) {
    final String? deviceId = json['deviceId'] as String?;
    final String? secret = json['secret'] as String?;
    if (deviceId == null ||
        deviceId.isEmpty ||
        secret == null ||
        secret.isEmpty) {
      throw FormatException('pair response missing deviceId or secret');
    }
    return DevicePairData(
      deviceId: deviceId,
      secret: secret,
      screenType: json['screenType'] as String?,
      placement: json['placement'] as String?,
    );
  }
}
