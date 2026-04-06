import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

/// Bus pairing / login screen. Device MAC or unique id is read-only; user enters pairing code.
/// TV-friendly: all interactive elements are focusable for D-pad.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoginSuccess});

  final VoidCallback onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _pairingCodeController = TextEditingController();
  final FocusNode _pairingCodeFocus = FocusNode();
  final FocusNode _registerButtonFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    context.read<AuthCubit>().loadMacAddress();
  }

  @override
  void dispose() {
    _pairingCodeController.dispose();
    _pairingCodeFocus.dispose();
    _registerButtonFocus.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthCubit>().register(_pairingCodeController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return RepaintBoundary(
              child: BlocListener<AuthCubit, AuthState>(
                listener: (BuildContext context, AuthState state) {
                  if (state is AuthAuthenticated) {
                    widget.onLoginSuccess();
                  }
                },
                child: BlocBuilder<AuthCubit, AuthState>(
                  builder: (BuildContext context, AuthState state) {
                    final String? deviceIdentifier = state is AuthMacLoaded
                        ? state.deviceIdentifier
                        : null;
                    final bool loading = state is AuthLoading;
                    final String? error =
                        state is AuthError ? state.message : null;
                    final Size screenSize = MediaQuery.sizeOf(context);
                    final double logoWidth = screenSize.width * 0.22;
                    final double logoHeight = screenSize.height * 0.28;

                    final Widget formColumn = Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'Pair this device using the identifier below and your pairing code',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Device MAC or unique ID',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          deviceIdentifier ?? 'Loading...',
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (screenSize.shortestSide * 0.055)
                                .clamp(22.0, 40.0),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Pairing code',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          focusNode: _pairingCodeFocus,
                          autofocus: true,
                          controller: _pairingCodeController,
                          enabled: !loading,
                          keyboardType: TextInputType.none,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter pairing code',
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
                            textAlign: TextAlign.start,
                          ),
                        ],
                        const SizedBox(height: 32),
                        Focus(
                          focusNode: _registerButtonFocus,
                          child: FocusableActionDetector(
                            actions: <Type, Action<Intent>>{
                              ActivateIntent:
                                  CallbackAction<ActivateIntent>(
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
                                                'Pair & show ads',
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
                    );

                    final Widget logoColumn = Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
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
                      ],
                    );

                    if (constraints.maxWidth < 720) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Center(child: logoColumn),
                            const SizedBox(height: 40),
                            formColumn,
                          ],
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 24,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: 5,
                            child: Center(child: logoColumn),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            flex: 6,
                            child: Center(
                              child: SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight - 48,
                                  ),
                                  child: formColumn,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
