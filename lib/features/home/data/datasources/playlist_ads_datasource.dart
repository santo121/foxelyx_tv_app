import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../domain/entities/ad_content.dart';
import '../../domain/exceptions/playlist_auth_required_exception.dart';

/// Fetches the ad playlist: `GET /api/devices/:deviceId/playlist`.
const String _playlistBaseHost = ApiConfig.host;

AdContent _parsePlaylistResponseBody(Map<String, String?> payload) {
  final String responseBody = payload['responseBody'] ?? '';
  final String? preferredOrientation = payload['preferredOrientation'];
  return PlaylistAdsDatasource.parseResponseBodyStatic(
    responseBody,
    preferredOrientation: preferredOrientation,
  );
}

class PlaylistAdsDatasource {
  PlaylistAdsDatasource(this._auth, {http.Client? client})
    : _client = client ?? http.Client();

  final AuthRepository _auth;
  final http.Client _client;

  Future<AdContent> getAds() async {
    final String? token = await _auth.getAccessToken();
    final session = await _auth.getStoredSession();
    final String? deviceId = session?.vehicleId;
    final String? preferredOrientation = _preferredOrientationForScreenType(
      session?.screenType,
    );
    if (token == null ||
        token.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      throw StateError('Not authenticated or device id missing.');
    }

    final Uri uri = Uri.https(
      _playlistBaseHost,
      '/api/devices/${Uri.encodeComponent(deviceId)}/playlist',
    );

    final http.Response response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 400 || response.statusCode == 401) {
      throw PlaylistAuthRequiredException(response.statusCode);
    }
    if (response.statusCode == 403) {
      throw Exception('Playlist unauthorized. Sign in again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Playlist failed (${response.statusCode}).');
    }

