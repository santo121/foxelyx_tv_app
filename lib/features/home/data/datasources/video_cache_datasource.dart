import 'dart:async';

import 'cached_video_database.dart';

/// Resolves remote URLs to cached local file paths when available.
/// No background downloads are performed while ads are playing.
class VideoCacheDatasource {
  VideoCacheDatasource();

  /// Returns local file path for the video. Cache-first: if already cached, returns
  /// that path and never hits the network. Non-http [url] (e.g. asset paths) are returned unchanged.
  Future<String> getLocalPath(String url) async {
    if (!url.startsWith('http')) return url;

    // Use cached local file if we have it (no network call).
    final String? storedPath = await CachedVideoDatabase.getLocalPathByUrl(url);
    if (storedPath != null) {
      return storedPath;
    }

    // Cache miss: return network URL; no background downloads.
    return url;
  }
}
