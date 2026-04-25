import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../core/utils/storage_helper.dart';
import 'cached_video_database.dart';

/// Resolves remote URLs to cached local file paths when available.
/// No background downloads are performed while ads are playing.
class VideoCacheDatasource {
  VideoCacheDatasource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, Future<void>> _inFlightByUrl = <String, Future<void>>{};

  static const int _maxCachedFiles = 20;
  static const int _maxCachedBytes = 300 * 1024 * 1024;

  /// Returns local file path for the video. Cache-first: if already cached, returns
  /// that path and never hits the network. Non-http [url] (e.g. asset paths) are returned unchanged.
  Future<String> getLocalPath(String url) async {
    if (_isYoutubeUrl(url)) return url;
    if (!url.startsWith('http')) return url;

    // Use cached local file if we have it (no network call).
    final String? storedPath = await CachedVideoDatabase.getLocalPathByUrl(url);
    if (storedPath != null) {
      if (await File(storedPath).exists()) {
        return storedPath;
      } else {
        await CachedVideoDatabase.deleteByUrl(url);
      }
    }

    // Cache miss: return network URL; no background downloads.
    return url;
  }

  /// Downloads [url] to local storage when not already cached.
  /// Uses per-URL in-flight deduping to avoid duplicate downloads.
  Future<void> cacheVideoIfNeeded(String url) async {
    if (_isYoutubeUrl(url)) return;
    if (!url.startsWith('http')) return;

    final Future<void> pending =
        _inFlightByUrl[url] ?? _cacheVideoInternal(url);
    _inFlightByUrl[url] = pending;
    try {
      await pending;
    } finally {
      if (identical(_inFlightByUrl[url], pending)) {
        _inFlightByUrl.remove(url);
      }
    }
  }

  /// Removes cached files/rows that are not present in [activeUrls].
  Future<void> purgeMissingFrom(Set<String> activeUrls) async {
    final Set<String> normalizedActive = activeUrls
        .where((String url) => url.startsWith('http') && !_isYoutubeUrl(url))
        .toSet();
    final List<CachedVideoEntry> entries =
        await CachedVideoDatabase.listEntries();
    for (final CachedVideoEntry entry in entries) {
      if (normalizedActive.contains(entry.url)) continue;
      await _deleteEntry(entry);
    }
  }

  Future<void> _cacheVideoInternal(String url) async {
    if (_isYoutubeUrl(url)) return;
    final String? existing = await CachedVideoDatabase.getLocalPathByUrl(url);
    if (existing != null) return;

    final Uri uri = Uri.parse(url);
    final http.StreamedResponse response = await _client.send(
      http.Request('GET', uri),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Video download failed (${response.statusCode})',
        uri: uri,
      );
    }

    final Directory docs = await StorageHelper.getBestCacheDirectory();
    final Directory cacheDir = Directory(p.join(docs.path, 'cached_videos'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final String extension = _safeExtensionFromUrl(url);
    final String fileName = '${base64Url.encode(utf8.encode(url))}$extension';
    final File tempFile = File(p.join(cacheDir.path, '$fileName.part'));
    final File finalFile = File(p.join(cacheDir.path, fileName));
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      final IOSink sink = tempFile.openWrite();
      await sink.addStream(response.stream);
      await sink.close();
      final int length = await tempFile.length();
      if (length < 1024) {
        throw const FileSystemException('Downloaded video file too small.');
      }
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(finalFile.path);
      await CachedVideoDatabase.saveCachedVideo(url, finalFile.path);
      await _evictIfNeeded();
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  String _safeExtensionFromUrl(String url) {
    final String extension = p.extension(Uri.parse(url).path).toLowerCase();
    switch (extension) {
      case '.mp4':
      case '.webm':
      case '.mkv':
      case '.mov':
      case '.m4v':
        return extension;
      default:
        return '.mp4';
    }
  }

  Future<void> _evictIfNeeded() async {
    final List<CachedVideoEntry> entries =
        await CachedVideoDatabase.listEntries();
    if (entries.isEmpty) return;

    final List<_SizedCachedVideoEntry> sized = <_SizedCachedVideoEntry>[];
    int totalBytes = 0;
    for (final CachedVideoEntry entry in entries) {
      final File file = File(entry.localPath);
      if (!await file.exists()) {
        await CachedVideoDatabase.deleteByUrl(entry.url);
        continue;
      }
      final int size = await file.length();
      totalBytes += size;
      sized.add(_SizedCachedVideoEntry(entry: entry, bytes: size));
    }
    if (sized.length <= _maxCachedFiles && totalBytes <= _maxCachedBytes) {
      return;
    }

    sized.sort((a, b) {
      final int accessedOrder = a.entry.lastAccessedAt.compareTo(
        b.entry.lastAccessedAt,
      );
      if (accessedOrder != 0) return accessedOrder;
      return a.entry.downloadedAt.compareTo(b.entry.downloadedAt);
    });

    int remainingFiles = sized.length;
    for (final _SizedCachedVideoEntry candidate in sized) {
      if (remainingFiles <= _maxCachedFiles && totalBytes <= _maxCachedBytes) {
        break;
      }
      await _deleteEntry(candidate.entry);
      totalBytes -= candidate.bytes;
      remainingFiles--;
    }
  }

  Future<void> _deleteEntry(CachedVideoEntry entry) async {
    final File file = File(entry.localPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await CachedVideoDatabase.deleteByUrl(entry.url);
  }

  bool _isYoutubeUrl(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }
}

class _SizedCachedVideoEntry {
  const _SizedCachedVideoEntry({required this.entry, required this.bytes});

  final CachedVideoEntry entry;
  final int bytes;
}
