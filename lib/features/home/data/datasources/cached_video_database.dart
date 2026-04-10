import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite database storing network video URL -> local file path.
/// Single source of truth: videos are loaded from paths stored here, not from URLs.
class CachedVideoDatabase {
  CachedVideoDatabase._();
  static const String _table = 'cached_videos';
  static const String _columnUrl = 'url';
  static const String _columnLocalPath = 'local_path';
  static const String _columnDownloadedAt = 'downloaded_at';
  static const String _columnLastAccessedAt = 'last_accessed_at';
  static const int _minValidVideoBytes = 1024;

  static Database? _db;

  static Future<Database> _getDb() async {
    if (_db != null && (_db!.isOpen)) return _db!;
    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = p.join(dir.path, 'cached_videos.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_table (
            $_columnUrl TEXT PRIMARY KEY,
            $_columnLocalPath TEXT NOT NULL,
            $_columnDownloadedAt INTEGER NOT NULL,
            $_columnLastAccessedAt INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _ensureLastAccessedAtColumn(db);
        }
      },
      onOpen: (Database db) async {
        await _ensureLastAccessedAtColumn(db);
      },
    );
    return _db!;
  }

  static Future<void> _ensureLastAccessedAtColumn(Database db) async {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info($_table)',
    );
    final bool hasLastAccessed = columns.any(
      (Map<String, Object?> c) => c['name'] == _columnLastAccessedAt,
    );
    if (hasLastAccessed) return;
    await db.execute(
      'ALTER TABLE $_table ADD COLUMN $_columnLastAccessedAt INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Returns stored local path for [url], or null if not in database.
  static Future<String?> getLocalPathByUrl(String url) async {
    final Database db = await _getDb();
    final List<Map<String, Object?>> rows = await db.query(
      _table,
      columns: [_columnLocalPath],
      where: '$_columnUrl = ?',
      whereArgs: [url],
    );
    if (rows.isEmpty) return null;
    final String path = rows.first[_columnLocalPath]! as String;
    final File file = File(path);
    final bool exists = await file.exists();
    final int fileSize = exists ? await file.length() : 0;
    if (!exists || fileSize < _minValidVideoBytes) {
      await deleteByUrl(url);
      if (exists) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return null;
    }
    return path;
  }

  /// Saves URL -> local path. Overwrites if URL already exists.
  static Future<void> saveCachedVideo(String url, String localPath) async {
    final Database db = await _getDb();
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(_table, <String, Object?>{
      _columnUrl: url,
      _columnLocalPath: localPath,
      _columnDownloadedAt: now,
      _columnLastAccessedAt: now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteByUrl(String url) async {
    final Database db = await _getDb();
    await db.delete(_table, where: '$_columnUrl = ?', whereArgs: [url]);
  }
}
