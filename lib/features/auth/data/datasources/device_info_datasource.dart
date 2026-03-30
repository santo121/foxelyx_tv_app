import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Provides a stable device identifier for bus registration (Android ID on Android).
class DeviceInfoDatasource {
  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// Returns a stable device identifier (Android: fingerprint; fallback: id).
  Future<String> getDeviceId() async {
    if (Platform.isAndroid) {
      final AndroidDeviceInfo android = await _plugin.androidInfo;
      return android.fingerprint.isNotEmpty
          ? android.fingerprint
          : android.id;
    }
    return 'unknown-device';
  }
}
