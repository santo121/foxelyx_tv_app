import '../entities/ad_content.dart';

/// Pure Dart contract – no Flutter/HTTP imports.
abstract class AdsRepository {
  Future<AdContent> getAds();

  /// Clears cache and fetches playlist from the network again.
  Future<AdContent> refreshAds();

  /// Ensures current video and next video are locally playable.
  Future<AdContent> warmupForPlayback(AdContent content, int videoIndex);

  /// Best-effort cache write after a video has played from network.
  Future<void> cachePlayedVideo(String url);

  /// Removes cached videos that are no longer part of active playlist.
  Future<void> purgeMissingCachedVideos(Set<String> activeVideoUrls);
}
