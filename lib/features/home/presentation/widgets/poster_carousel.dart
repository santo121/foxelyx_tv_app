import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import 'ad_poster_image.dart';

/// TV-focused carousel: Focus on each item, no heavy shaders (border only when focused).
/// cacheWidth/cacheHeight from display size to save heap on ~1 GB RAM.
class PosterCarousel extends StatefulWidget {
  const PosterCarousel({
    super.key,
    required this.posterUrls,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  final List<String> posterUrls;
  final int cacheWidth;
  final int cacheHeight;

  @override
  State<PosterCarousel> createState() => _PosterCarouselState();
}

class _PosterCarouselState extends State<PosterCarousel> {
  @override
  Widget build(BuildContext context) {
    return CarouselSlider.builder(
      itemCount: widget.posterUrls.length,
      options: CarouselOptions(
        height: double.infinity,
        viewportFraction: 0.8,
        enlargeCenterPage: true,
        scrollDirection: Axis.vertical,
        autoPlay: true,
        autoPlayInterval: const Duration(seconds: 4),
      ),
      itemBuilder: (BuildContext context, int index, int realIndex) {
        final String posterUrl = widget.posterUrls[index];
        return Focus(
          autofocus: index == 0,
          child: Builder(
            builder: (BuildContext context) {
              final bool hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: hasFocus ? Colors.blueAccent : Colors.transparent,
                    width: hasFocus ? 4.0 : 0.0,
                  ),
                  // No BoxShadow – heavy shaders avoided for TV GPU/RAM
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: AdPosterImage(
                    url: posterUrl,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: widget.cacheWidth,
                    cacheHeight: widget.cacheHeight,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
