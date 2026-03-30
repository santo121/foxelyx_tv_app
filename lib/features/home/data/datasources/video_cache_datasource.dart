import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cached_video_database.dart';

/// Downloads remote videos, stores them on disk and records URL → path in local DB.
/// Always loads video from the path stored in the database, not from the network URL.
/// Reuses existing file if URL is already in DB and file exists.
class VideoCacheDatasource {
  VideoCacheDatasource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _cacheSubdir = 'video_cache';

  /// Returns local file path for the video. Cache-first: if already cached, returns
  /// that path and never hits the network. Non-http [url] (e.g. asset paths) are returned unchanged.
  Future<String> getLocalPath(String url) async {
    if (!url.startsWith('http')) return url;

    // Use cached local file if we have it (no network call).
    final String? storedPath = await CachedVideoDatabase.getLocalPathByUrl(url);
    if (storedPath != null) return storedPath;

    // Cache miss: download once, save to file, store in DB; next call will use cache.
    final String filename = _filenameFromUrl(url);
    final Directory dir = await _cacheDir();
    final File file = File('${dir.path}/$filename');
    await _downloadToFile(url, file);
    await CachedVideoDatabase.saveCachedVideo(url, file.path);
    return file.path;
  }

  Future<Directory> _cacheDir() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${appDir.path}/$_cacheSubdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _filenameFromUrl(String url) {
    final Uri uri = Uri.parse(url);
    final String last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'video';
    final String safe = last.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return safe.isNotEmpty ? safe : 'video_${uri.hashCode}.mp4';
  }

  Future<void> _downloadToFile(String url, File file) async {
    final http.Request request = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Video download failed: ${response.statusCode}');
    }
    final IOSink sink = file.openWrite();
    await for (final List<int> chunk in response.stream) {
      sink.add(chunk);
    }
    await sink.close();
  }
}
