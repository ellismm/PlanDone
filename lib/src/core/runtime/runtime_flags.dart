const _legacyUseDriftLocalStore = bool.fromEnvironment(
  'USE_DRIFT_LOCAL_STORE',
  defaultValue: true,
);

const _isFlutterTest =
    bool.fromEnvironment('FLUTTER_TEST', defaultValue: false);

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
  defaultValue: false,
);

/// Firestore sync/listener runtime path for Phase 2.
///
/// Enable with `--dart-define=USE_FIREBASE_SYNC=true`.
const useFirebaseSync = bool.fromEnvironment(
  'USE_FIREBASE_SYNC',
  defaultValue: false,
);

/// Firebase Cloud Messaging runtime path for mobile push notifications.
///
/// Enable with `--dart-define=USE_FIREBASE_PUSH=true`.
const useFirebasePush = bool.fromEnvironment(
  'USE_FIREBASE_PUSH',
  defaultValue: false,
);
