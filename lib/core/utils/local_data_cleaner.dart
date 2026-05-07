import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'ext_cache_manager.dart';
import 'storage_helper.dart';

/// Clears persisted app caches that should be invalidated on auth failures.
class LocalDataCleaner {
  /// Best-effort cleanup: failures in one step do not block others.
  Future<void> clearAllCachedData() async {
    await _clearImageCache();
    await _clearVideoCacheFiles();
    await _clearVideoCacheDatabase();
  }

  Future<void> _clearImageCache() async {
    try {
      await ExtCacheManager.instance.emptyCache();
    } catch (_) {
      // Ignore cache cleanup errors.
    }
  }

  Future<void> _clearVideoCacheFiles() async {
    try {
      final Directory root = await StorageHelper.getBestCacheDirectory();
      final Directory cacheDir = Directory(p.join(root.path, 'cached_videos'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {
      // Ignore cache cleanup errors.
    }
  }

  Future<void> _clearVideoCacheDatabase() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String dbPath = p.join(dir.path, 'cached_videos.db');
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {
      // Ignore cache cleanup errors.
    }
  }
}
