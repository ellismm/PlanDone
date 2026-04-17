# Phase 17 — Notifications & Alert Preferences

## Why this phase exists

Daily use requires reminders that are understandable, conservative, and reliable even when the app is backgrounded.

## Scope

### In scope

- User-scoped notification preferences.
- Deterministic start/due reminder evaluation from canonical item metadata.
- Local Android scheduled notification delivery for due/start reminders.
- Mute and snooze controls.
- Offline-safe schedule reconciliation on app bootstrap and data changes.

### Out of scope

- Full multi-channel enterprise notification center.
- Automated server-triggered reminder backend.
- Cross-platform notification parity.

## Implementation summary (completed)

- Added a user-scoped `NotificationPreferences` model with:
  - enable/disable reminders
  - due/start reminder toggles
  - lead-time controls
  - default snooze duration
  - temporary mute-until
  - persisted per-reminder snooze map
- Added `NotificationPreferencesRepository` with local implementations:
  - `DriftNotificationPreferencesRepository`
  - `InMemoryNotificationPreferencesRepository`
- Added deterministic reminder policy:
  - `NotificationReminderPolicy.buildActiveReminders(...)`
  - `NotificationReminderPolicy.buildScheduledReminders(...)`
- Added workspace reminder UX:
  - reminder badge in workspace app bar
  - reminder center bottom sheet with per-alert snooze
  - top banner for highest-priority reminder with quick actions
- Added notification settings UI in Workspace and Board Configuration.
- Added local reminder delivery adapter:
  - `LocalNotificationDelivery`
  - Android `AlarmManager`-backed scheduling through a method channel
- Added Android reminder platform support:
  - notification channel creation
  - runtime notification permission request
  - alarm receiver for scheduled delivery
  - boot/package-replace receiver for deterministic rescheduling after reboot/update
- Kept optional FCM device-token registration as an extension path, not the MVP baseline.

## Reminder behavior reference

- Due reminders trigger at `dueAt - dueReminderMinutesBefore`.
- Start reminders trigger at `startAt - startReminderMinutesBefore`.
- Archived and completed items do not schedule reminders.
- Muted state suppresses all reminders until `mutedUntil`.
- Snoozed state suppresses a reminder until its snooze expiry.
- Future reminders are mirrored into Android local scheduled notifications.
- Schedule reconciliation occurs from local canonical data, so offline/online transitions remain deterministic.

## MVP decision

The baseline personal MVP uses **local scheduled Android reminders first**.

That keeps reminder delivery:

- offline-safe
- device-local
- simpler than a server push pipeline

Optional FCM token registration remains available for future extension work, but it is not required for the baseline reminder experience.

## Validation notes

- Added unit tests for scheduling correctness and suppression behavior.
- Full `flutter test` passes.
- Physical Android smoke testing is still recommended for background/closed-app reminder delivery.
