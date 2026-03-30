import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/domain/entities/vehicle_session.dart';

const String _keySession = 'kerala_bus_auth_session';

/// Reads/writes vehicle session to local storage (SharedPreferences).
class LocalAuthDatasource {
  LocalAuthDatasource(this._prefs);

  final SharedPreferences _prefs;

  Future<VehicleSession?> getSession() async {
    final String? raw = _prefs.getString(_keySession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      return VehicleSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(VehicleSession session) async {
    await _prefs.setString(_keySession, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() async {
    await _prefs.remove(_keySession);
  }
}
