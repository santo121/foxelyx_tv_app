/// Pure Dart entity – no Flutter/HTTP imports.
class AdContent {
  const AdContent({
    required this.videoUrls,
    required this.posterUrls,
    this.youtubeUrls = const [],
  });

  /// One or more video URLs (asset paths or http). Played in order after posters.
  final List<String> videoUrls;
  final List<String> posterUrls;
  final List<String> youtubeUrls;
}
