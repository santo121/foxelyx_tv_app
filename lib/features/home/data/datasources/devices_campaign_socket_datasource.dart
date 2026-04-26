import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../../../core/config/api_config.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../domain/campaign_playlist_socket.dart';

/// Socket.IO at `https://api.foxelyx.com` with namespace `/devices`.
/// [Authorization] uses the stored JWT (`access_token`).
/// Refreshes playlist on connect and on create/update ad events.
class DevicesCampaignSocketDatasource implements CampaignPlaylistSocket {
  DevicesCampaignSocketDatasource(this._auth);

  final AuthRepository _auth;

  socket_io.Socket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _started = false;
  bool _isConnecting = false;
  bool _isRefreshingAuth = false;
  int _failedConnectAttempts = 0;
  void Function()? _onPlaylistRefresh;
  static const Duration _reconnectInterval = Duration(seconds: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const int _maxAttemptsBeforeReauth = 3;
  static const Set<String> _playlistRefreshEvents = <String>{
    'campaign.updated',
    'campaign.created',
    'campaign.deleted',
    'campaign.removed',
    'campaign.update',
    'campaign.create',
    'campaign.delete',
    'campaign.remove',
    'playlist.updated',
    'playlist.created',
    'playlist.deleted',
    'playlist.removed',
    'playlist.update',
    'playlist.create',
    'playlist.delete',
    'playlist.remove',
    'ad.updated',
    'ad.created',
    'ad.deleted',
    'ad.removed',
    'ad.update',
    'ad.create',
    'ad.delete',
    'ad.remove',
    'ads.updated',
    'ads.created',
    'ads.deleted',
    'ads.removed',
    'ads.update',
    'ads.create',
    'ads.delete',
    'ads.remove',
  };

  /// Namespace `/devices` — same host as REST ([ApiConfig.host]).
  static const String _socketIoUrl = ApiConfig.socketIoDevicesUrl;

  /// Call once when home is ready. [onPlaylistRefresh] runs after connect and on campaign events.
  @override
  Future<void> start({required void Function() onPlaylistRefresh}) async {
    _onPlaylistRefresh = onPlaylistRefresh;
    if (_started) return;
    _started = true;
    _failedConnectAttempts = 0;
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
      unawaited(_handleConnectFailure('missing token'));
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
        _failedConnectAttempts = 0;
        _cancelReconnectTimer();
        _startHeartbeat();
        _notifyRefresh();
      });
      for (final String eventName in _playlistRefreshEvents) {
        socket.on(eventName, onCampaignEvent);
      }
      socket.on('disconnect', (dynamic data) async {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket disconnected: $data');
        }
        _isConnecting = false;
        _cancelHeartbeatTimer();
        await _handleConnectFailure('disconnect');
      });
      socket.on('connect_error', (dynamic data) async {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket connect_error: $data');
        }
        _isConnecting = false;
        _cancelHeartbeatTimer();
        await _handleConnectFailure('connect_error');
      });
      socket.on('error', (dynamic data) async {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DevicesCampaignSocket error: $data');
        }
        _isConnecting = false;
        _cancelHeartbeatTimer();
        await _handleConnectFailure('error');
      });
    } catch (e, st) {
      _isConnecting = false;
      unawaited(_handleConnectFailure('exception'));
      if (kDebugMode) {
        // ignore: avoid_print
        print('DevicesCampaignSocket connect error: $e\n$st');
      }
    }
  }

  Future<void> _handleConnectFailure(String reason) async {
    if (!_started) return;
    _failedConnectAttempts++;
    if (_failedConnectAttempts < _maxAttemptsBeforeReauth) {
      _scheduleReconnect();
      return;
    }
    _failedConnectAttempts = 0;
    if (_isRefreshingAuth) {
      _scheduleReconnect();
      return;
    }
    _isRefreshingAuth = true;
    try {
      final bool refreshed = await _auth.refreshDeviceAuth();
      if (kDebugMode) {
        // ignore: avoid_print
        print('DevicesCampaignSocket refresh auth after $reason: $refreshed');
      }
    } finally {
      _isRefreshingAuth = false;
    }
    _scheduleReconnect();
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

  void _startHeartbeat() {
    _cancelHeartbeatTimer();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final socket_io.Socket? socket = _socket;
      if (!_started || socket == null || !socket.connected) return;
      socket.emit('heartbeat', <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _cancelHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    _isRefreshingAuth = false;
    _failedConnectAttempts = 0;
    _onPlaylistRefresh = null;
    _cancelReconnectTimer();
    _cancelHeartbeatTimer();
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }
}
