import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/pages/splash_page.dart';
import 'features/home/domain/entities/ad_content.dart';
import 'features/home/domain/entities/preloaded_ads_holder.dart';
import 'features/home/domain/repositories/ads_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setupDi();

  // Prefetch ads while native splash is still visible (cache warm-up; HomeCubit will use this).
  try {
    final AdContent content = await getIt<AdsRepository>().getAds();
    PreloadedAdsHolder.instance.set(content);
  } catch (_) {
    // Ignore; HomeCubit will fetch on loadAds() if holder is empty.
  }

  // Low-memory tuning for ~1 GB RAM: limit image cache
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 25;
  cache.maximumSizeBytes = 15 * 1024 * 1024;

  // Default: landscape only (TV/bus ad display). Ads orientation is landscape.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>(
      create: (_) => getIt<AuthCubit>(),
      child: Shortcuts(
        // Only map TV remote OK (Select) to ActivateIntent so that Enter/Space
        // reach the TextField for typing (registration number).
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.select):
              const ActivateIntent(),
        },
        child: MaterialApp(
          title: 'foxelyx',
          theme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.black,
          ),
          builder: (BuildContext context, Widget? child) {
            return MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              removeLeft: true,
              removeRight: true,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashPage(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
