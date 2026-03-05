# Phase 17 — Notifications & Alert Preferences

## Why this phase exists

Daily use requires reminders and alerts that are configurable and non-intrusive, with explicit user control over channels and timing.

## Scope

### In scope

- Notification preferences surface per user.
- Local notification support for key events/reminders.
- Configurable alert timing for due/start reminders.
- Mute/snooze controls and digest-style options where practical.
- Offline-safe scheduling behavior with reconciliation on reconnect.

### Out of scope

- Full multi-channel enterprise notification center.
- Complex cross-platform push backend migration.

## Key implementation targets

1. Define notification preference model and persistence path.
2. Implement reminder scheduling for key date-based metadata.
3. Add user-facing controls for alert type/frequency/timing.
4. Ensure notifications respect permissions and board visibility boundaries.
5. Add tests for scheduling logic and preference application.

## Risks and mitigations

- **Risk:** alert fatigue from noisy defaults.  
  **Mitigation:** conservative default policy + easy opt-out.
- **Risk:** unreliable schedules after offline periods.  
  **Mitigation:** deterministic re-evaluation on app resume/sync.

## Acceptance criteria

- Users can configure and trust reminder behavior.
- Alerts align with due/start metadata and user settings.
- Notification behavior remains coherent across offline/online transitions.
- Tests/docs are updated and coherent.

## Exit artifacts

- Notification preference matrix.
- Reminder scheduling behavior doc.
- Phase completion summary.

## Implementation summary (completed)

- Added a user-scoped `NotificationPreferences` model with:
  - enable/disable reminders
  - due/start reminder toggles
  - lead-time controls
  - default snooze duration
  - temporary mute-until
  - persisted per-reminder snooze map
- Added `NotificationPreferencesRepository` with local implementations:
  - `DriftNotificationPreferencesRepository` (stored in local `app_settings`)
  - `InMemoryNotificationPreferencesRepository` (test/dev path)
- Added deterministic scheduling policy:
  - `NotificationReminderPolicy.buildActiveReminders(...)`
  - computes reminders from canonical work-item metadata (`startAt`, `dueAt`)
  - suppresses archived/completed items
  - suppresses muted/snoozed reminders
  - filters stale reminders to avoid noisy backlog
- Added workspace reminder UX:
  - reminder badge in workspace app bar
  - reminder center bottom-sheet with per-alert snooze
  - top banner for highest-priority reminder with quick actions:
    - snooze
    - mute for 8h
    - view all
- Added notification settings UI in two places:
  - workspace notification preferences dialog
  - board configuration `Notification Preferences` entry
- Added controller/providers for reminder flow:
  - notification preferences load/save
  - reminder clock tick for deterministic reevaluation
  - active reminder provider derived from board snapshot + preferences + clock

## Reminder behavior reference

- Due reminders: trigger at `dueAt - dueReminderMinutesBefore`.
- Start reminders: trigger at `startAt - startReminderMinutesBefore`.
- Muted state: suppresses all reminders until `mutedUntil`.
- Snoozed state: suppresses matching reminder id until snooze expiry.
- Offline/online coherence: reminders are derived from local canonical data and
  reevaluated on clock ticks and state updates, so behavior remains deterministic
  across connectivity changes.

## Validation notes

- Added unit tests for:
  - preference serialization defaults/round-trip
  - scheduling correctness and suppression behavior
  - drift/in-memory preference repository persistence
