import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/domain/entities/vehicle_session.dart';

/// Set to true when the backend API is ready; until then login is local-only.
const bool _useRealApi = false;

/// Base URL for Kerala bus registration API. Replace with your server URL.
const String _baseUrl = 'https://your-api.example.com/api';

/// Validates device ID + registration number. When [_useRealApi] is false,
/// accepts any non-empty registration locally (dummy mode). When true, calls server.
class RemoteAuthDatasource {
  Future<VehicleSession> register(String deviceId, String registrationNumber) {
    if (_useRealApi) {
      return _registerViaApi(deviceId, registrationNumber);
    }
    return _registerLocally(deviceId, registrationNumber);
  }

  /// Local-only: no API call. Accept any non-empty registration for now.
  Future<VehicleSession> _registerLocally(
    String deviceId,
    String registrationNumber,
  ) async {
    final String regNo = registrationNumber.trim().toUpperCase();
    if (regNo.isEmpty) {
      throw AuthException('Please enter a registration number.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return VehicleSession(
      deviceId: deviceId,
      registrationNumber: regNo,
      vehicleId: 'local-$regNo',
      registeredAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Real API call. Used when [_useRealApi] is true.
  Future<VehicleSession> _registerViaApi(
    String deviceId,
    String registrationNumber,
  ) async {
    final Uri url = Uri.parse('$_baseUrl/buses/register');
    final http.Response response = await http
        .post(
          url,
          headers: <String, String>{
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'deviceId': deviceId,
            'registrationNumber': registrationNumber.trim().toUpperCase(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      return VehicleSession(
        deviceId: body['deviceId'] as String? ?? deviceId,
        registrationNumber:
            body['registrationNumber'] as String? ?? registrationNumber,
        vehicleId: body['vehicleId'] as String?,
        registeredAtMs: body['registeredAtMs'] as int?,
      );
    }

    if (response.statusCode == 400) {
      throw AuthException('Invalid registration number or device.');
    }
    if (response.statusCode == 404 || response.statusCode == 403) {
      throw AuthException('Vehicle not registered with the service.');
    }
    throw AuthException(
      'Server error (${response.statusCode}). Please try again.',
    );
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
