import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/domain/entities/vehicle_session.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../../home/domain/campaign_playlist_socket.dart';
import '../../../home/domain/entities/ad_content.dart';
import '../../../home/domain/entities/preloaded_ads_holder.dart';
import '../../../home/domain/repositories/ads_repository.dart';
import '../../../home/presentation/cubit/home_cubit.dart';
import '../../../home/presentation/pages/tv_home_page.dart';
import 'auth_gate.dart';

/// Full-screen FOXELYX splash. Shown as first frame so user always sees branding.
/// Navigates to [AuthGate] after a short delay.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const Duration _splashDuration = Duration(seconds: 2);
  static const Duration _maxBootstrapFetchWait = Duration(seconds: 2);
  bool _isPrimingAds = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapAndNavigate());
  }

  Future<void> _bootstrapAndNavigate() async {
    final DateTime start = DateTime.now();
    try {
      final AuthRepository authRepository = getIt<AuthRepository>();
      final VehicleSession? session = await authRepository.getStoredSession();
      final bool hasValidSession =
          session != null &&
          (session.accessToken?.isNotEmpty ?? false) &&
          (session.secret?.isNotEmpty ?? false);

      if (!hasValidSession) {
        await _waitForMinimumSplash(start);
        _goToAuthGate();
        return;
      }

      final AdsRepository adsRepository = getIt<AdsRepository>();
      final CampaignPlaylistSocket campaignSocket = getIt<CampaignPlaylistSocket>();

      await campaignSocket.start(
        onPlaylistRefresh: () {
          unawaited(_fetchPlaylistAndPrimeInitialAd(adsRepository));
        },
      );
      try {
        await _fetchPlaylistAndPrimeInitialAd(
          adsRepository,
        ).timeout(_maxBootstrapFetchWait);
      } catch (_) {
        // Don't block splash too long; HomeCubit can continue with direct stream.
      }
      await _waitForMinimumSplash(start);
      _goToHome();
    } catch (_) {
      await _waitForMinimumSplash(start);
      _goToAuthGate();
    }
  }

  Future<void> _fetchPlaylistAndPrimeInitialAd(AdsRepository repository) async {
    if (_isPrimingAds) return;
    _isPrimingAds = true;
    try {
      final AdContent content = await repository.refreshAds();
      PreloadedAdsHolder.instance.set(content);
    } finally {
      _isPrimingAds = false;
    }
  }

  Future<void> _waitForMinimumSplash(DateTime start) async {
    final Duration elapsed = DateTime.now().difference(start);
    final Duration remaining = _splashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  void _goToAuthGate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<HomeCubit>(
          create: (_) {
            final HomeCubit cubit = getIt<HomeCubit>();
            cubit.loadAds();
            return cubit;
          },
          child: const TvHomePage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Match native splash: dark indigo background + centered logo
    const Color splashBackground = Color(0xFF1A1B3D);
    final Size size = MediaQuery.sizeOf(context);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int cacheWidth = (size.width * 0.5 * dpr)
        .clamp(480.0, 1280.0)
        .toInt();
    final int cacheHeight = (size.width * 0.5 * dpr)
        .clamp(480.0, 1280.0)
        .toInt();
    return Scaffold(
      backgroundColor: splashBackground,
      body: RepaintBoundary(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo/foxelyx_logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.tv, size: 120, color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
