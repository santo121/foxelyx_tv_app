import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/domain/repositories/auth_repository.dart';
import '../../domain/campaign_playlist_socket.dart';
import '../../domain/entities/ad_content.dart';
import '../../domain/exceptions/playlist_auth_required_exception.dart';
import '../../domain/entities/preloaded_ads_holder.dart';
import '../../domain/repositories/ads_repository.dart';
import 'home_state.dart';

/// Single video controller at a time; init next when advancing to next video slot.
/// Posters and videos are shown in order: each poster 20s, then each video for its duration.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._adsRepository, this._campaignSocket, this._authRepository)
    : super(const HomeInitial());

  final AdsRepository _adsRepository;
  final CampaignPlaylistSocket _campaignSocket;
  final AuthRepository _authRepository;
  static const Duration _posterDuration = Duration(seconds: 20);
  static const Duration _warmupTimeout = Duration(seconds: 8);
  static const Duration _videoInitializeTimeout = Duration(seconds: 45);
  static const Duration _videoInitLockWait = Duration(seconds: 2);
  static const Duration _videoControllerReleaseGap = Duration(
    milliseconds: 300,
  );
  static const Duration _videoDurationSafetyBuffer = Duration(seconds: 10);
  static const Duration _unknownDurationFallback = Duration(minutes: 40);
  static const int _maxVideoRetryCount = 3;
  static const Duration _videoRetryDelay = Duration(milliseconds: 1500);
  static const Duration _videoStallRecoveryTimeout = Duration(seconds: 20);
  static const Duration _nearEndTolerance = Duration(seconds: 2);
  static const bool _enableNextVideoPreload = false;
  Timer? _rotationTimer;
  VoidCallback? _videoErrorListener;
  VoidCallback? _videoHealthListener;
  VoidCallback? _videoCompletionListener;
  VideoPlayerController? _videoCompletionController;
  VideoPlayerController? _videoHealthController;
  Timer? _videoStallTimer;
  int _videoSlotGeneration = 0;
  AdContent? _pendingPlaylistContent;
  bool _isRefreshInFlight = false;
  bool _refreshRequestedWhileInFlight = false;
  VideoPlayerController? _preparedVideoController;
  int? _preparedVideoDisplayIndex;
  bool _isPreparingVideo = false;
  bool _isInitializingVideoController = false;
  bool _isAuthRecoveryInFlight = false;
  bool _isPausedByLifecycle = false;
  Timer? _initialLoadingIndicatorTimer;
  final Map<String, int> _videoRetryByUrl = <String, int>{};

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
        _initialLoadingIndicatorTimer = Timer(
          const Duration(milliseconds: 1200),
          () {
            if (isClosed) return;
            final HomeState current = state;
            if (current is HomeInitial) {
              emit(const HomeLoading());
            }
          },
        );
        content = await _getAdsWithAuthRecovery();
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
      if (!isClosed) emit(HomeError(_toUserMessage(e)));
    }
  }

  /// Called when the devices socket connects or campaign events fire — fetches latest playlist.
  Future<void> refreshPlaylistFromServer() async {
    if (isClosed) return;
    if (state is HomeLoading) return;
    if (_isRefreshInFlight) {
      // Coalesce rapid socket events so we always run one trailing refresh.
      _refreshRequestedWhileInFlight = true;
      return;
    }
    _isRefreshInFlight = true;
    try {
      do {
        _refreshRequestedWhileInFlight = false;
        final AdContent content = await _refreshAdsWithAuthRecovery();
        if (isClosed) return;
        if (_shouldApplyPlaylistImmediately()) {
          await _applyPlaylistImmediately(content);
        } else {
          // Queue playlist refresh and apply only at ad boundary.
          _pendingPlaylistContent = content;
        }
      } while (_refreshRequestedWhileInFlight && !isClosed);
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('HomeCubit.refreshPlaylistFromServer error: $e\n$st');
      }
    } finally {
      _isRefreshInFlight = false;
    }
  }

  Future<AdContent> _getAdsWithAuthRecovery() async {
    try {
      return await _adsRepository.getAds();
    } on PlaylistAuthRequiredException {
      final bool recovered = await _recoverAuthAndStartSocket();
      if (!recovered) rethrow;
      return _adsRepository.refreshAds();
    }
  }

  Future<AdContent> _refreshAdsWithAuthRecovery() async {
    try {
      return await _adsRepository.refreshAds();
    } on PlaylistAuthRequiredException {
      final bool recovered = await _recoverAuthAndStartSocket();
      if (!recovered) rethrow;
      return _adsRepository.refreshAds();
    }
  }

  Future<bool> _recoverAuthAndStartSocket() async {
    if (_isAuthRecoveryInFlight) return false;
    _isAuthRecoveryInFlight = true;
    try {
      final bool refreshed = await _authRepository.refreshDeviceAuth();
      if (!refreshed || isClosed) return false;
      await _campaignSocket.start(
        onPlaylistRefresh: () {
          unawaited(refreshPlaylistFromServer());
        },
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _isAuthRecoveryInFlight = false;
    }
  }

  /// Only [AdContent.videoUrls] are played; playlist YouTube entries are dropped upstream.
  List<String> _getActiveMediaUrls(AdContent content) => content.videoUrls;

  void _startRotation(AdContent content) {
    if (isClosed) return;
    _clearPreparedVideo();
    final int posterCount = content.posterUrls.length;
    if (_getActiveMediaUrls(content).isEmpty) {
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
      return VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      );
    }
    if (url.startsWith('assets/')) {
      return VideoPlayerController.asset(url);
    }
    return VideoPlayerController.file(File(url));
  }

  Future<void> _playVideoAt(AdContent content, int videoIndex) async {
    if (isClosed || videoIndex >= _getActiveMediaUrls(content).length) return;
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
      if (isClosed || videoIndex >= _getActiveMediaUrls(warmedContent).length) return;
      final String url = _getActiveMediaUrls(warmedContent)[videoIndex];

      controller = _controllerForUrl(url);
      try {
        final bool acquired = await _acquireVideoInitLock(waitIfBusy: true);
        if (!acquired) {
          await _safeDisposeVideoController(controller);
          if (isClosed) return;
          _skipToNextVideoOrPosters(warmedContent, videoIndex);
          return;
        }
        try {
          await Future<void>.delayed(_videoControllerReleaseGap);
          await controller.initialize().timeout(_videoInitializeTimeout);
        } finally {
          _releaseVideoInitLock();
        }
      } on TimeoutException catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('HomeCubit._playVideoAt timeout for $url: $e\n$st');
        }
        await _safeDisposeVideoController(controller);
        if (isClosed) return;
        unawaited(_retryCurrentVideoOrSkip(warmedContent, videoIndex));
        return;
      } catch (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('HomeCubit._playVideoAt error for $url: $e\n$st');
        }
        await _safeDisposeVideoController(controller);
        if (isClosed) return;
        unawaited(_retryCurrentVideoOrSkip(warmedContent, videoIndex));
        return;
      }
    }
    if (isClosed) {
      await _safeDisposeVideoController(controller);
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
      unawaited(
        _handleVideoPlaybackError(
          controller: controller,
          content: warmedContent,
          displayIndex: displayIndex,
          videoIndex: videoIndex,
        ),
      );
    };
    controller.addListener(_videoErrorListener!);
    controller.play();
    _attachVideoHealthMonitor(
      controller: controller,
      content: warmedContent,
      displayIndex: displayIndex,
    );
    // remove from retry map
    if (videoIndex < _getActiveMediaUrls(warmedContent).length) {
      _videoRetryByUrl.remove(_getActiveMediaUrls(warmedContent)[videoIndex]);
    }
    if (_enableNextVideoPreload) {
      unawaited(_prepareNextDisplay(warmedContent, displayIndex));
    }
    _scheduleNext(warmedContent, controller, displayIndex);
  }

  /// Pause video and rotation when app goes to background (no background playing).
  void pausePlayback() {
    _isPausedByLifecycle = true;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _cancelVideoStallMonitor();
    final s = state;
    if (s is HomeLoaded && s.videoController != null) {
      s.videoController!.pause();
    }
  }

  /// Resume video and rotation when app returns to foreground.
  void resumePlayback() {
    _isPausedByLifecycle = false;
    final s = state;
    if (s is! HomeLoaded) return;
    if (s.videoController != null) {
      s.videoController!.play();
      _attachVideoHealthMonitor(
        controller: s.videoController!,
        content: s.content,
        displayIndex: s.currentDisplayIndex,
      );
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

  void _removeVideoHealthListener() {
    _cancelVideoStallMonitor();
    if (_videoHealthListener != null && _videoHealthController != null) {
      _videoHealthController!.removeListener(_videoHealthListener!);
    }
    _videoHealthListener = null;
    _videoHealthController = null;
  }

  void _cancelVideoStallMonitor() {
    _videoStallTimer?.cancel();
    _videoStallTimer = null;
  }

  void _attachVideoHealthMonitor({
    required VideoPlayerController controller,
    required AdContent content,
    required int displayIndex,
  }) {
    _removeVideoHealthListener();
    _videoHealthController = controller;
    _videoHealthListener = () {
      if (isClosed || _isPausedByLifecycle) {
        _cancelVideoStallMonitor();
        return;
      }
      final VideoPlayerValue value = controller.value;
      if (!value.isInitialized || value.isCompleted || value.hasError) {
        _cancelVideoStallMonitor();
        return;
      }
      final bool nearEnd =
          value.duration > Duration.zero &&
          value.position >= (value.duration - _nearEndTolerance);
      final bool stalled =
          !nearEnd &&
          (value.isBuffering ||
              (!value.isPlaying && value.position > Duration.zero));
      if (!stalled) {
        _cancelVideoStallMonitor();
        return;
      }
      if (_videoStallTimer != null) return;
      _videoStallTimer = Timer(_videoStallRecoveryTimeout, () {
        _videoStallTimer = null;
        if (isClosed || _isPausedByLifecycle) return;
        final HomeState current = state;
        if (current is! HomeLoaded || current.videoController != controller) {
          return;
        }
        final int posterCount = content.posterUrls.length;
        final int videoIndex = displayIndex - posterCount;
        if (videoIndex < 0 || videoIndex >= _getActiveMediaUrls(content).length) return;
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'HomeCubit detected stalled video. Triggering recovery for index=$videoIndex',
          );
        }
        unawaited(_retryCurrentVideoOrSkip(content, videoIndex));
      });
    };
    controller.addListener(_videoHealthListener!);
  }

  /// When a video fails to play, try the next video or return to posters.
  void _skipToNextVideoOrPosters(AdContent content, int failedVideoIndex) {
    if (isClosed) return;
    if (failedVideoIndex >= 0 && failedVideoIndex < _getActiveMediaUrls(content).length) {
      _videoRetryByUrl.remove(_getActiveMediaUrls(content)[failedVideoIndex]);
    }
    final int videoCount = _getActiveMediaUrls(content).length;
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
    final int videoCount = _getActiveMediaUrls(content).length;

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
      if (_applyPendingPlaylistIfAny()) return;
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
      unawaited(
        _finishVideoSlotAndAdvance(content, controller, videoIndex, slot),
      );
    };
    controller.addListener(_videoCompletionListener!);

    final Duration videoDuration = controller.value.duration;
    final Duration fallback = videoDuration > Duration.zero
        ? videoDuration + _videoDurationSafetyBuffer
        : _unknownDurationFallback;
    _rotationTimer = Timer(fallback, () {
      if (isClosed) return;
      if (slot != _videoSlotGeneration) return;
      _rotationTimer = null;
      _removeVideoCompletionListener();
      unawaited(
        _finishVideoSlotAndAdvance(content, controller, videoIndex, slot),
      );
    });
  }

  Future<void> _finishVideoSlotAndAdvance(
    AdContent content,
    VideoPlayerController controller,
    int videoIndex,
    int slot,
  ) async {
    if (isClosed) return;
    if (slot != _videoSlotGeneration) return;
    if (videoIndex >= 0 && videoIndex < _getActiveMediaUrls(content).length) {
      final String url = _getActiveMediaUrls(content)[videoIndex];
      unawaited(_cachePlayedVideoBestEffort(url));
    }
    _videoSlotGeneration++;
    _removeVideoHealthListener();
    if (_videoErrorListener != null) {
      controller.removeListener(_videoErrorListener!);
      _videoErrorListener = null;
    }
    try {
      await controller.pause();
      await controller.seekTo(Duration.zero);
    } catch (_) {}
    await _safeDisposeVideoController(controller);
    await Future<void>.delayed(_videoControllerReleaseGap);
    if (_applyPendingPlaylistIfAny()) return;

    final int posterCount = content.posterUrls.length;
    final int videoCount = _getActiveMediaUrls(content).length;

    if (videoIndex + 1 < videoCount) {
      if (videoIndex >= 0 && videoIndex < _getActiveMediaUrls(content).length) {
        _videoRetryByUrl.remove(_getActiveMediaUrls(content)[videoIndex]);
      }
      _playVideoAt(content, videoIndex + 1);
    } else {
      if (posterCount > 0) {
        emit(HomeLoaded(content: content, currentDisplayIndex: 0));
        _scheduleNext(content, null, 0);
      } else {
        _playVideoAt(content, 0);
      }
    }
  }

  bool _applyPendingPlaylistIfAny() {
    final AdContent? pending = _pendingPlaylistContent;
    if (pending == null || isClosed) return false;
    _pendingPlaylistContent = null;
    _replaceCurrentPlaylist(pending);
    return true;
  }

  bool _shouldApplyPlaylistImmediately() {
    final HomeState current = state;
    if (current is HomeInitial || current is HomeContentReady) {
      return true;
    }
    if (current is HomeLoaded) {
      return _isPlaylistEmpty(current.content);
    }
    return false;
  }

  bool _isPlaylistEmpty(AdContent content) =>
      content.posterUrls.isEmpty && _getActiveMediaUrls(content).isEmpty;

  Future<void> _applyPlaylistImmediately(AdContent content) async {
    _pendingPlaylistContent = null;
    _replaceCurrentPlaylist(content);
  }

  void _replaceCurrentPlaylist(AdContent content) {
    if (isClosed) return;
    _clearPreparedVideo();
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _removeVideoCompletionListener();
    _removeVideoHealthListener();
    _videoSlotGeneration++;
    emit(HomeContentReady(content: content));
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      unawaited(_applyPendingPlaylistAndStart(content));
    });
  }

  Future<void> _applyPendingPlaylistAndStart(AdContent pending) async {
    if (isClosed) return;
    await _purgeStaleVideoCacheBestEffort(pending);
    if (isClosed) return;
    _startRotation(pending);
  }

  Future<void> _purgeStaleVideoCacheBestEffort(AdContent pending) async {
    try {
      await _adsRepository
          .purgeMissingCachedVideos(pending.videoUrls.toSet())
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Keep playback flow uninterrupted if purge fails.
    }
  }

  Future<void> _cachePlayedVideoBestEffort(String url) async {
    if (!url.startsWith('http')) return;
    try {
      await _adsRepository.cachePlayedVideo(url);
    } catch (_) {
      // Keep playback flow uninterrupted if caching fails.
    }
  }

  int _totalDisplayCount(AdContent content) =>
      content.posterUrls.length + _getActiveMediaUrls(content).length;

  int _nextDisplayIndex(AdContent content, int currentIndex) {
    final int total = _totalDisplayCount(content);
    if (total <= 0) return 0;
    return (currentIndex + 1) % total;
  }

  Future<void> _prepareNextDisplay(AdContent content, int currentIndex) async {
    if (!_enableNextVideoPreload) return;
    if (isClosed || _isPreparingVideo || _isInitializingVideoController) return;
    final int total = _totalDisplayCount(content);
    if (total <= 1 || _getActiveMediaUrls(content).isEmpty) return;

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
      if (isClosed || videoIndex >= _getActiveMediaUrls(warmedContent).length) return;
      final String url = _getActiveMediaUrls(warmedContent)[videoIndex];

      final VideoPlayerController prepared = _controllerForUrl(url);
      final bool acquired = await _acquireVideoInitLock();
      if (!acquired) {
        await _safeDisposeVideoController(prepared);
        return;
      }
      try {
        await prepared.initialize().timeout(_videoInitializeTimeout);
      } finally {
        _releaseVideoInitLock();
      }
      if (isClosed) {
        await _safeDisposeVideoController(prepared);
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
    if (_preparedVideoDisplayIndex != displayIndex) {
      _clearPreparedVideo();
      return null;
    }
    _preparedVideoController = null;
    _preparedVideoDisplayIndex = null;
    return prepared;
  }

  Future<bool> _acquireVideoInitLock({bool waitIfBusy = false}) async {
    if (!waitIfBusy) {
      if (_isInitializingVideoController) return false;
      _isInitializingVideoController = true;
      return true;
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    while (_isInitializingVideoController &&
        stopwatch.elapsed < _videoInitLockWait) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (isClosed) return false;
    }
    if (_isInitializingVideoController) return false;
    _isInitializingVideoController = true;
    return true;
  }

  void _releaseVideoInitLock() {
    _isInitializingVideoController = false;
  }

  void _clearPreparedVideo() {
    final VideoPlayerController? prepared = _preparedVideoController;
    _preparedVideoController = null;
    _preparedVideoDisplayIndex = null;
    if (prepared != null) {
      unawaited(_safeDisposeVideoController(prepared));
    }
  }

  Future<void> _handleVideoPlaybackError({
    required VideoPlayerController controller,
    required AdContent content,
    required int displayIndex,
    required int videoIndex,
  }) async {
    _removeVideoHealthListener();
    await _safeDisposeVideoController(controller);
    final HomeState s = state;
    if (s is HomeLoaded && s.videoController == controller && !isClosed) {
      emit(
        HomeLoaded(
          content: content,
          currentDisplayIndex: displayIndex,
          videoController: null,
        ),
      );
    }
    if (!isClosed) {
      unawaited(_retryCurrentVideoOrSkip(content, videoIndex));
    }
  }

  Future<void> _retryCurrentVideoOrSkip(
    AdContent content,
    int videoIndex,
  ) async {
    if (isClosed || videoIndex < 0 || videoIndex >= _getActiveMediaUrls(content).length) {
      return;
    }
    final String url = _getActiveMediaUrls(content)[videoIndex];
    final int attempts = _videoRetryByUrl[url] ?? 0;
    if (attempts >= _maxVideoRetryCount) {
      _videoRetryByUrl.remove(url);
      _skipToNextVideoOrPosters(content, videoIndex);
      return;
    }
    _videoRetryByUrl[url] = attempts + 1;
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        'HomeCubit retrying video ($videoIndex) attempt ${attempts + 1}/$_maxVideoRetryCount: $url',
      );
    }
    await Future<void>.delayed(_videoRetryDelay);
    if (isClosed) return;
    _playVideoAt(content, videoIndex);
  }

  Future<void> _safeDisposeVideoController(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (_) {}
  }

  String _toUserMessage(Object error) {
    if (error is TimeoutException) {
      return 'The connection is slow. Please check your network and try again.';
    }
    if (error is SocketException) {
      return 'No internet connection. Please connect to a network and retry.';
    }
    if (error is PlaylistAuthRequiredException) {
      return 'Your session expired. Please sign in again.';
    }
    if (error is StateError) {
      return 'Device setup is incomplete. Please sign in and try again.';
    }
    return 'Unable to load ads right now. Please try again.';
  }

  @override
  Future<void> close() async {
    await _campaignSocket.dispose();
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _removeVideoHealthListener();
    _initialLoadingIndicatorTimer?.cancel();
    _initialLoadingIndicatorTimer = null;
    _removeVideoCompletionListener();
    _clearPreparedVideo();
    _isInitializingVideoController = false;
    final state = this.state;
    if (state is HomeLoaded && state.videoController != null) {
      final c = state.videoController!;
      if (_videoErrorListener != null) {
        c.removeListener(_videoErrorListener!);
        _videoErrorListener = null;
      }
      await _safeDisposeVideoController(c);
    }
    return super.close();
  }
}
