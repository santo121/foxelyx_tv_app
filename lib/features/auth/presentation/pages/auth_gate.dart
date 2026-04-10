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
      final VehicleSession? session = await getIt<AuthRepository>()
          .getStoredSession();
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
        body: FocusScope(
          child: Center(
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
                  _GateRetryButton(autofocus: true, onPressed: _checkSession),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_session != null &&
        (_session!.accessToken?.isNotEmpty ?? false) &&
        (_session!.secret?.isNotEmpty ?? false)) {
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

class _GateRetryButton extends StatelessWidget {
  const _GateRetryButton({required this.onPressed, this.autofocus = false});

  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: autofocus,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onPressed();
            return null;
          },
        ),
      },
      child: Builder(
        builder: (BuildContext context) {
          final bool isFocused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: isFocused ? Colors.white24 : Colors.white12,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isFocused ? Colors.white : Colors.white30,
                width: isFocused ? 2 : 1,
              ),
            ),
            child: TextButton(onPressed: onPressed, child: const Text('Retry')),
          );
        },
      ),
    );
  }
}
