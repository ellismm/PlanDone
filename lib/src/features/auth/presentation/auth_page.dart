import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/plan_done_branding.dart';
import '../../../core/runtime/app_bootstrap_state.dart';
import '../../../core/runtime/runtime_flags.dart';
import '../domain/models/auth_failure.dart';
import '../domain/models/auth_user.dart';
import '../domain/policies/auth_input_policy.dart';
import 'auth_controller.dart';

enum _AuthMode { signIn, signUp }

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _isBusy = false;
  String? _error;
  String? _statusMessage;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text;
    final password = _passwordController.text;
    final displayName = _displayNameController.text;
    final confirmPassword = _confirmPasswordController.text;

    final error = _validateInputs(
      email: email,
      password: password,
      displayName: displayName,
      confirmPassword: confirmPassword,
    );
    if (error != null) {
      setState(() {
        _error = error;
        _statusMessage = null;
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final controller = ref.read(authControllerProvider);
      final normalizedEmail = AuthInputPolicy.normalizeEmail(email);
      final AuthSession session;
      if (_mode == _AuthMode.signIn) {
        session = await controller.signInWithEmailPassword(
          email: normalizedEmail,
          password: password,
        );
      } else {
        session = await controller.signUpWithEmailPassword(
          email: normalizedEmail,
          password: password,
          displayName: displayName.trim(),
        );
      }
      await _maybeOfferBiometricQuickUnlock(session);
    } catch (error) {
      setState(() {
        _error = _messageFor(error);
        _statusMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final session = await ref.read(authControllerProvider).signInWithGoogle();
      await _maybeOfferBiometricQuickUnlock(session);
    } catch (error) {
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final bootstrapState = ref.read(appBootstrapStateProvider);
    if (useFirebaseAuth && !bootstrapState.firebaseReady) {
      setState(() {
        _error = bootstrapState.firebaseErrorMessage;
        _statusMessage = null;
      });
      return;
    }
    final resetEmailController = TextEditingController(
      text: AuthInputPolicy.normalizeEmail(_emailController.text),
    );
    String? dialogError;
    bool isSending = false;

    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset your password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final emailError = AuthInputPolicy.validateEmail(
                            resetEmailController.text,
                          );
                          if (emailError != null) {
                            setDialogState(() => dialogError = emailError);
                            return;
                          }
                          setDialogState(() {
                            isSending = true;
                            dialogError = null;
                          });
                          try {
                            await ref
                                .read(authControllerProvider)
                                .sendPasswordResetEmail(
                                  email: AuthInputPolicy.normalizeEmail(
                                    resetEmailController.text,
                                  ),
                                );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() {
                              isSending = false;
                              dialogError = _messageFor(error);
                            });
                          }
                        },
                  child: Text(isSending ? 'Sending...' : 'Send reset email'),
                ),
              ],
            );
          },
        );
      },
    );

    resetEmailController.dispose();
    if (sent == true && mounted) {
      setState(() {
        _error = null;
        _statusMessage = 'Password reset email sent. Check your inbox.';
      });
    }
  }

  Future<void> _maybeOfferBiometricQuickUnlock(AuthSession session) async {
    final controller = ref.read(authControllerProvider);
    final shouldOffer = await controller.canOfferBiometricQuickUnlock(session);
    if (!shouldOffer || !mounted) {
      return;
    }
    final enableBiometrics = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable fingerprint unlock?'),
          content: const Text(
            'Use your fingerprint to quickly unlock PlanDone on this Android device after you sign in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );
    if (enableBiometrics == true) {
      await controller.enableBiometricQuickUnlock(session);
      if (mounted) {
        setState(() {
          _error = null;
          _statusMessage = 'Fingerprint quick unlock enabled for this device.';
        });
      }
    }
  }

  String? _validateInputs({
    required String email,
    required String password,
    required String displayName,
    required String confirmPassword,
  }) {
    final emailError = AuthInputPolicy.validateEmail(email);
    if (emailError != null) return emailError;
    final passwordError = _mode == _AuthMode.signUp
        ? AuthInputPolicy.validatePassword(password)
        : AuthInputPolicy.validateSignInPassword(password);
    if (passwordError != null) return passwordError;
    if (_mode == _AuthMode.signUp) {
      final displayNameError = AuthInputPolicy.validateDisplayName(displayName);
      if (displayNameError != null) return displayNameError;
      final confirmPasswordError = AuthInputPolicy.validatePasswordConfirmation(
        password: password,
        confirmPassword: confirmPassword,
      );
      if (confirmPasswordError != null) return confirmPasswordError;
    }
    return null;
  }

  String _messageFor(Object error) {
    if (error is AuthFailure) {
      return error.message;
    }
    final raw = error.toString();
    if (raw.startsWith('StateError: ')) {
      return raw.substring('StateError: '.length);
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapState = ref.watch(appBootstrapStateProvider);
    final title = _mode == _AuthMode.signIn
        ? 'Sign in to PlanDone'
        : 'Create your PlanDone account';
    final subtitle = _mode == _AuthMode.signIn
        ? 'Use your email, password, or Google account to get back to work.'
        : 'Create a real account with a display name, secure password, and optional Google sign-in.';

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: const Padding(
          padding: EdgeInsetsDirectional.only(start: 16),
          child: Center(child: PlanDoneBrandMark(size: 28)),
        ),
        title: const Text('PlanDone'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewInsets = MediaQuery.viewInsetsOf(context);
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(child: PlanDoneLogo(height: 72)),
                            const SizedBox(height: 16),
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (useFirebaseAuth &&
                                !bootstrapState.firebaseReady) ...[
                              const SizedBox(height: 16),
                              Card(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    bootstrapState.firebaseErrorMessage ??
                                        'Firebase Auth is not configured for this Android build yet.',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SegmentedButton<_AuthMode>(
                              segments: const [
                                ButtonSegment(
                                  value: _AuthMode.signIn,
                                  label: Text('Sign in'),
                                ),
                                ButtonSegment(
                                  value: _AuthMode.signUp,
                                  label: Text('Sign up'),
                                ),
                              ],
                              selected: {_mode},
                              onSelectionChanged: _isBusy
                                  ? null
                                  : (selection) {
                                      setState(() {
                                        _mode = selection.first;
                                        _error = null;
                                        _statusMessage = null;
                                      });
                                    },
                            ),
                            const SizedBox(height: 16),
                            if (_mode == _AuthMode.signUp) ...[
                              TextField(
                                controller: _displayNameController,
                                enabled: !_isBusy,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Display name',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _emailController,
                              enabled: !_isBusy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              enabled: !_isBusy,
                              obscureText: true,
                              textInputAction: _mode == _AuthMode.signIn
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                helperText: null,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) =>
                                  _mode == _AuthMode.signIn ? _submit() : null,
                            ),
                            if (_mode == _AuthMode.signIn) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _isBusy ? null : _showResetPasswordDialog,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ],
                            if (_mode == _AuthMode.signUp) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPasswordController,
                                enabled: !_isBusy,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Use 8+ characters with upper, lower, and a number.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _isBusy ? null : _submit,
                              child: Text(
                                _mode == _AuthMode.signIn
                                    ? 'Sign in'
                                    : 'Create account',
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _isBusy ? null : _signInWithGoogle,
                              icon: const Icon(Icons.login),
                              label: const Text('Continue with Google'),
                            ),
                            if (_statusMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _statusMessage!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            if (_isBusy) ...[
                              const SizedBox(height: 16),
                              const Center(child: CircularProgressIndicator()),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
