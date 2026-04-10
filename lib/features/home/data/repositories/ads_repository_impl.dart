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

  @override
  Future<AdContent> refreshAds() async {
    _cachedResolvedContent = null;
    return getAds();
  }

  @override
  Future<AdContent> getAds() async {
    if (_cachedResolvedContent != null) return _cachedResolvedContent!;

    final AdContent content = await _playlist.getAds();
    _cachedResolvedContent = content;
    return content;
  }

  @override
  Future<AdContent> warmupForPlayback(AdContent content, int videoIndex) async {
    if (content.videoUrls.isEmpty) return content;

    final List<String> resolved = List<String>.from(content.videoUrls);
    final Set<int> indexesToWarm = <int>{videoIndex};

    for (final int index in indexesToWarm) {
      if (index < 0 || index >= resolved.length) continue;
      try {
        resolved[index] = await _videoCache.getLocalPath(resolved[index]);
      } catch (_) {
        // Keep original URL so playback can continue even when caching fails.
      }
    }

    final AdContent warmed = AdContent(
      videoUrls: resolved,
      posterUrls: content.posterUrls,
    );
    _cachedResolvedContent = warmed;
    return warmed;
  }
}
