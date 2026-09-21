import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/runtime/app_bootstrap_state.dart';
import 'package:plandone/src/core/runtime/runtime_flags.dart';
import 'package:plandone/src/features/auth/domain/models/auth_failure.dart';
import 'package:plandone/src/features/auth/domain/models/auth_user.dart';
import 'package:plandone/src/features/auth/domain/repositories/auth_repository.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/auth/presentation/auth_page.dart';

void main() {
  testWidgets(
    'password reset validates and normalizes the email before showing success',
    (tester) async {
      final resetCompleter = Completer<void>();
      final repository = _RecordingAuthRepository(
        resetCompleter: resetCompleter,
      );
      await tester.pumpWidget(_buildResetTestApp(repository));

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      final resetEmailField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(resetEmailField, 'not-an-email');
      await tester.tap(find.text('Send reset email'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(repository.lastResetEmail, isNull);

      await tester.enterText(resetEmailField, '  OWNER@EXAMPLE.COM  ');
      await tester.tap(find.text('Send reset email'));
      await tester.pump();

      expect(find.text('Sending...'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );

      resetCompleter.complete();
      await tester.pumpAndSettle();

      expect(repository.lastResetEmail, 'owner@example.com');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Password reset email sent. Check your inbox.'),
        findsOneWidget,
      );
    },
    skip: !useFirebaseAuth,
  );

  testWidgets(
    'password reset keeps the dialog open and displays Firebase failures',
    (tester) async {
      final repository = _RecordingAuthRepository(
        resetFailure: const AuthFailure(
          code: AuthFailureCode.network,
          message: 'Network error. Check your connection and try again.',
        ),
      );
      await tester.pumpWidget(_buildResetTestApp(repository));

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      final resetEmailField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(resetEmailField, 'owner@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Network error. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.text('Send reset email'), findsOneWidget);
    },
    skip: !useFirebaseAuth,
  );
}

Widget _buildResetTestApp(AuthRepository repository) {
  return ProviderScope(
    overrides: [
      appBootstrapStateProvider.overrideWithValue(
        const AppBootstrapState.ready(),
      ),
      authRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: AuthPage()),
  );
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({this.resetFailure, this.resetCompleter});

  final AuthFailure? resetFailure;
  final Completer<void>? resetCompleter;
  String? lastResetEmail;

  @override
  Stream<AuthSession?> authStateChanges() => Stream.value(null);

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    lastResetEmail = email;
    if (resetFailure != null) {
      throw resetFailure!;
    }
    await resetCompleter?.future;
  }

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}
}
