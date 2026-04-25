import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/debug/api_request_log.dart';
import '../../../../core/domain/entities/device_pair_data.dart';
import '../../../../core/domain/entities/vehicle_session.dart';

/// Foxelyx API base (pair + device auth).
const String _baseUrl = ApiConfig.baseUrl;

/// Pairing code → device credentials → access token.
class RemoteAuthDatasource {
  Future<VehicleSession> register(String pairingCode) async {
    final String code = pairingCode.trim();
    if (code.isEmpty) {
      throw AuthException('Please enter the pairing code.');
    }

    final DevicePairData paired = await _pairDevice(code);

    return _authenticateDevice(
      apiDeviceId: paired.deviceId,
      secret: paired.secret,
      pairingCode: code,
      screenType: paired.screenType,
      placement: paired.placement,
    );
  }

  Future<VehicleSession> authenticateDevice({
    required String apiDeviceId,
    required String secret,
    required String pairingCode,
    String? screenType,
    String? placement,
  }) {
    return _authenticateDevice(
      apiDeviceId: apiDeviceId,
      secret: secret,
      pairingCode: pairingCode,
      screenType: screenType,
      placement: placement,
    );
  }

  Future<VehicleSession> _authenticateDevice({
    required String apiDeviceId,
    required String secret,
    required String pairingCode,
    String? screenType,
    String? placement,
  }) async {
    final Uri authUrl = Uri.parse('$_baseUrl/api/auth/device');
    final String authBodyJson = jsonEncode(<String, String>{
      'deviceId': apiDeviceId,
      'secret': secret,
    });
    debugLogHttpRequest(
      'POST',
      authUrl,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: authBodyJson,
    );
    final http.Response authResponse = await http
        .post(
          authUrl,
          headers: <String, String>{'Content-Type': 'application/json'},
          body: authBodyJson,
        )
        .timeout(const Duration(seconds: 5));
    debugLogHttpResponse(
      authUrl,
      authResponse.statusCode,
      body: authResponse.body,
    );

    final Map<String, dynamic> authBody = _decodeJsonMap(authResponse.body);
    final bool authOk = authBody['success'] as bool? ?? false;
    if (!authOk ||
        authResponse.statusCode < 200 ||
        authResponse.statusCode >= 300) {
      final String? err = authBody['error'] as String?;
      final String? msg = authBody['message'] as String?;
      throw AuthException(
        _sanitizeMessage(err ?? msg) ??
            'Authentication failed. Please try again.',
      );
    }

    final Map<String, dynamic>? authData =
        authBody['data'] as Map<String, dynamic>?;
    if (authData == null) {
      throw AuthException('Authentication failed. Please try again.');
    }

    final String? accessToken = authData['access_token'] as String?;
    final Map<String, dynamic>? device =
        authData['device'] as Map<String, dynamic>?;
    final String? devicePublicId = device?['deviceId'] as String?;

    if (accessToken == null ||
        accessToken.isEmpty ||
        devicePublicId == null ||
        devicePublicId.isEmpty) {
      throw AuthException('Authentication failed. Please try again.');
    }

    return VehicleSession(
      // Persist the device id issued by `/api/devices/pair` for re-auth calls.
      deviceId: apiDeviceId,
      pairingCode: pairingCode,
      vehicleId: devicePublicId,
      macAddress: null,
      registeredAtMs: DateTime.now().millisecondsSinceEpoch,
      accessToken: accessToken,
      secret: secret,
      screenType: screenType,
      placement: placement,
    );
  }

  Future<DevicePairData> _pairDevice(String pairingCode) async {
    final Uri url = Uri.parse('$_baseUrl/api/devices/pair');
    final String pairJson = jsonEncode(<String, String>{
      'pairingCode': pairingCode,
    });
    debugLogHttpRequest(
      'POST',
      url,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: pairJson,
    );
    final http.Response response = await http
        .post(
          url,
          headers: <String, String>{'Content-Type': 'application/json'},
          body: pairJson,
        )
        .timeout(const Duration(seconds: 5));
    debugLogHttpResponse(url, response.statusCode, body: response.body);

    final Map<String, dynamic> body = _decodeJsonMap(response.body);
    final bool ok = body['success'] as bool? ?? false;
    if (!ok || response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Invalid pairing code');
    }

    final Map<String, dynamic>? data = body['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw AuthException('Invalid pairing code');
    }
    try {
      return DevicePairData.fromResponseData(data);
    } on FormatException {
      throw AuthException('Invalid pairing code');
    }
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return <String, dynamic>{};
  }

  String? _sanitizeMessage(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
