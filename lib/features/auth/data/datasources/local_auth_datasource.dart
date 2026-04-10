import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/domain/entities/vehicle_session.dart';

const String _keySession = 'kerala_bus_auth_session';
const String _keyAccessToken = 'foxelyx_access_token';
const String _keyMacAddress = 'foxelyx_device_mac';
const String _keyDeviceSecret = 'foxelyx_device_secret';

/// Reads/writes vehicle session to local storage (SharedPreferences).
class LocalAuthDatasource {
  LocalAuthDatasource(this._prefs);

  final SharedPreferences _prefs;

  Future<VehicleSession?> getSession() async {
    final String? raw = _prefs.getString(_keySession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final VehicleSession session = VehicleSession.fromJson(json);
      final String? secretFromPrefs = _prefs.getString(_keyDeviceSecret);
      if ((session.secret == null || session.secret!.isEmpty) &&
          secretFromPrefs != null &&
          secretFromPrefs.isNotEmpty) {
        return session.copyWith(secret: secretFromPrefs);
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(VehicleSession session) async {
    await _prefs.setString(_keySession, jsonEncode(session.toJson()));
    final String? token = session.accessToken;
    if (token != null && token.isNotEmpty) {
      await _prefs.setString(_keyAccessToken, token);
    } else {
      await _prefs.remove(_keyAccessToken);
    }
    final String? deviceRouteId = session.vehicleId ?? session.macAddress;
    if (deviceRouteId != null && deviceRouteId.isNotEmpty) {
      await _prefs.setString(_keyMacAddress, deviceRouteId);
    } else {
      await _prefs.remove(_keyMacAddress);
    }
    final String? secret = session.secret;
    if (secret != null && secret.isNotEmpty) {
      await _prefs.setString(_keyDeviceSecret, secret);
    } else {
      await _prefs.remove(_keyDeviceSecret);
    }
  }

  Future<void> clearSession() async {
    await _prefs.remove(_keySession);
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyMacAddress);
    await _prefs.remove(_keyDeviceSecret);
  }

  /// JWT persisted after `/auth/device`; use for sockets and authenticated calls.
  Future<String?> getAccessToken() async {
    final String? fromKey = _prefs.getString(_keyAccessToken);
    if (fromKey != null && fromKey.isNotEmpty) {
      return fromKey;
    }
    return (await getSession())?.accessToken;
  }
}
