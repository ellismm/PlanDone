import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/runtime/runtime_flags.dart';

void main() {
  test('active runtime profile is internally consistent', () {
    expect(validateRuntimeConfiguration(), isNull);
  });

  test('firebase profile requires auth, sync, and persistent storage', () {
    expect(
      validateRuntimeConfiguration(
        profile: firebaseRuntimeProfile,
        inMemoryLocalStore: false,
        firebaseAuth: true,
        firebaseSync: true,
        firebasePush: false,
        firebaseAi: false,
      ),
      isNull,
    );
    expect(
      validateRuntimeConfiguration(
        profile: firebaseRuntimeProfile,
        inMemoryLocalStore: false,
        firebaseAuth: true,
        firebaseSync: false,
        firebasePush: false,
        firebaseAi: false,
      ),
      contains('firebase profile requires'),
    );
  });

  test('rejects unsafe or ambiguous flag combinations', () {
    expect(
      validateRuntimeConfiguration(
        profile: localRuntimeProfile,
        inMemoryLocalStore: false,
        firebaseAuth: false,
        firebaseSync: true,
        firebasePush: false,
        firebaseAi: false,
      ),
      contains('requires USE_FIREBASE_AUTH'),
    );
    expect(
      validateRuntimeConfiguration(
        profile: localRuntimeProfile,
        inMemoryLocalStore: false,
        firebaseAuth: true,
        firebaseSync: false,
        firebasePush: false,
        firebaseAi: false,
      ),
      contains('local profile cannot enable Firebase'),
    );
    expect(
      validateRuntimeConfiguration(
        profile: 'staging-ish',
        inMemoryLocalStore: false,
        firebaseAuth: false,
        firebaseSync: false,
        firebasePush: false,
        firebaseAi: false,
      ),
      contains('Unknown PLANDONE_RUNTIME_PROFILE'),
    );
    expect(
      validateRuntimeConfiguration(
        profile: firebaseRuntimeProfile,
        inMemoryLocalStore: false,
        firebaseAuth: false,
        firebaseSync: false,
        firebasePush: false,
        firebaseAi: true,
      ),
      contains('USE_FIREBASE_AI requires USE_FIREBASE_AUTH'),
    );
  });
}
