import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/pages/splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Low-memory tuning for ~1 GB RAM: cap in-memory image cache.
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 30;
  imageCache.maximumSizeBytes = 30 * 1024 * 1024;

  await setupDi();

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
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonSelect):
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
