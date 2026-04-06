import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// Provides hardware MAC when available, otherwise a stable platform id (Android ID / iOS IDFV).
class DeviceInfoDatasource {
  static const MethodChannel _deviceChannel =
      MethodChannel('com.example.flutter_tv_app/device');

  /// Device id for session / API: MAC when readable, else Android ID / iOS IDFV.
  Future<String> getDeviceId() async {
    return getDisplayDeviceIdentifier();
  }

  /// Value shown on the login screen: hardware MAC when available, else a unique device id.
  Future<String> getDisplayDeviceIdentifier() async {
    if (Platform.isAndroid) {
      final String? mac = await _resolveHardwareMac();
      if (mac != null && mac.isNotEmpty) {
        return mac;
      }
      try {
        final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
        if (info.id.isNotEmpty) {
          return info.id;
        }
      } catch (_) {
        // Fall through.
      }
      return _unavailable;
    }
    if (Platform.isIOS) {
      try {
        final IosDeviceInfo info = await DeviceInfoPlugin().iosInfo;
        final String? idfv = info.identifierForVendor;
        if (idfv != null && idfv.isNotEmpty) {
          return idfv;
        }
      } catch (_) {
        // Fall through.
      }
      return _unavailable;
    }
    return 'unknown-device';
  }

  /// Prefer [getDisplayDeviceIdentifier]; kept for call sites that still say "MAC".
  Future<String> getMacAddress() async {
    return getDisplayDeviceIdentifier();
  }

  static const String _unavailable = 'Not available';

  /// Whether [value] is a colon-separated hardware MAC (not "Not available").
  static bool isHardwareMac(String value) {
    return _looksLikeMac(value);
  }

  Future<String?> _resolveHardwareMac() async {
    final String? fromSys = await _readMacFromSysfs();
    if (fromSys != null) {
      return fromSys;
    }
    try {
      final String? fromNative =
          await _deviceChannel.invokeMethod<String>('getMacAddress');
      if (fromNative != null && fromNative.isNotEmpty) {
        return fromNative;
      }
    } on PlatformException catch (_) {
      // Fall through.
    } catch (_) {
      // Missing channel, etc.
    }
    return null;
  }

  static Future<String?> _readMacFromSysfs() async {
    const List<String> interfaceNames = <String>['wlan0', 'eth0', 'wlan1'];
    for (final String name in interfaceNames) {
      try {
        final File f = File('/sys/class/net/$name/address');
        if (!await f.exists()) {
          continue;
        }
        final String mac = (await f.readAsString()).trim();
        if (_looksLikeMac(mac) && mac != '00:00:00:00:00:00') {
          return mac.toUpperCase();
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static bool _looksLikeMac(String s) {
    return RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(s.trim());
  }
}
