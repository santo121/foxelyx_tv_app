/// Single source of truth for Foxelyx API hosts (REST + Socket.IO).
///
/// Correct spelling is **foxelyx** — `api.foclyx.com` will not resolve (DNS failure).
abstract final class ApiConfig {
  ApiConfig._();

  static const String host = 'api.foxelyx.com';

  static const String baseUrl = 'https://api.foxelyx.com';

  /// Socket.IO client URL (namespace `/devices`).
  static const String socketIoDevicesUrl = 'https://api.foxelyx.com/devices';
}
