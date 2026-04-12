import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FocusScope(
          child: BlocConsumer<HomeCubit, HomeState>(
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
                return _HomeLayout(
                  posterUrls: state.content.posterUrls,
                  videoController: null,
                  currentDisplayIndex: 0,
                );
              }
              if (state is HomeLoaded) {
                return _HomeLayout(
                  posterUrls: state.content.posterUrls,
                  videoController: state.videoController,
                  currentDisplayIndex: state.currentDisplayIndex,
                );
              }
              return const SizedBox.shrink();
            },
          ),
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
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int cacheWidth = (size.width * dpr).clamp(200.0, 1920.0).toInt();
    final int cacheHeight = (size.height * dpr).clamp(200.0, 1080.0).toInt();
    final ImageProvider provider = CachedNetworkImageProvider(
      posterUrl,
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
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 18,
                  ),
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
  });

  final List<String> posterUrls;
  final VideoPlayerController? videoController;
  final int currentDisplayIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final int cacheHeight = height.clamp(200.0, 1080.0).toInt();
        final int cacheWidth = width.clamp(200.0, 1920.0).toInt();

        final bool showingVideo =
            videoController != null && currentDisplayIndex >= posterUrls.length;
        final bool showingPoster =
            posterUrls.isNotEmpty && currentDisplayIndex < posterUrls.length;

        Widget content;
        if (showingVideo) {
          content = VideoAdPlayer(controller: videoController!);
        } else if (showingPoster) {
          final String posterUrl = posterUrls[currentDisplayIndex];
          final bool isPdf = posterUrl.toLowerCase().endsWith('.pdf');
          content = isPdf
              ? AdPosterPdf(
                  assetPath: posterUrl,
                  width: width,
                  height: height,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  fit: BoxFit.cover,
                )
              : AdPosterImage(
                  url: posterUrl,
                  width: width,
                  height: height,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                  fit: BoxFit.cover,
                );
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

class _InitialAdsLoadingView extends StatelessWidget {
  const _InitialAdsLoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black);
  }
}
