import '../entities/ad_content.dart';

/// Pure Dart contract – no Flutter/HTTP imports.
abstract class AdsRepository {
  Future<AdContent> getAds();

  /// Clears cache and fetches playlist from the network again.
  Future<AdContent> refreshAds();
}
