# Cline Prompt — Phase 17 (Notifications & Alert Preferences)

Implement **Phase 17** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Add practical reminders and user-controlled alert preferences to support daily execution without alert fatigue.

## Non-negotiables

1. Preserve local-first/offline-first guarantees.
2. Preserve permission boundaries and least-privilege assumptions.
3. Keep reminder behavior deterministic and understandable.
4. Avoid broad platform migration for notification delivery.

## Scope to implement now

1. Add notification preference model + settings UI.
2. Add reminder scheduling for date-based metadata (start/due baseline).
3. Add alert timing controls, mute/snooze where practical.
4. Ensure offline/online transitions reconcile schedules safely.
5. Add/update tests for scheduling logic and preference enforcement.
6. Update docs and readiness checklist.

## Constraints

- No enterprise notification center scope.
- Keep defaults conservative to avoid noisy alerts.
- Preserve existing board/item operation contracts.

## Required output from you

1. Brief implementation plan.
2. Notification model and scheduling summary.
3. Code + tests + docs.
4. Edge-case notes (offline reschedule, stale reminders).
5. Phase-17 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can configure reminder behavior clearly.
- Alerts follow user preferences and relevant item metadata.
- Notification behavior remains coherent after offline/online transitions.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted reminder scheduling tests
