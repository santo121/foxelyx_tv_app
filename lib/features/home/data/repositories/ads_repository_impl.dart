import '../../../../core/domain/repositories/auth_repository.dart';
import '../../../../core/utils/ext_cache_manager.dart';
import '../../domain/entities/ad_content.dart';
import '../../domain/repositories/ads_repository.dart';
import '../datasources/playlist_ads_datasource.dart';
import '../datasources/video_cache_datasource.dart';

class AdsRepositoryImpl implements AdsRepository {
  AdsRepositoryImpl(this._playlist, this._videoCache, this._auth);

  final PlaylistAdsDatasource _playlist;
  final VideoCacheDatasource _videoCache;
  final AuthRepository _auth;

  static bool _isRestaurantPlacement(String? placement) {
    if (placement == null) return false;
    return placement.trim().toUpperCase() == 'RESTAURANT';
  }

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

    final session = await _auth.getStoredSession();
    final bool restaurant = _isRestaurantPlacement(session?.placement);
    final AdContent fetchedContent = await _playlist.getAds();

    final bool apiPlaylistEmpty = fetchedContent.videoUrls.isEmpty &&
        fetchedContent.posterUrls.isEmpty &&
        fetchedContent.youtubeUrls.isEmpty;
    if (apiPlaylistEmpty) {
      try {
        await _videoCache.purgeMissingFrom(<String>{});
      } catch (_) {}
      try {
        await ExtCacheManager.instance.emptyCache();
      } catch (_) {}
    }

    // RESTAURANT placement: no YouTube in the playlist. Otherwise inject global filler URLs.
    final AdContent content = restaurant
        ? AdContent(
            videoUrls: fetchedContent.videoUrls,
            posterUrls: fetchedContent.posterUrls,
            youtubeUrls: const <String>[],
          )
        : AdContent(
            videoUrls: fetchedContent.videoUrls,
            posterUrls: fetchedContent.posterUrls,
            youtubeUrls: <String>{
              ...fetchedContent.youtubeUrls,
              'https://www.youtube.com/watch?v=kzpS-A3QJqE&list=RDkzpS-A3QJqE&start_radio=1',
              'https://www.youtube.com/watch?v=DXm6diugHCc&list=RDDXm6diugHCc&start_radio=1',
            }.toList(),
          );

    try {
      await _videoCache.purgeMissingFrom(content.videoUrls.toSet());
    } catch (_) {
      // Keep fetch resilient even if stale-cache purge fails.
    }
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
      youtubeUrls: content.youtubeUrls,
    );
    _cachedResolvedContent = warmed;
    return warmed;
  }

  @override
  Future<void> cachePlayedVideo(String url) async {
    if (_isYoutubeUrl(url)) return;
    if (!url.startsWith('http')) return;
    await _videoCache.cacheVideoIfNeeded(url);
  }

  @override
  Future<void> purgeMissingCachedVideos(Set<String> activeVideoUrls) async {
    await _videoCache.purgeMissingFrom(activeVideoUrls);
  }

  bool _isYoutubeUrl(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }
}
