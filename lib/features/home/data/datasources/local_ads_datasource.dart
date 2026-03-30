import '../../domain/entities/ad_content.dart';

/// Local data source for ads (e.g. hardcoded or asset-based).
/// Can be replaced later with a remote datasource without changing domain.
/// For Android TV (ExoPlayer): use H.264 Baseline or Main profile in MP4.
/// If you get PlatformException(VideoError, ExoPlaybackException: Source error),
/// re-encode the file (e.g. ffmpeg -c:v libx264 -profile:v main -c:a aac).
class LocalAdsDatasource {
  Future<AdContent> getAds() async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    // Use H.264 Baseline/Main MP4 for Android TV (ExoPlayer). Pixabay/other sources
    // often use profiles that cause red screen / decode errors on TV.
    return const AdContent(
      videoUrls: [
        // 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        'assets/videos/VIDEO-2026-02-25-10-37-10.mp4',
        'assets/videos/G-tech.mp4',
        'assets/videos/smartclick.mp4',
      ],
      posterUrls: [
        'assets/ads/amigo.pdf',
        'assets/images/Lalitham-2.jpg',
        'assets/images/G-tec-final.png',
        'assets/images/Health-plus-poster-2.jpg',
        'assets/images/Jazz-paints-poster.jpg',
        'assets/images/eagle-way-poster.jpg',
        // 'assets/images/bus2.jpg',
      ],
    );
  }
}
