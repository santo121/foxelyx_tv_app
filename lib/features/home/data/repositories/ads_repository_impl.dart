import '../../domain/entities/ad_content.dart';
import '../../domain/repositories/ads_repository.dart';
import '../datasources/playlist_ads_datasource.dart';
import '../datasources/video_cache_datasource.dart';

class AdsRepositoryImpl implements AdsRepository {
  AdsRepositoryImpl(this._playlist, this._videoCache);

  final PlaylistAdsDatasource _playlist;
  final VideoCacheDatasource _videoCache;

  /// Cached resolved content so repeated getAds() (e.g. after each ad or new cubit)
  /// returns local paths without calling network or re-resolving.
  AdContent? _cachedResolvedContent;

  /// Resolves every video URL to a local path (cached file or asset).
  /// Once resolved, subsequent calls return the same cached content — no network, no re-resolve.
  @override
  Future<AdContent> getAds() async {
    if (_cachedResolvedContent != null) return _cachedResolvedContent!;

    final AdContent content = await _playlist.getAds();
    final List<String> resolved = <String>[];
    for (final String url in content.videoUrls) {
      resolved.add(await _videoCache.getLocalPath(url));
    }
    _cachedResolvedContent = AdContent(
      videoUrls: resolved,
      posterUrls: content.posterUrls,
    );
    return _cachedResolvedContent!;
  }
}
