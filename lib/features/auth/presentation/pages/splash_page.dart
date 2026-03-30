import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future<void>.delayed(_splashDuration);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const AuthGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Match native splash: dark indigo background + centered logo
    const Color splashBackground = Color(0xFF1A1B3D);
    return Scaffold(
      backgroundColor: splashBackground,
      body: RepaintBoundary(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Image.asset(
              'assets/logo/foxelyx_logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
              cacheWidth: 800,
              cacheHeight: 600,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.tv, size: 120, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
