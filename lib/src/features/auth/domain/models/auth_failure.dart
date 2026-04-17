enum AuthFailureCode {
  invalidEmail,
  weakPassword,
  duplicateEmail,
  wrongPassword,
  userNotFound,
  missingFields,
  providerConflict,
  googleCanceled,
  firebaseNotConfigured,
  requiresRecentLogin,
  network,
  unavailable,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure({
    required this.code,
    required this.message,
    this.email,
    this.signInMethods = const <String>[],
  });

  final AuthFailureCode code;
  final String message;
  final String? email;
  final List<String> signInMethods;

  @override
  String toString() => message;
}
