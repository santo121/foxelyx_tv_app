import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/vehicle_session.dart';
import '../../../../core/domain/repositories/auth_repository.dart';
import '../../../../core/di/injection.dart';
import '../../../home/presentation/cubit/home_cubit.dart';
import '../../../home/presentation/pages/tv_home_page.dart';
import 'login_page.dart';

/// Decides whether to show [TvHomePage] (ads) or [LoginPage] based on stored session.
/// Only registered buses can reach the home screen and show ads.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  VehicleSession? _session;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final VehicleSession? session =
          await getIt<AuthRepository>().getStoredSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onLoginSuccess() {
    setState(() {
      _loading = true;
      _error = null;
    });
    getIt<AuthRepository>().getStoredSession().then((VehicleSession? session) {
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: RepaintBoundary(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => _checkSession(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_session != null) {
      return BlocProvider<HomeCubit>(
        create: (_) {
          final HomeCubit cubit = getIt<HomeCubit>();
          cubit.loadAds();
          return cubit;
        },
        child: const TvHomePage(),
      );
    }
    return LoginPage(onLoginSuccess: _onLoginSuccess);
  }
}
