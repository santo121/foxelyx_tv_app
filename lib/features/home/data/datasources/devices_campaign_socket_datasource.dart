import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../../../core/config/api_config.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../domain/campaign_playlist_socket.dart';

/// Socket.IO at `https://api.foxelyx.com` with namespace `/devices`.
/// [Authorization] uses the stored JWT (`access_token`).
/// Refreshes playlist on connect and on `campaign.updated` / `campaign.created`.
class DevicesCampaignSocketDatasource implements CampaignPlaylistSocket {
  DevicesCampaignSocketDatasource(this._auth);

  final AuthRepository _auth;

  socket_io.Socket? _socket;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _isConnecting = false;
  void Function()? _onPlaylistRefresh;
  static const Duration _reconnectInterval = Duration(seconds: 5);

  /// Namespace `/devices` — same host as REST ([ApiConfig.host]).
  static const String _socketIoUrl = ApiConfig.socketIoDevicesUrl;

  /// Call once when home is ready. [onPlaylistRefresh] runs after connect and on campaign events.
  @override
  Future<void> start({required void Function() onPlaylistRefresh}) async {
    if (_started) return;
    _started = true;
    _onPlaylistRefresh = onPlaylistRefresh;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_started || _isConnecting) return;
    final socket_io.Socket? existingSocket = _socket;
    if (existingSocket != null && existingSocket.connected) return;

    _isConnecting = true;
    final String? token = await _auth.getAccessToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('DevicesCampaignSocket: no access_token; skip connect.');
      }
      _isConnecting = false;
      _scheduleReconnect();
      return;
    }

    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;

    try {
      final socket_io.Socket socket = socket_io.io(
        _socketIoUrl,
        socket_io.OptionBuilder()
            .setTransports(<String>['websocket'])
            .setExtraHeaders(<String, dynamic>{
              'Authorization': 'Bearer $token',
            })
            .build(),
      );
      _socket = socket;

      void onCampaignEvent(dynamic _) => _notifyRefresh();

      socket.on('connect', (_) {
        _isConnecting = false;
        _cancelReconnectTimer();
        _notifyRefresh();
      });
      socket.on('campaign.updated', onCampaignEvent);
      socket.on('campaign.created', onCampaignEvent);
      socket.on('disconnect', (dynamic data) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket disconnected: $data');
        }
        _isConnecting = false;
        _scheduleReconnect();
      });
      socket.on('connect_error', (dynamic data) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket connect_error: $data');
        }
        _isConnecting = false;
        _scheduleReconnect();
      });
      socket.on('error', (dynamic data) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket error: $data');
        }
        _isConnecting = false;
        _scheduleReconnect();
      });
    } catch (e, st) {
      _isConnecting = false;
      _scheduleReconnect();
      if (kDebugMode) {
        // ignore: avoid_print
        print('DevicesCampaignSocket connect error: $e\n$st');
      }
    }
  }

  void _scheduleReconnect() {
    if (!_started) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(_reconnectInterval, () {
      _reconnectTimer = null;
      if (!_started) return;
      unawaited(_connect());
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _notifyRefresh() {
    final void Function()? cb = _onPlaylistRefresh;
    if (cb == null) return;
    scheduleMicrotask(cb);
  }

  @override
  Future<void> dispose() async {
    _started = false;
    _isConnecting = false;
    _onPlaylistRefresh = null;
    _cancelReconnectTimer();
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }
}
