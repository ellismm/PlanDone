# Known Limitations

Current as of September 20, 2026.

## Notifications

- Baseline reminder delivery is implemented with **local scheduled notifications on Android**.
- iOS, web, and desktop do not yet have equivalent reminder delivery.
- Optional FCM setup supports device token registration and manual push testing, but automated server-triggered reminder delivery is not part of the MVP.

## Backup and restore

- Backup restore imports data as a **new board**.
- Restore does not perform merge/conflict resolution into an existing board.
- Restored boards are re-owned by the current local user; collaborator membership is not fully restored.
- Android cloud backup and device-transfer extraction are disabled to keep the
  local database, credentials, preferences, and app-managed JSON snapshots out
  of OS backup transports.
- App-managed JSON snapshots remain inside PlanDone's private storage and are
  removed if the app is uninstalled or its storage is cleared. Synced board
  data can still be recovered from Firestore after signing in.

## Recurrence

- MVP recurrence is intentionally **completion-gated only**.
- There is no enterprise calendar/RRULE support.
- There is no catch-up batch generation for every missed interval; behavior is controlled by the selected late-completion policy.

## Metadata and time tracking

- Automatic lifecycle timestamps are supported for created/completed states, but true working-time tracking is still only a basic manual/derived baseline.
- There is no advanced custom-fields framework yet.

## Collaboration and operations

- The product is optimized for personal daily use first, not polished small-team rollout.
- Build 14 still needs direct physical-device confirmation for Undo and the
  complete offline create/edit/move/archive sequence before it is treated as
  the final MVP release candidate.
- Automated analyze, Flutter tests, Firestore rules tests, and the Android
  build are clean, but they do not replace those device-only checks.

## Operational constraints and deferred work

- AI-assisted planning is enabled in the Firebase profile and live generation
  has succeeded through Firebase AI Logic. Formal Phase 9 acceptance still
  requires one recorded end-to-end generation/review/reject/approve pass on a
  physical device under App Check.
- AI availability and latency remain subject to free-tier quota and temporary
  model-capacity limits; the app fails safely without writing a draft.
- automated backend push notification workflows
- cross-platform reminder parity
- merge-based import UX
