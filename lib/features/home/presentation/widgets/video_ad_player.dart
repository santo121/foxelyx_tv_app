import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Dumb widget: displays video from a single controller (owned by Cubit).
/// RepaintBoundary isolates video layer for GPU memory on low-RAM devices.
class VideoAdPlayer extends StatelessWidget {
  const VideoAdPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final double aspectRatio = controller.value.aspectRatio;
    return RepaintBoundary(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: aspectRatio,
            height: 1,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
