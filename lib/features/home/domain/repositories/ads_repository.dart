import '../entities/ad_content.dart';

/// Pure Dart contract – no Flutter/HTTP imports.
abstract class AdsRepository {
  Future<AdContent> getAds();
}
