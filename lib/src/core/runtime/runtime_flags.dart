const _legacyUseDriftLocalStore = bool.fromEnvironment(
  'USE_DRIFT_LOCAL_STORE',
  defaultValue: true,
);

const _isFlutterTest =
    bool.fromEnvironment('FLUTTER_TEST', defaultValue: false);

const isFlutterTestRuntime = _isFlutterTest;

const localRuntimeProfile = 'local';
const firebaseRuntimeProfile = 'firebase';

/// Named runtime contract selected through a checked-in dart-define file.
const runtimeProfile = String.fromEnvironment(
  'PLANDONE_RUNTIME_PROFILE',
  defaultValue: localRuntimeProfile,
);

const isFirebaseRuntimeProfile = runtimeProfile == firebaseRuntimeProfile;

/// Drift is the default runtime path.
///
/// Set `--dart-define=USE_IN_MEMORY_LOCAL_STORE=true` for tests/dev toggles.
const useInMemoryLocalStore = bool.fromEnvironment(
  'USE_IN_MEMORY_LOCAL_STORE',
  defaultValue: _isFlutterTest ? true : !_legacyUseDriftLocalStore,
);

/// Firebase auth is optional at runtime until Firebase is configured.
///
/// Enable with `--dart-define=USE_FIREBASE_AUTH=true`.
const useFirebaseAuth = bool.fromEnvironment(
  'USE_FIREBASE_AUTH',
  defaultValue: isFirebaseRuntimeProfile,
);

/// Firestore sync/listener runtime path for Phase 2.
///
/// Enable with `--dart-define=USE_FIREBASE_SYNC=true`.
const useFirebaseSync = bool.fromEnvironment(
  'USE_FIREBASE_SYNC',
  defaultValue: isFirebaseRuntimeProfile,
);

/// Firebase Cloud Messaging runtime path for mobile push notifications.
///
/// Enable with `--dart-define=USE_FIREBASE_PUSH=true`.
const useFirebasePush = bool.fromEnvironment(
  'USE_FIREBASE_PUSH',
  defaultValue: false,
);

/// Firebase AI Logic planning assistant runtime path.
///
/// The client never contains a private model-provider key. Firebase App Check
/// protects model requests when this feature is enabled.
const useFirebaseAi = bool.fromEnvironment(
  'USE_FIREBASE_AI',
  defaultValue: false,
);

const firebaseAiModel = String.fromEnvironment(
  'PLANDONE_FIREBASE_AI_MODEL',
  defaultValue: 'gemini-3.5-flash',
);

const firebaseAiFallbackModel = String.fromEnvironment(
  'PLANDONE_FIREBASE_AI_FALLBACK_MODEL',
  defaultValue: 'gemini-3.5-flash-lite',
);

String? validateRuntimeConfiguration({
  String profile = runtimeProfile,
  bool inMemoryLocalStore = useInMemoryLocalStore,
  bool firebaseAuth = useFirebaseAuth,
  bool firebaseSync = useFirebaseSync,
  bool firebasePush = useFirebasePush,
  bool firebaseAi = useFirebaseAi,
}) {
  if (profile != localRuntimeProfile && profile != firebaseRuntimeProfile) {
    return 'Unknown PLANDONE_RUNTIME_PROFILE "$profile". Use "local" or "firebase".';
  }
  if (firebaseSync && !firebaseAuth) {
    return 'USE_FIREBASE_SYNC requires USE_FIREBASE_AUTH.';
  }
  if (firebasePush && !firebaseAuth) {
    return 'USE_FIREBASE_PUSH requires USE_FIREBASE_AUTH.';
  }
  if (firebaseAi && !firebaseAuth) {
    return 'USE_FIREBASE_AI requires USE_FIREBASE_AUTH.';
  }
  if (firebaseSync && inMemoryLocalStore) {
    return 'Firebase sync requires persistent local storage.';
  }
  if (profile == localRuntimeProfile &&
      (firebaseAuth || firebaseSync || firebasePush || firebaseAi)) {
    return 'The local profile cannot enable Firebase services. Use the firebase profile.';
  }
  if (profile == firebaseRuntimeProfile &&
      (!firebaseAuth || !firebaseSync || inMemoryLocalStore)) {
    return 'The firebase profile requires Firebase auth, Firestore sync, and persistent local storage.';
  }
  return null;
}
