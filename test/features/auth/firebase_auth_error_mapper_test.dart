import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/auth/data/data_sources/firebase_auth_error_mapper.dart';
import 'package:plandone/src/features/auth/domain/models/auth_failure.dart';

void main() {
  test('maps duplicate email to a friendly duplicate account error', () {
    final failure = mapFirebaseAuthException(
      FirebaseAuthException(code: 'email-already-in-use'),
      normalizedEmail: 'user@plandone.dev',
    );

    expect(failure.code, AuthFailureCode.duplicateEmail);
    expect(failure.message, 'An account already exists for that email.');
  });

  test('maps google provider conflict with password guidance', () {
    final failure = mapFirebaseAuthException(
      FirebaseAuthException(
        code: 'account-exists-with-different-credential',
        email: 'user@plandone.dev',
      ),
      normalizedEmail: 'user@plandone.dev',
      signInMethods: const ['password'],
    );

    expect(failure.code, AuthFailureCode.providerConflict);
    expect(
      failure.message,
      'This email already exists. Sign in with your password first to link Google.',
    );
  });
}
