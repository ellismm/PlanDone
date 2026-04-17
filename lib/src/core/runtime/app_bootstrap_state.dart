import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.firebaseReady,
    this.firebaseErrorMessage,
  });

  const AppBootstrapState.ready()
      : firebaseReady = true,
        firebaseErrorMessage = null;

  const AppBootstrapState.firebaseUnavailable(String message)
      : firebaseReady = false,
        firebaseErrorMessage = message;

  final bool firebaseReady;
  final String? firebaseErrorMessage;
}

final appBootstrapStateProvider = Provider<AppBootstrapState>(
  (ref) => const AppBootstrapState.ready(),
);
