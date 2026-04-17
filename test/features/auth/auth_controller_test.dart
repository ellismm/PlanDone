import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/auth/data/data_sources/in_memory_auth_data_source.dart';
import 'package:plandone/src/features/auth/data/repositories/auth_repository_impl.dart';

void main() {
  test('in-memory auth supports email sign-up/sign-in and sign-out', () async {
    final dataSource = InMemoryAuthDataSource();
    final repository = AuthRepositoryImpl(dataSource);

    final signUpSession = await repository.signUpWithEmailPassword(
      email: 'tester@plandone.dev',
      password: 'password-123',
      displayName: 'Tester',
    );
    expect(signUpSession.user.email, 'tester@plandone.dev');
    expect(signUpSession.user.displayName, 'Tester');

    final signInSession = await repository.signInWithEmailPassword(
      email: 'tester@plandone.dev',
      password: 'password-123',
    );
    expect(signInSession.user.uid, isNotEmpty);

    await repository.signOut();

    final latest = await repository.authStateChanges().first;
    expect(latest, isNull);
  });

  test('in-memory auth supports Google sign-in', () async {
    final dataSource = InMemoryAuthDataSource();
    final repository = AuthRepositoryImpl(dataSource);

    final session = await repository.signInWithGoogle();

    expect(session.user.uid, 'google-user');
    expect(session.user.email, 'google-user@plandone.local');
  });

  test('in-memory auth accepts password reset requests', () async {
    final dataSource = InMemoryAuthDataSource();
    final repository = AuthRepositoryImpl(dataSource);

    await repository.sendPasswordResetEmail(
      email: 'tester@plandone.dev',
    );
  });
}
