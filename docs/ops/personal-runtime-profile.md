# Personal Runtime Profile

## Purpose

This is the recommended runtime profile for **daily personal use** of PlanDone as of March 18, 2026.

## Recommended flags

Use persistent local storage plus Firebase auth and sync:

```bash
flutter run \
  --dart-define=USE_IN_MEMORY_LOCAL_STORE=false \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=USE_FIREBASE_SYNC=true
```

## What this profile gives you

- Drift-backed local persistence
- Firebase-backed sign-in
- Firestore sync + hydration
- local Android due/start reminders derived from canonical local metadata
- offline-first behavior with local DB still driving the UI

## Optional extension flag

If you also want FCM device-token registration for manual push testing:

```bash
flutter run \
  --dart-define=USE_IN_MEMORY_LOCAL_STORE=false \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=USE_FIREBASE_SYNC=true \
  --dart-define=USE_FIREBASE_PUSH=true
```

Use this only for the optional push extension path. The baseline MVP reminder flow does not require it.

## Device checklist

1. Install the latest build on a physical Android device.
2. Sign in with Firebase auth enabled.
3. Grant Android notification permission when prompted.
4. Keep the app in the system's allowed-notification list.
5. If your phone has aggressive battery optimization, exempt PlanDone if reminders appear delayed.
6. Complete the Android auth setup in [android-auth-setup.md](/home/messay/coding/own/PlanDone/docs/ops/android-auth-setup.md) before expecting real Firebase sign-in or Google auth.

## Recommended validation sequence

1. Run `npm run test:rules`.
2. Run `flutter test`.
3. Deploy latest Android build.
4. Run the manual checklist in [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md).

## Non-goals for this profile

- shared-team production rollout process
- automated server-side push scheduling
- iOS/web/desktop notification parity
