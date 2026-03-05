# Push Notifications to Phones (FCM)

This repository now includes Firebase Cloud Messaging (FCM) device token registration.

## What is implemented

- Android app requests notification permission and fetches FCM token.
- Token is stored at:
  - `users/{uid}/devices/{deviceId}`
- Token updates are handled on refresh.
- Background message handler is wired for FCM runtime.

## Runtime flag

Enable push path when running/building:

```bash
flutter run --dart-define=USE_FIREBASE_AUTH=true --dart-define=USE_FIREBASE_SYNC=true --dart-define=USE_FIREBASE_PUSH=true
```

Use `USE_FIREBASE_PUSH=true` for push registration.

## Firebase Console steps (required)

1. Open Firebase Console for your project.
2. Go to `Project settings -> Cloud Messaging`.
3. Ensure Android app is registered in Firebase project.
4. Download/update `google-services.json` in:
   - `android/app/google-services.json`
5. Verify package name matches app id (current: `com.example.plandone` unless changed).
6. Build and install app on physical phone.
7. Sign in to app with Firebase auth.
8. Confirm token document exists in Firestore:
   - `users/{yourUid}/devices/{deviceId}`

## Sending a test push

1. Firebase Console -> `Cloud Messaging` -> `Send your first message`.
2. Use test title/body.
3. Target by token from the Firestore device doc.
4. Send and verify phone receives it.

## Firestore rules

Rules now allow users to read/write only their own device docs under:

- `users/{uid}/devices/{deviceId}`

