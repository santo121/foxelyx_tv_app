import 'package:equatable/equatable.dart';
import 'package:video_player/video_player.dart';

import '../../domain/entities/ad_content.dart';

sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

final class HomeInitial extends HomeState {
  const HomeInitial();
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

/// Ads loaded, UI can paint; video init deferred to next frame to avoid blocking main thread.
final class HomeContentReady extends HomeState {
  const HomeContentReady({required this.content});

  final AdContent content;

  @override
  List<Object?> get props => [content];
}

final class HomeLoaded extends HomeState {
  const HomeLoaded({
    required this.content,
    this.videoController,
    this.currentDisplayIndex = 0,
  });

  final AdContent content;
  /// Non-null when currentDisplayIndex >= posterUrls.length (showing a video).
  final VideoPlayerController? videoController;
  /// 0..posterUrls.length-1 = poster; >= posterUrls.length = video slot.
  final int currentDisplayIndex;

  @override
  List<Object?> get props => [content, videoController, currentDisplayIndex];
}

final class HomeError extends HomeState {
  const HomeError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
