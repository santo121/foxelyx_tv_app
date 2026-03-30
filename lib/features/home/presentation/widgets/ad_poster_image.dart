import 'package:flutter/material.dart';

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
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        loadingBuilder: (
          BuildContext context,
          Widget child,
          ImageChunkEvent? loadingProgress,
        ) {
          if (loadingProgress == null) return child;
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
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) {
          return RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
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
