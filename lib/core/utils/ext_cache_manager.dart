import 'dart:io' as io;

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

import 'storage_helper.dart';

class ExtFileSystem implements FileSystem {
  final String cacheKey;
  final fs.FileSystem _localFileSystem = const LocalFileSystem();

  ExtFileSystem(this.cacheKey);

  @override
  Future<fs.File> createFile(String name) async {
    final io.Directory dir = await StorageHelper.getBestCacheDirectory();
    final io.Directory cacheDir = io.Directory(p.join(dir.path, cacheKey));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return _localFileSystem.file(p.join(cacheDir.path, name));
  }
}

/// [ImageCacheManager] is required so [CachedNetworkImageProvider] may use
/// `maxWidth` / `maxHeight` (disk-resized cache entries) without assertions.
class _ExtAdImageCacheManager extends CacheManager with ImageCacheManager {
  _ExtAdImageCacheManager()
    : super(
        Config(
          ExtCacheManager.key,
          fileSystem: ExtFileSystem(ExtCacheManager.key),
          maxNrOfCacheObjects: 200,
          stalePeriod: const Duration(days: 30),
        ),
      );
}

class ExtCacheManager {
  static const String key = 'extAdImageCache';

  static final CacheManager instance = _ExtAdImageCacheManager();
}
