import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Renders a poster from either an asset path (e.g. assets/images/...) or a network URL.
/// Uses cacheWidth/cacheHeight for low-RAM TV devices.
class AdPosterImage extends StatelessWidget {
  const AdPosterImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.cacheWidth,
    required this.cacheHeight,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double width;
  final double height;
  final int cacheWidth;
  final int cacheHeight;
  final BoxFit fit;

  static bool isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (isNetworkUrl(url)) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        filterQuality: FilterQuality.low,
        placeholder: (BuildContext context, String _) {
          return RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
        },
        errorWidget: (BuildContext context, String _, Object error) {
          return RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      );
    }
    return Image.asset(
      url,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }
}
