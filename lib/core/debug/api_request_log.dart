import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Logs HTTP traffic in debug builds only (Flutter / Dart DevTools console).
/// Redacts common auth fields so secrets are not printed.
void debugLogHttpRequest(
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
}) {
  if (!kDebugMode) return;
  final StringBuffer b = StringBuffer('[API] → $method $uri');
  if (headers != null && headers.isNotEmpty) {
    b.writeln();
    b.write('  headers: $headers');
  }
  if (body != null && body.isNotEmpty) {
    b.writeln();
    b.write('  body: ${_redactSensitiveJson(body)}');
  }
  debugPrint(b.toString());
}

void debugLogHttpResponse(
  Uri uri,
  int statusCode, {
  String? body,
  String? note,
}) {
  if (!kDebugMode) return;
  final StringBuffer b = StringBuffer('[API] ← $statusCode $uri');
  if (note != null && note.isNotEmpty) {
    b.writeln();
    b.write('  $note');
  }
  if (body != null && body.isNotEmpty) {
    b.writeln();
    b.write('  body: ${_redactSensitiveJson(body)}');
  }
  debugPrint(b.toString());
}

String _redactSensitiveJson(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    final Object? redacted = _redactValue(decoded);
    return jsonEncode(redacted);
  } catch (_) {
    if (raw.length > 400) {
      return '${raw.substring(0, 400)}…';
    }
    return raw;
  }
}

Object? _redactValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> out = <String, Object?>{};
    for (final MapEntry<dynamic, dynamic> e in value.entries) {
      final String key = e.key.toString();
      if (_sensitiveKeys.contains(key)) {
        out[key] = '***';
      } else {
        out[key] = _redactValue(e.value);
      }
    }
    return out;
  }
  if (value is List) {
    return value.map(_redactValue).toList();
  }
  return value;
}

const Set<String> _sensitiveKeys = <String>{
  'secret',
  'pairingCode',
  'access_token',
  'refresh_token',
  'password',
  'authorization',
};
