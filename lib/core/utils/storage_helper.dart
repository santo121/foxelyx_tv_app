import 'dart:io';

import 'package:path_provider/path_provider.dart';

class StorageHelper {
  /// Returns the best available cache directory.
  /// Prefers external removable storage (e.g., USB drive).
  /// Falls back to internal documents directory.
  static Future<Directory> getBestCacheDirectory() async {
    if (Platform.isAndroid) {
      try {
        final List<Directory>? externalDirs =
            await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          // The first directory is usually the primary external storage.
          // Subsequent directories are physical media like SD Cards or USB drives.
          // Favouring the 'last' one ensures we pick external removable media if connected.
          return externalDirs.last;
        }
      } catch (_) {
        // Ignore and fallback
      }
    }
    return await getApplicationDocumentsDirectory();
  }
}
