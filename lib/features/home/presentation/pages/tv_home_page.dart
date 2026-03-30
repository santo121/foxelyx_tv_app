import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

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

class _TvHomePageState extends State<TvHomePage>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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
        body: BlocBuilder<HomeCubit, HomeState>(
          builder: (BuildContext context, HomeState state) {
            if (state is HomeLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            if (state is HomeError) {
              return Center(
                child: Text(
                  state.message,
                  style: const TextStyle(color: Colors.white),
                ),
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
