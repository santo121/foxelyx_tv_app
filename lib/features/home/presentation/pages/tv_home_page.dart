import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../../../core/utils/ext_cache_manager.dart';
import '../../../../core/utils/image_display_decode_size.dart';
import '../../../../widgets/news_ticker_overlay.dart';

import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';
import '../widgets/ad_poster_image.dart';
import '../widgets/ad_poster_pdf.dart';
import '../widgets/video_ad_player.dart';

/// Dumb UI: no API calls, no business logic. Only cubit.loadAds() and BlocBuilder.
class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> with WidgetsBindingObserver {
  String? _lastPrefetchedPosterUrl;
  bool _rotatePostersPortrait = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPosterLayoutFromSession());
  }

  /// When API [VehicleSession.screenType] is PORTRAIT, rotate poster assets 90° on this landscape TV.
  Future<void> _loadPosterLayoutFromSession() async {
    final session = await getIt<AuthRepository>().getStoredSession();
    if (!mounted) return;
    final bool portrait =
        (session?.screenType ?? '').trim().toUpperCase() == 'PORTRAIT';
    setState(() {
      _rotatePostersPortrait = portrait;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<HomeCubit>().pausePlayback();
    } else if (state == AppLifecycleState.resumed) {
      context.read<HomeCubit>().resumePlayback();
    }
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  Widget build(BuildContext context) {
    final Widget adsPane = BlocConsumer<HomeCubit, HomeState>(
      listener: (BuildContext context, HomeState state) {
        if (state is! HomeLoaded) return;
        unawaited(_prefetchNextPosterIfNeeded(context, state));
      },
      builder: (BuildContext context, HomeState state) {
        if (state is HomeLoading) {
          return const _InitialAdsLoadingView();
        }
        if (state is HomeError) {
          return _HomeErrorView(
            message: state.message,
            onRetry: () => context.read<HomeCubit>().loadAds(),
          );
        }
        if (state is HomeContentReady) {
          final bool isPlaylistEmpty =
              state.content.posterUrls.isEmpty &&
              state.content.videoUrls.isEmpty;
          if (isPlaylistEmpty) {
            return const _EmptyPlaylistView();
          }
          return _HomeLayout(
            posterUrls: state.content.posterUrls,
            videoController: null,
            currentDisplayIndex: 0,
            rotatePostersPortrait: _rotatePostersPortrait,
          );
        }
        if (state is HomeLoaded) {
          final bool isPlaylistEmpty =
              state.content.posterUrls.isEmpty &&
              state.content.videoUrls.isEmpty;
          if (isPlaylistEmpty) {
            return const _EmptyPlaylistView();
          }
          return _HomeLayout(
            posterUrls: state.content.posterUrls,
            videoController: state.videoController,
            currentDisplayIndex: state.currentDisplayIndex,
            rotatePostersPortrait: _rotatePostersPortrait,
          );
        }
        return const SizedBox.shrink();
      },
    );

    // LANDSCAPE screenType: horizontal ticker along the bottom of the screen.
    // PORTRAIT screenType: left rail with vertical scrolling — matches poster orientation.
    final Widget body = _rotatePostersPortrait
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const NewsTickerOverlay(
                layout: NewsTickerLayout.portraitPosterLeftRail,
              ),
              Expanded(child: adsPane),
            ],
          )
        : Column(
            children: <Widget>[
              Expanded(child: adsPane),
              const NewsTickerOverlay(),
            ],
          );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FocusScope(
          child: body,
        ),
      ),
    );
  }

  Future<void> _prefetchNextPosterIfNeeded(
    BuildContext context,
    HomeLoaded state,
  ) async {
    final int posterCount = state.content.posterUrls.length;
    final int totalCount = posterCount + state.content.videoUrls.length;
    if (posterCount == 0 || totalCount <= 1) return;

    final int nextIndex = (state.currentDisplayIndex + 1) % totalCount;
    if (nextIndex >= posterCount) return;

    final String posterUrl = state.content.posterUrls[nextIndex];
    if (posterUrl.toLowerCase().endsWith('.pdf')) return;
    if (!AdPosterImage.isNetworkUrl(posterUrl)) return;
    if (_lastPrefetchedPosterUrl == posterUrl) return;

    final Size size = MediaQuery.sizeOf(context);
    final double dpr = displayPixelRatioOf(context);
    final int cacheWidth = decodePixelsAlong(size.width, dpr);
    final int cacheHeight = decodePixelsAlong(size.height, dpr);
    final ImageProvider provider = CachedNetworkImageProvider(
      posterUrl,
      cacheManager: ExtCacheManager.instance,
      maxWidth: cacheWidth,
      maxHeight: cacheHeight,
    );
    try {
      await precacheImage(provider, context);
      _lastPrefetchedPosterUrl = posterUrl;
    } catch (_) {
      // Ignore prefetch failures; active poster will still load on demand.
    }
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B14),
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white70,
                  size: 74,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Connection Problem',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 22,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Press Retry to reconnect.',
                  style: TextStyle(color: Colors.white54, fontSize: 18),
                ),
                const SizedBox(height: 30),
                FocusableActionDetector(
                  autofocus: true,
                  actions: <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (ActivateIntent intent) {
                        onRetry();
                        return null;
                      },
                    ),
                  },
                  child: Builder(
                    builder: (BuildContext context) {
                      final bool hasFocus = Focus.of(context).hasFocus;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 120),
                        scale: hasFocus ? 1.02 : 1,
                        child: ElevatedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            foregroundColor: const Color(0xFF06122A),
                            backgroundColor: hasFocus
                                ? const Color(0xFFE4EEFF)
                                : const Color(0xFFD5E3FF),
                            side: BorderSide(
                              color: hasFocus
                                  ? const Color(0xFF8CB0FF)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeLayout extends StatelessWidget {
  const _HomeLayout({
    required this.posterUrls,
    this.videoController,
    this.currentDisplayIndex = 0,
    this.rotatePostersPortrait = false,
  });

  final List<String> posterUrls;
  final VideoPlayerController? videoController;
  final int currentDisplayIndex;
  final bool rotatePostersPortrait;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double dpr = displayPixelRatioOf(context);
        final int pxCanvasW = decodePixelsAlong(width, dpr);
        final int pxCanvasH = decodePixelsAlong(height, dpr);
        final int pxRotW = decodePixelsAlong(height, dpr);
        final int pxRotH = decodePixelsAlong(width, dpr);

        final bool showingVideo =
            videoController != null && currentDisplayIndex >= posterUrls.length;
        final bool showingPoster =
            posterUrls.isNotEmpty && currentDisplayIndex < posterUrls.length;

        Widget content;
        if (showingVideo) {
          if (rotatePostersPortrait) {
            content = RotatedBox(
              quarterTurns: 1,
              child: SizedBox(
                width: height,
                height: width,
                child: VideoAdPlayer(controller: videoController!),
              ),
            );
          } else {
            content = VideoAdPlayer(controller: videoController!);
          }
        } else if (showingPoster) {
          final String posterUrl = posterUrls[currentDisplayIndex];
          final bool isPdf = posterUrl.toLowerCase().endsWith('.pdf');
          if (rotatePostersPortrait) {
            content = RotatedBox(
              quarterTurns: 1,
              child: SizedBox(
                width: height,
                height: width,
                child: isPdf
                    ? AdPosterPdf(
                        assetPath: posterUrl,
                        width: height,
                        height: width,
                        cacheWidth: pxRotW,
                        cacheHeight: pxRotH,
                        fit: BoxFit.cover,
                      )
                    : AdPosterImage(
                        url: posterUrl,
                        width: height,
                        height: width,
                        cacheWidth: pxRotW,
                        cacheHeight: pxRotH,
                        fit: BoxFit.cover,
                      ),
              ),
            );
          } else {
            content = isPdf
                ? AdPosterPdf(
                    assetPath: posterUrl,
                    width: width,
                    height: height,
                    cacheWidth: pxCanvasW,
                    cacheHeight: pxCanvasH,
                    fit: BoxFit.cover,
                  )
                : AdPosterImage(
                    url: posterUrl,
                    width: width,
                    height: height,
                    cacheWidth: pxCanvasW,
                    cacheHeight: pxCanvasH,
                    fit: BoxFit.cover,
                  );
          }
        } else {
          content = const _VideoPlaceholder();
        }

        return RepaintBoundary(
          child: SizedBox.expand(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.center,
                child: SizedBox(width: width, height: height, child: content),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight placeholder while video initializes off the first frame.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: RepaintBoundary(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}

class _EmptyPlaylistView extends StatelessWidget {
  const _EmptyPlaylistView();
  static const String _adsPhoneNumber = '+91 87140 10234';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight;
        final double dpr = MediaQuery.devicePixelRatioOf(context);
        final double logoWidth = height * 0.48;
        final double logoHeight = height * 0.48;
        final int cacheWidth = decodePixelsAlong(logoWidth, dpr);
        final int cacheHeight = decodePixelsAlong(logoHeight, dpr);

        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Image.asset(
                  'assets/logo/foxelyx_logo.png',
                  width: logoWidth,
                  height: logoHeight,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Show your ads on this TV',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.call_rounded, color: Colors.white, size: 32),
                    SizedBox(width: 10),
                    Text(
                      _adsPhoneNumber,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Call now',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InitialAdsLoadingView extends StatelessWidget {
  const _InitialAdsLoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black);
  }
}
