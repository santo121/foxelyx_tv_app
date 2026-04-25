import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../domain/entities/ad_content.dart';
import '../../domain/exceptions/playlist_auth_required_exception.dart';

/// Fetches the ad playlist: `GET /api/devices/:deviceId/playlist`.
const String _playlistBaseHost = ApiConfig.host;

AdContent _parsePlaylistResponseBody(String responseBody) {
  return PlaylistAdsDatasource.parseResponseBodyStatic(responseBody);
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
      response.body,
    );
    return parsed;
  }

  static AdContent parseResponseBodyStatic(String responseBody) {
    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is List<dynamic>) {
      return _parseItems(decoded);
    }
    if (decoded is Map<String, dynamic>) {
      return _parseResponse(decoded);
    }
    throw const FormatException('Unsupported playlist JSON shape.');
  }

  static AdContent parseResponseStatic(Map<String, dynamic> json) {
    return _parseResponse(json);
  }

  static AdContent _parseResponse(Map<String, dynamic> json) {
    final dynamic data = json['data'] ?? json;
    if (data is List<dynamic>) {
      return _parseItems(data);
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
        return _parseItems(items);
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

  static AdContent _parseItems(List<dynamic> items) {
    final List<String> videos = <String>[];
    final List<String> posters = <String>[];
    for (final dynamic item in items) {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item);
      final String? orientation = m['orientation']?.toString().toLowerCase();
      // TV app is landscape-only; when API sends orientation, keep only horizontal items.
      if (orientation != null &&
          orientation.isNotEmpty &&
          orientation != 'horizontal') {
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
