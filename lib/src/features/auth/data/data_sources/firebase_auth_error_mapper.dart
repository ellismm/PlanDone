import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/auth_failure.dart';

AuthFailure mapFirebaseAuthException(
  FirebaseAuthException exception, {
  String? normalizedEmail,
  List<String> signInMethods = const <String>[],
}) {
  switch (exception.code) {
    case 'invalid-email':
      return const AuthFailure(
        code: AuthFailureCode.invalidEmail,
        message: 'Enter a valid email address.',
      );
    case 'weak-password':
      return const AuthFailure(
        code: AuthFailureCode.weakPassword,
        message:
            'Password must be at least 8 characters and include upper, lower, and numeric characters.',
      );
    case 'email-already-in-use':
      return AuthFailure(
        code: AuthFailureCode.duplicateEmail,
        email: normalizedEmail,
        message: 'An account already exists for that email.',
      );
    case 'wrong-password':
    case 'invalid-credential':
    case 'invalid-login-credentials':
      if (signInMethods.contains('google.com') &&
          !signInMethods.contains('password')) {
        return AuthFailure(
          code: AuthFailureCode.providerConflict,
          email: normalizedEmail,
          signInMethods: signInMethods,
          message: 'This account uses Google sign-in. Continue with Google.',
        );
      }
      return const AuthFailure(
        code: AuthFailureCode.wrongPassword,
        message: 'Incorrect email or password.',
      );
    case 'user-not-found':
      return const AuthFailure(
        code: AuthFailureCode.userNotFound,
        message: 'No account was found for that email.',
      );
    case 'account-exists-with-different-credential':
      return AuthFailure(
        code: AuthFailureCode.providerConflict,
        email: exception.email ?? normalizedEmail,
        signInMethods: signInMethods,
        message: signInMethods.contains('password')
            ? 'This email already exists. Sign in with your password first to link Google.'
            : 'This email already exists with a different sign-in method.',
      );
    case 'operation-not-allowed':
      return const AuthFailure(
        code: AuthFailureCode.unavailable,
        message: 'This sign-in method is not enabled in Firebase Auth yet.',
      );
    case 'network-request-failed':
      return const AuthFailure(
        code: AuthFailureCode.network,
        message: 'Network error. Check your connection and try again.',
      );
    case 'requires-recent-login':
      return const AuthFailure(
        code: AuthFailureCode.requiresRecentLogin,
        message: 'For security, sign in again before deleting your account.',
      );
    case 'too-many-requests':
      return const AuthFailure(
        code: AuthFailureCode.unavailable,
        message: 'Too many attempts. Please wait and try again.',
      );
    default:
      return AuthFailure(
        code: AuthFailureCode.unknown,
        email: normalizedEmail,
        signInMethods: signInMethods,
        message:
            exception.message ?? 'Authentication failed. Please try again.',
      );
  }
}