    final AdContent parsed = await compute(
      _parsePlaylistResponseBody,
      <String, String?>{
        'responseBody': response.body,
        'preferredOrientation': preferredOrientation,
      },
    );
    return parsed;
  }

  static AdContent parseResponseBodyStatic(
    String responseBody, {
    String? preferredOrientation,
  }) {
    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is List<dynamic>) {
      return _parseItems(decoded, preferredOrientation: preferredOrientation);
    }
    if (decoded is Map<String, dynamic>) {
      return _parseResponse(
        decoded,
        preferredOrientation: preferredOrientation,
      );
    }
    throw const FormatException('Unsupported playlist JSON shape.');
  }

  static AdContent parseResponseStatic(
    Map<String, dynamic> json, {
    String? preferredOrientation,
  }) {
    return _parseResponse(json, preferredOrientation: preferredOrientation);
  }

  static AdContent _parseResponse(
    Map<String, dynamic> json, {
    String? preferredOrientation,
  }) {
    final dynamic data = json['data'] ?? json;
    if (data is List<dynamic>) {
      return _parseItems(data, preferredOrientation: preferredOrientation);
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Unsupported playlist JSON shape.');
    }
    final Map<String, dynamic> body = data;

    List<String> videos = _urlsFromKeys(body, <String>[
      'videoUrls',
      'video_urls',
      'videos',
    ]);
    List<String> posters = _urlsFromKeys(body, <String>[
      'posterUrls',
      'poster_urls',
      'posters',
      'images',
    ]);

    if (videos.isEmpty && posters.isEmpty) {
      final dynamic items = body['items'] ?? body['playlist'];
      if (items is List<dynamic>) {
        return _parseItems(items, preferredOrientation: preferredOrientation);
      }
      videos = _urlsFromFlatListKeys(body, <String>[
        'urls',
        'media',
        'assets',
        'contents',
      ]);
    }

    final List<String> finalVideos = <String>[];
    final List<String> finalYouTubes = <String>[];
    for (final v in videos) {
      if (_looksLikeYoutube(v)) {
        finalYouTubes.add(v);
      } else {
        finalVideos.add(v);
      }
    }

    if (finalVideos.isEmpty && posters.isEmpty && finalYouTubes.isEmpty) {
      throw const FormatException('Unsupported playlist JSON shape.');
    }
    return AdContent(videoUrls: finalVideos, posterUrls: posters, youtubeUrls: finalYouTubes);
  }

  static AdContent _parseItems(
    List<dynamic> items, {
    String? preferredOrientation,
  }) {
    final AdContent oriented = _parseItemsWithOrientation(
      items,
      preferredOrientation: preferredOrientation,
    );
    if (!_isAdContentEmpty(oriented) || preferredOrientation == null) {
      return oriented;
    }

    // Defensive fallback: if strict orientation produced nothing, use any
    // available media instead of locking the screen in empty state.
    return _parseItemsWithOrientation(items, preferredOrientation: null);
  }

  static AdContent _parseItemsWithOrientation(
    List<dynamic> items, {
    String? preferredOrientation,
  }) {
    final List<String> videos = <String>[];
    final List<String> posters = <String>[];
    for (final dynamic item in items) {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item);
      final String? itemOrientation =
          m['orientation']?.toString().trim().toLowerCase();
      if (!_matchesPreferredOrientation(itemOrientation, preferredOrientation)) {
        continue;
      }
      final String? type = (m['type'] ?? m['kind'] ?? m['mediaType'])
          ?.toString()
          .toLowerCase();
      final String? v = _firstString(m, <String>[
        'videoUrl',
        'video_url',
        'url',
        'src',
        'mediaUrl',
        'media_url',
      ]);
      final String? p = _firstString(m, <String>[
        'posterUrl',
        'poster_url',
        'thumbnail',
        'image',
        'poster',
      ]);
      if (type == 'poster' || type == 'image') {
        if (p != null && p.isNotEmpty) {
          posters.add(p);
        } else if (v != null && v.isNotEmpty) {
          posters.add(v);
        }
        continue;
      }
      if (type == 'video' || type == 'ad' || type == 'video_ad') {
        if (v != null && v.isNotEmpty) videos.add(v);
        if (p != null && p.isNotEmpty) posters.add(p);
        continue;
      }
      if (v != null && v.isNotEmpty) {
        if (_looksLikeVideo(v)) {
          videos.add(v);
        } else {
          posters.add(v);
        }
      }
      if (p != null && p.isNotEmpty) posters.add(p);
    }
    final List<String> finalVideos = <String>[];
    final List<String> finalYouTubes = <String>[];
    for (final v in videos) {
      if (_looksLikeYoutube(v)) {
        finalYouTubes.add(v);
      } else {
        finalVideos.add(v);
      }
    }
    return AdContent(videoUrls: finalVideos, posterUrls: posters, youtubeUrls: finalYouTubes);
  }

  static bool _isAdContentEmpty(AdContent content) =>
      content.videoUrls.isEmpty &&
      content.posterUrls.isEmpty &&
      content.youtubeUrls.isEmpty;

  static bool _looksLikeVideo(String url) {
    if (_looksLikeYoutube(url)) return true;
    final String lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('.mkv') ||
        lower.contains('/video');
  }

  static bool _looksLikeYoutube(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  static String? _preferredOrientationForScreenType(String? screenType) {
    final String normalized = (screenType ?? '').trim().toUpperCase();
    if (normalized == 'PORTRAIT') return 'portrait';
    if (normalized == 'LANDSCAPE') return 'landscape';
    return null;
  }

  static bool _matchesPreferredOrientation(
    String? itemOrientation,
    String? preferredOrientation,
  ) {
    final String preferred = (preferredOrientation ?? '').trim().toLowerCase();
    if (preferred.isEmpty) return true;
    final String item = (itemOrientation ?? '').trim().toLowerCase();
    if (item.isEmpty) return true;
    if (preferred == 'portrait') {
      return item == 'portrait' || item == 'vertical';
    }
    if (preferred == 'landscape') {
      return item == 'landscape' || item == 'horizontal';
    }
    return true;
  }

  static String? _firstString(Map<String, dynamic> m, List<String> keys) {
    for (final String k in keys) {
      final Object? v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static List<String> _urlsFromFlatListKeys(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final String key in keys) {
      final dynamic raw = data[key];
      if (raw is! List<dynamic>) continue;
      final List<String> out = <String>[];
      for (final dynamic e in raw) {
        if (e is String && e.isNotEmpty) {
          out.add(e);
        } else if (e is Map) {
          final String? u = _firstString(Map<String, dynamic>.from(e), <String>[
            'url',
            'src',
            'videoUrl',
            'video_url',
          ]);
          if (u != null) out.add(u);
        }
      }
      if (out.isNotEmpty) return out;
    }
    return <String>[];
  }

  static List<String> _urlsFromKeys(Map<String, dynamic> data, List<String> keys) {
    for (final String key in keys) {
      final dynamic raw = data[key];
      if (raw is! List<dynamic>) continue;
      final List<String> out = <String>[];
      for (final dynamic e in raw) {
        if (e is String && e.isNotEmpty) {
          out.add(e);
        } else if (e is Map) {
          final String? u = _firstString(Map<String, dynamic>.from(e), <String>[
            'url',
            'src',
            'videoUrl',
            'video_url',
          ]);
          if (u != null) out.add(u);
        }
      }
      if (out.isNotEmpty) return out;
    }
    return <String>[];
  }
}
