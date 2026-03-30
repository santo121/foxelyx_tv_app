import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

/// Bus registration / login screen. Device ID is read-only; user enters registration number.
/// TV-friendly: all interactive elements are focusable for D-pad.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});

  final VoidCallback onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _regNoController = TextEditingController();
  final FocusNode _regNoFocus = FocusNode();
  final FocusNode _registerButtonFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    context.read<AuthCubit>().loadDeviceId();
  }

  @override
  void dispose() {
    _regNoController.dispose();
    _regNoFocus.dispose();
    _registerButtonFocus.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthCubit>().register(_regNoController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: RepaintBoundary(
          child: BlocListener<AuthCubit, AuthState>(
            listener: (BuildContext context, AuthState state) {
              if (state is AuthAuthenticated) {
                widget.onLoginSuccess();
              }
            },
            child: BlocBuilder<AuthCubit, AuthState>(
              builder: (BuildContext context, AuthState state) {
                final String? deviceId = state is AuthDeviceIdLoaded
                    ? state.deviceId
                    : state is AuthLoading
                    ? null
                    : null;
                final bool loading = state is AuthLoading;
                final String? error = state is AuthError ? state.message : null;
                final Size screenSize = MediaQuery.sizeOf(context);
                final double logoWidth = screenSize.width * 0.5;
                final double logoHeight = screenSize.height * 0.5;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Static ad banner
                          Center(
                            child: SizedBox(
                              width: logoWidth,
                              height: logoHeight,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  'assets/logo/foxelyx_logo.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.low,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'foxelyx',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Register this device with the vehicle registration number',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          // Device ID (read-only)
                          const Text(
                            'Device ID',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Focus(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                deviceId ?? 'Loading...',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Registration number
                          const Text(
                            'Vehicle registration number',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            focusNode: _regNoFocus,
                            autofocus: true,
                            controller: _regNoController,
                            enabled: !loading,
                            keyboardType: TextInputType.none,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. KL-01-AB-1234',
                              hintStyle: TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white12,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _submit(),
                          ),
                          if (error != null) ...<Widget>[
                            const SizedBox(height: 16),
                            Text(
                              error,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 32),
                          Focus(
                            focusNode: _registerButtonFocus,
                            child: FocusableActionDetector(
                              actions: <Type, Action<Intent>>{
                                ActivateIntent: CallbackAction<ActivateIntent>(
                                  onInvoke: (ActivateIntent intent) {
                                    if (!loading) _submit();
                                    return null;
                                  },
                                ),
                              },
                              child: Builder(
                                builder: (BuildContext ctx) {
                                  final bool hasFocus = Focus.of(ctx).hasFocus;
                                  return Material(
                                    color: hasFocus
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white24,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      onTap: loading ? null : _submit,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 24,
                                        ),
                                        child: Center(
                                          child: loading
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Text(
                                                  'Register & show ads',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
