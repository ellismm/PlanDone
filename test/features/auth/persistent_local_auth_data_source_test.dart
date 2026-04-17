import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/auth/data/data_sources/persistent_local_auth_data_source.dart';
import 'package:plandone/src/features/auth/domain/models/auth_failure.dart';

void main() {
  test('local auth persists users and session across data source instances',
      () async {
    final store = _FakeLocalAuthKeyValueStore();
    final first = PersistentLocalAuthDataSource(store: store);

    final signUpSession = await first.signUpWithEmailPassword(
      email: 'tester@plandone.dev',
      password: 'PlanDone123',
      displayName: 'Tester',
    );

    final second = PersistentLocalAuthDataSource(store: store);
    final restoredSession = await second.authStateChanges().first;
    expect(restoredSession?.user.uid, signUpSession.user.uid);

    await second.signOut();

    final third = PersistentLocalAuthDataSource(store: store);
    final signInSession = await third.signInWithEmailPassword(
      email: 'tester@plandone.dev',
      password: 'PlanDone123',
    );
    expect(signInSession.user.email, 'tester@plandone.dev');
    expect(signInSession.user.displayName, 'Tester');
  });

  test('missing local account surfaces the reconnect guidance', () async {
    final dataSource = PersistentLocalAuthDataSource(
      store: _FakeLocalAuthKeyValueStore(),
    );

    expect(
      () => dataSource.signInWithEmailPassword(
        email: 'missing@plandone.dev',
        password: 'PlanDone123',
      ),
      throwsA(
        isA<AuthFailure>()
            .having((error) => error.code, 'code', AuthFailureCode.userNotFound)
            .having(
              (error) => error.message,
              'message',
              contains('use Sign up with the same email'),
            ),
      ),
    );
  });

  test('delete account removes the local user and clears the session',
      () async {
    final store = _FakeLocalAuthKeyValueStore();
    final dataSource = PersistentLocalAuthDataSource(store: store);

    await dataSource.signUpWithEmailPassword(
      email: 'tester@plandone.dev',
      password: 'PlanDone123',
      displayName: 'Tester',
    );

    await dataSource.deleteAccount();

    expect(await dataSource.authStateChanges().first, isNull);
    expect(
      () => dataSource.signInWithEmailPassword(
        email: 'tester@plandone.dev',
        password: 'PlanDone123',
      ),
      throwsA(
        isA<AuthFailure>().having(
            (error) => error.code, 'code', AuthFailureCode.userNotFound),
      ),
    );
  });
}

class _FakeLocalAuthKeyValueStore implements LocalAuthKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
