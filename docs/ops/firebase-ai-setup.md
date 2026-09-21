# Firebase AI Planning Setup

Phase 9 uses Firebase AI Logic rather than embedding a private provider API key
in the Android application.

## Project activation

1. Open Firebase AI Logic for the target Firebase project and complete **Get
   started**.
2. Select the Gemini Developer API for the initial staging rollout unless the
   project deliberately uses the billed Vertex AI backend.
3. Register the Android application under Firebase App Check.
4. Configure Play Integrity for release builds and register each distributed
   signing certificate's SHA-256 fingerprint.
5. Enforce App Check for Firebase AI Logic.

`plandone-staging` was activated on the Spark plan on 2026-08-26 using the
no-cost Gemini Developer API. AI monitoring is disabled. Firebase AI Logic is
App Check-enforced, and the Android app is registered with Play Integrity for
the current off-Play signing certificate. Off-Play attestation does not require
`PLAY_RECOGNIZED` or `LICENSED`; it requires device integrity.

Official references:

- <https://firebase.google.com/docs/ai-logic/get-started?platform=dart>
- <https://firebase.google.com/docs/ai-logic/app-check>
- <https://firebase.google.com/docs/ai-logic/production-checklist>

## Runtime flags

The Firebase profile enables AI while the local-only profile keeps it disabled:

```json
"USE_FIREBASE_AI": true,
"PLANDONE_FIREBASE_AI_MODEL": "gemini-3.5-flash",
"PLANDONE_FIREBASE_AI_FALLBACK_MODEL": "gemini-3.5-flash-lite"
```

The primary model is always attempted first. PlanDone retries exactly once on
a quota-exceeded response using the free fallback model. Authorization,
configuration, parsing, and other service errors never trigger the fallback.

Do not enable AI in `config/runtime/local.json`; runtime validation rejects AI
without Firebase Auth.

## App Check behavior

- Flutter debug builds use the App Check debug provider. Register the debug
  token printed by Firebase before testing model calls.
- Release builds use Play Integrity. Every signing certificate used for a
  distributed build must be registered before that build can call AI Logic.
- App Check activation failure does not block the offline-first board. The AI
  page instead reports a recoverable authorization error and performs no write.

## Manual validation

1. Open **Workspace -> Plan with AI**.
2. Read the data-sharing disclosure.
3. Generate a small hierarchy and verify nothing appears on the board.
4. Edit, reparent, and remove draft entries in the hierarchy preview.
5. Reject the draft and verify the board/outbox remain unchanged.
6. Generate again, approve, and verify items appear in a planning-like column.
7. Verify parent relationships, `ai-assisted` tags, activity events, and outbox
   sync.
8. Submit malformed/oversized adapter fixtures in automated tests and confirm
   they fail without writes.
