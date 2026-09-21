# Android Auth Setup

## Goal

Enable the real Android authentication flow in PlanDone:

- email/password sign-up and sign-in
- Google sign-in
- password reset
- fingerprint quick unlock after a prior successful sign-in

## Runtime profile

Use the Android auth path with Firebase enabled:

```bash
flutter run \
  --dart-define-from-file=config/runtime/firebase.json
```

This named profile always enables Firebase Auth and Firestore sync together with
persistent local storage. Inconsistent manual flag combinations are rejected.

## Firebase project setup

1. Create or open your Firebase project.
2. Add the Android app that matches your local `applicationId`:
   - current value: `com.example.plandone`
3. Download `google-services.json`.
4. Place it at:
   - `android/app/google-services.json`

If this file is missing, the profile-aware Android build/deploy scripts stop
with an actionable error. A direct Flutter run still shows a setup message
instead of silently falling back to local authentication.

## Firebase Auth providers

Enable these providers in Firebase Console:

1. `Authentication -> Sign-in method`
2. Enable `Email/Password`
3. Enable `Google`

Without those providers enabled, the app will show a friendly runtime error instead of a raw Firebase exception.

## Google sign-in Android setup

For Google sign-in to work on Android:

1. Register the Android app in Firebase with the correct package name.
2. Add the app signing SHA certificate fingerprints in Firebase project settings.
3. Re-download `google-services.json` after adding fingerprints if Firebase prompts for it.

Typical fingerprints to register during development:

- debug SHA-1
- debug SHA-256

You can get them from your local keystore with:

```bash
keytool -list -v \
  -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android \
  -keypass android
```

If Google sign-in fails because the email already exists under password sign-in, PlanDone now guides the user to sign in with password first and then links the Google credential.

## Email/password behavior

Client-side sign-up validation enforces:

- at least 8 characters
- at least one uppercase letter
- at least one lowercase letter
- at least one number

Firebase remains the source of truth for:

- duplicate email detection
- credential validation
- weak-password rejection
- password reset delivery

## Fingerprint quick unlock

Biometric quick unlock is Android-only in this pass.

Behavior:

- it is only offered after a successful sign-in
- it does not store the raw password
- it only unlocks an already-authenticated Firebase session on that device
- signing out clears the quick-unlock shortcut

Device prerequisites:

- biometric hardware enrolled on the phone
- lock screen configured
- Google Play services / Android biometric support available

If biometrics are unavailable on the device, the app hides the quick-unlock offer.

## Validation checklist

1. Confirm `android/app/google-services.json` exists.
2. Enable Email/Password and Google in Firebase Auth.
3. Run the app with `config/runtime/firebase.json`.
4. Create a new account with email/password.
5. Sign out and sign back in.
6. Trigger `Forgot password`.
7. Test Google sign-in.
8. Accept the fingerprint quick-unlock prompt after a successful sign-in.
9. Fully close and reopen the app, then confirm biometric unlock appears before the workspace.

## Failure behavior

Current expected behavior:

- missing Firebase Android config -> setup warning, no crash
- disabled Firebase provider -> friendly “not enabled” auth message
- duplicate email -> friendly duplicate-account message
- wrong password -> friendly incorrect-credentials message
- Google/provider collision -> guidance to sign in with the existing provider first

## Legacy local-account recovery

Before the Firebase-backed Android auth upgrade, local-only accounts were not durable across app restarts.

What that means:

- your board data may still be on the device
- the older local sign-in record may not be

If you see a local-account message telling you to use `Sign up` with the same email to reconnect, that is the intended recovery path for older local-only installs. The local account uid is derived from the email, so re-creating the same local account can reconnect you to the same user-scoped local workspace on that device.
