# Optional Push Notifications to Phones (FCM Extension Path)

This document is for the **optional FCM extension path**.

If your goal is simple due/start reminders on your own Android phone, the baseline MVP already uses **local scheduled notifications** and you do not need this setup.

## What this optional path adds

- Android app requests notification permission and fetches FCM token.
- Token is stored at:
  - `users/{uid}/devices/{deviceId}`
- Token updates are handled on refresh.
- Background message handler is wired for FCM runtime.

## Runtime flag

Enable the push path when running/building:

```bash
flutter run \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=USE_FIREBASE_SYNC=true \
  --dart-define=USE_FIREBASE_PUSH=true
```

Use `USE_FIREBASE_PUSH=true` only when you want device-token registration/manual push testing.

## Firebase Console steps

1. Open Firebase Console for your project.
2. Go to `Project settings -> Cloud Messaging`.
3. Ensure the Android app is registered in the Firebase project.
4. Download/update `google-services.json` in:
   - `android/app/google-services.json`
5. Verify the package name matches your app id.
6. Build and install the app on a physical phone.
7. Sign in with Firebase auth enabled.
8. Confirm a token document exists in Firestore:
   - `users/{yourUid}/devices/{deviceId}`

## Sending a test push

1. Firebase Console -> `Cloud Messaging` -> create a test message.
2. Use a test title/body.
3. Target the device token from the Firestore device doc.
4. Send and verify the phone receives it.

## Firestore rules

Rules allow users to read/write only their own device docs under:

- `users/{uid}/devices/{deviceId}`

## Important limitation

This path does **not** yet implement automated server-triggered reminder delivery. It is an optional extension path for device registration and manual push testing.
