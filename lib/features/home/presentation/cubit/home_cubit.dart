import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../domain/campaign_playlist_socket.dart';
import '../../domain/entities/ad_content.dart';
import '../../domain/entities/preloaded_ads_holder.dart';
import '../../domain/repositories/ads_repository.dart';
import 'home_state.dart';

/// Single video controller at a time; init next when advancing to next video slot.
/// Posters and videos are shown in order: each poster 20s, then each video for its duration.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._adsRepository, this._campaignSocket)
    : super(const HomeInitial());

  final AdsRepository _adsRepository;
  final CampaignPlaylistSocket _campaignSocket;
  static const Duration _posterDuration = Duration(seconds: 20);
  static const Duration _warmupTimeout = Duration(seconds: 8);
  static const Duration _videoInitializeTimeout = Duration(seconds: 12);
  Timer? _rotationTimer;
  VoidCallback? _videoErrorListener;
  VoidCallback? _videoCompletionListener;
  VideoPlayerController? _videoCompletionController;
  int _videoSlotGeneration = 0;
  AdContent? _pendingPlaylistContent;
  bool _isRefreshInFlight = false;
  VideoPlayerController? _preparedVideoController;
  int? _preparedVideoDisplayIndex;
  bool _isPreparingVideo = false;
  Timer? _initialLoadingIndicatorTimer;

  Future<void> loadAds() async {
    _initialLoadingIndicatorTimer?.cancel();
    _initialLoadingIndicatorTimer = null;
    try {
      final AdContent? preloaded = PreloadedAdsHolder.instance.hasContent
          ? PreloadedAdsHolder.instance.take()
          : null;
      final AdContent content;
      if (preloaded != null) {
        content = preloaded;
      } else {
        _initialLoadingIndicatorTimer = Timer(const Duration(milliseconds: 1200), () {
          if (isClosed) return;
          final HomeState current = state;
          if (current is HomeInitial) {
            emit(const HomeLoading());
          }
        });
        content = await _adsRepository.getAds();
      }
      if (isClosed) return;
      _initialLoadingIndicatorTimer?.cancel();
      _initialLoadingIndicatorTimer = null;
      emit(HomeContentReady(content: content));
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (isClosed) return;
        _startRotation(content);
      });
      unawaited(
        _campaignSocket.start(
          onPlaylistRefresh: () {
            unawaited(refreshPlaylistFromServer());
          },
        ),
      );
    } catch (e, st) {
      _initialLoadingIndicatorTimer?.cancel();
      _initialLoadingIndicatorTimer = null;
      if (kDebugMode) {
        // ignore: avoid_print
        print('HomeCubit.loadAds error: $e\n$st');
      }
      if (!isClosed) emit(HomeError(e.toString()));
    }
  }

  /// Called when the devices socket connects or campaign events fire — fetches latest playlist.
  Future<void> refreshPlaylistFromServer() async {
    if (isClosed) return;
    if (state is HomeLoading) return;
    if (_isRefreshInFlight) return;
    _isRefreshInFlight = true;
    try {
      final AdContent content = await _adsRepository.refreshAds();
      if (isClosed) return;
      // Queue playlist refresh and apply only at ad boundary.
      _pendingPlaylistContent = content;
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('HomeCubit.refreshPlaylistFromServer error: $e\n$st');
      }
    } finally {
      _isRefreshInFlight = false;
    }
  }

  void _startRotation(AdContent content) {
    if (isClosed) return;
    _clearPreparedVideo();
    final int posterCount = content.posterUrls.length;
    if (content.videoUrls.isEmpty) {
      if (posterCount > 0) {
        emit(HomeLoaded(content: content, currentDisplayIndex: 0));
        unawaited(_prepareNextDisplay(content, 0));
        _scheduleNext(content, null, 0);
      }
      return;
    }
    if (posterCount > 0) {
      emit(HomeLoaded(content: content, currentDisplayIndex: 0));
      unawaited(_prepareNextDisplay(content, 0));
      _scheduleNext(content, null, 0);
    } else {
      _playVideoAt(content, 0);
    }
  }

  VideoPlayerController _controllerForUrl(String url) {
    if (url.startsWith('http')) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }
    if (url.startsWith('assets/')) {
      return VideoPlayerController.asset(url);
    }
    return VideoPlayerController.file(File(url));
  }

  Future<void> _playVideoAt(AdContent content, int videoIndex) async {
    if (isClosed || videoIndex >= content.videoUrls.length) return;
    final int posterCount = content.posterUrls.length;
    final int displayIndex = posterCount + videoIndex;

    VideoPlayerController? controller = _consumePreparedVideoIfMatches(
      displayIndex,
    );

    AdContent warmedContent = content;
    if (controller == null) {
      try {
        warmedContent = await _adsRepository
            .warmupForPlayback(content, videoIndex)
            .timeout(_warmupTimeout);
      } catch (_) {
        warmedContent = content;
      }
      if (isClosed || videoIndex >= warmedContent.videoUrls.length) return;
      final String url = warmedContent.videoUrls[videoIndex];
      controller = _controllerForUrl(url);
      try {
        await controller.initialize().timeout(_videoInitializeTimeout);
      } on TimeoutException catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('HomeCubit._playVideoAt timeout for $url: $e\n$st');
        }
        controller.dispose();
        if (isClosed) return;
        _skipToNextVideoOrPosters(warmedContent, videoIndex);
        return;
      } catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('HomeCubit._playVideoAt error for $url: $e\n$st');
        }
        controller.dispose();
        if (isClosed) return;
        _skipToNextVideoOrPosters(warmedContent, videoIndex);
        return;
      }
    }
    if (isClosed) {
      controller.dispose();
      return;
    }
    controller.setLooping(false);
    emit(
      HomeLoaded(
        content: warmedContent,
        videoController: controller,
        currentDisplayIndex: displayIndex,
      ),
    );
    _videoErrorListener = () {
      if (!controller!.value.hasError || isClosed) return;
      controller.removeListener(_videoErrorListener!);
      _videoErrorListener = null;
      controller.dispose();
      final s = state;
      if (s is HomeLoaded && s.videoController == controller) {
        emit(
          HomeLoaded(
            content: warmedContent,
            currentDisplayIndex: displayIndex,
            videoController: null,
          ),
        );
      }
      _skipToNextVideoOrPosters(warmedContent, videoIndex);
    };
    controller.addListener(_videoErrorListener!);
    controller.play();
    unawaited(_prepareNextDisplay(warmedContent, displayIndex));
    _scheduleNext(warmedContent, controller, displayIndex);
  }

  /// Pause video and rotation when app goes to background (no background playing).
  void pausePlayback() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    final s = state;
    if (s is HomeLoaded && s.videoController != null) {
      s.videoController!.pause();
    }
  }

  /// Resume video and rotation when app returns to foreground.
  void resumePlayback() {
    final s = state;
    if (s is! HomeLoaded) return;
    if (s.videoController != null) {
      s.videoController!.play();
      _scheduleNext(s.content, s.videoController, s.currentDisplayIndex);
    } else {
      _scheduleNext(s.content, null, s.currentDisplayIndex);
    }
  }

  void _removeVideoCompletionListener() {
    if (_videoCompletionListener != null &&
        _videoCompletionController != null) {
      _videoCompletionController!.removeListener(_videoCompletionListener!);
    }
    _videoCompletionListener = null;
    _videoCompletionController = null;
  }

  /// When a video fails to play, try the next video or return to posters.
  void _skipToNextVideoOrPosters(AdContent content, int failedVideoIndex) {
    if (isClosed) return;
    final int videoCount = content.videoUrls.length;
    if (failedVideoIndex + 1 < videoCount) {
      _playVideoAt(content, failedVideoIndex + 1);
    } else {
      emit(HomeLoaded(content: content, currentDisplayIndex: 0));
      _scheduleNext(content, null, 0);
    }
  }

  void _scheduleNext(
    AdContent content,
    VideoPlayerController? controller,
    int currentIndex,
  ) {
    _rotationTimer?.cancel();
    if (isClosed) return;

    final int posterCount = content.posterUrls.length;
    final int videoCount = content.videoUrls.length;

    if (currentIndex < posterCount) {
      _rotationTimer = Timer(_posterDuration, () {
        if (isClosed) return;
        if (_applyPendingPlaylistIfAny()) return;
        final int next = currentIndex + 1;
        if (next < posterCount) {
          emit(HomeLoaded(content: content, currentDisplayIndex: next));
          unawaited(_prepareNextDisplay(content, next));
          _scheduleNext(content, null, next);
        } else if (videoCount > 0) {
          _playVideoAt(content, 0);
        } else {
          emit(HomeLoaded(content: content, currentDisplayIndex: 0));
          _scheduleNext(content, null, 0);
        }
      });
      return;
    }

    final int videoIndex = currentIndex - posterCount;
    if (controller == null) {
      // Defensive: keep loop running even if controller was already disposed.
      if (videoCount > 0) {
        _playVideoAt(content, videoIndex.clamp(0, videoCount - 1));
      }
      return;
    }
    _removeVideoCompletionListener();
    final int slot = ++_videoSlotGeneration;
    _videoCompletionController = controller;
    _videoCompletionListener = () {
      if (isClosed) return;
      if (slot != _videoSlotGeneration) return;
      if (!controller.value.isInitialized) return;
      if (!controller.value.isCompleted) return;
      _rotationTimer?.cancel();
      _rotationTimer = null;
      _removeVideoCompletionListener();
      _finishVideoSlotAndAdvance(content, controller, videoIndex, slot);
    };
    controller.addListener(_videoCompletionListener!);

    final Duration videoDuration = controller.value.duration;
    final Duration fallback = videoDuration > Duration.zero
        ? videoDuration + const Duration(seconds: 3)
        : const Duration(minutes: 2);
    _rotationTimer = Timer(fallback, () {
      if (isClosed) return;
      if (slot != _videoSlotGeneration) return;
      _rotationTimer = null;
      _removeVideoCompletionListener();
      _finishVideoSlotAndAdvance(content, controller, videoIndex, slot);
    });
  }

  void _finishVideoSlotAndAdvance(
    AdContent content,
    VideoPlayerController controller,
    int videoIndex,
    int slot,
  ) {
    if (isClosed) return;
    if (slot != _videoSlotGeneration) return;
    _videoSlotGeneration++;
    if (_videoErrorListener != null) {
      controller.removeListener(_videoErrorListener!);
      _videoErrorListener = null;
    }
    controller.pause();
    controller.seekTo(Duration.zero);
    controller.dispose();
    if (_applyPendingPlaylistIfAny()) return;

    final int posterCount = content.posterUrls.length;
    final int videoCount = content.videoUrls.length;

    if (videoIndex + 1 < videoCount) {
      _playVideoAt(content, videoIndex + 1);
    } else if (posterCount > 0) {
      emit(HomeLoaded(content: content, currentDisplayIndex: 0));
      _scheduleNext(content, null, 0);
    } else {
      _playVideoAt(content, 0);
    }
  }

  bool _applyPendingPlaylistIfAny() {
    final AdContent? pending = _pendingPlaylistContent;
    if (pending == null || isClosed) return false;
    _pendingPlaylistContent = null;
    _clearPreparedVideo();
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _removeVideoCompletionListener();
    _videoSlotGeneration++;
    emit(HomeContentReady(content: pending));
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (isClosed) return;
      _startRotation(pending);
    });
    return true;
  }

  int _totalDisplayCount(AdContent content) =>
      content.posterUrls.length + content.videoUrls.length;

  int _nextDisplayIndex(AdContent content, int currentIndex) {
    final int total = _totalDisplayCount(content);
    if (total <= 0) return 0;
    return (currentIndex + 1) % total;
  }

  Future<void> _prepareNextDisplay(AdContent content, int currentIndex) async {
    if (isClosed || _isPreparingVideo) return;
    final int total = _totalDisplayCount(content);
    if (total <= 1 || content.videoUrls.isEmpty) return;

    final int nextIndex = _nextDisplayIndex(content, currentIndex);
    final int posterCount = content.posterUrls.length;
    if (nextIndex < posterCount) {
      // Posters are prefetched in UI layer one step ahead.
      return;
    }
    if (_preparedVideoController != null &&
        _preparedVideoDisplayIndex == nextIndex) {
      return;
    }

    final int videoIndex = nextIndex - posterCount;
    _isPreparingVideo = true;
    try {
      AdContent warmedContent = content;
      try {
        warmedContent = await _adsRepository
            .warmupForPlayback(content, videoIndex)
            .timeout(_warmupTimeout);
      } catch (_) {
        warmedContent = content;
      }
      if (isClosed || videoIndex >= warmedContent.videoUrls.length) return;
      final String url = warmedContent.videoUrls[videoIndex];
      final VideoPlayerController prepared = _controllerForUrl(url);
      await prepared.initialize().timeout(_videoInitializeTimeout);
      if (isClosed) {
        prepared.dispose();
        return;
      }
      prepared.setLooping(false);
      _clearPreparedVideo();
      _preparedVideoController = prepared;
      _preparedVideoDisplayIndex = nextIndex;
    } on TimeoutException {
      // Skip one-ahead preloading if warmup or init is too slow.
    } catch (_) {
      // Best-effort one-ahead preparation should never break playback.
    } finally {
      _isPreparingVideo = false;
    }
  }

  VideoPlayerController? _consumePreparedVideoIfMatches(int displayIndex) {
    final VideoPlayerController? prepared = _preparedVideoController;
    if (prepared == null) return null;
    if (_preparedVideoDisplayIndex != displayIndex) return null;
    _preparedVideoController = null;
    _preparedVideoDisplayIndex = null;
    return prepared;
  }

  void _clearPreparedVideo() {
    final VideoPlayerController? prepared = _preparedVideoController;
    _preparedVideoController = null;
    _preparedVideoDisplayIndex = null;
    if (prepared != null) {
      prepared.dispose();
    }
  }

  @override
  Future<void> close() async {
    await _campaignSocket.dispose();
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _initialLoadingIndicatorTimer?.cancel();
    _initialLoadingIndicatorTimer = null;
    _removeVideoCompletionListener();
    _clearPreparedVideo();
    final state = this.state;
    if (state is HomeLoaded && state.videoController != null) {
      final c = state.videoController!;
      if (_videoErrorListener != null) {
        c.removeListener(_videoErrorListener!);
        _videoErrorListener = null;
      }
      c.dispose();
    }
    return super.close();
  }
}
