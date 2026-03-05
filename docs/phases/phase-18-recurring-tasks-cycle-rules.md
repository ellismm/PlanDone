# Phase 18 — Recurring Tasks & Cycle Rules

## Why this phase exists

Daily workflows need repeatable task cycles (especially weekly habits) that are reliable offline and do not create duplicate instances during retry/reconnect flows.

## Scope

### In scope

- Recurrence model on supported work-item types (task/action).
- Completion-gated recurring generation.
- Deterministic, duplicate-safe generation behavior.
- Recurrence visibility/editing from item details/edit surfaces.
- Tests for generation lifecycle and duplicate suppression.

### Out of scope

- External calendar integrations.
- Enterprise calendar rules and exception scheduling.

## Implementation summary (completed)

- Added canonical recurrence model:
  - `WorkItemRecurrence`
  - cadence: `daily`, `weekly`, `customDays`
  - interval (positive integer)
  - completion-gated toggle
  - root id + sequence for deterministic chain identity
- Extended canonical `WorkItem` with optional recurrence metadata.
- Added deterministic recurring generation in repository when completion transitions `incomplete -> complete`.
- Added duplicate suppression via `rootItemId + sequence` existence checks and deterministic generated id (`w-rec-{root}-{sequence}`).
- Added missed-window handling by advancing next date until it is after completion time.
- Preserved existing permissions/validation boundaries and reused existing mutation paths.
- Added recurrence controls in item edit/details surfaces.

## Recurrence generation behavior

- Generation trigger: item completion transition.
- Guardrails:
  - only task/action items
  - recurrence enabled
  - completion-gated enabled
- Next instance dates:
  - start/target-end/due advance by configured cadence/interval
  - if advanced date is still in past relative to completion, continue advancing until future
- Duplicate suppression:
  - checks existing instances for same `rootItemId` + `sequence`
  - deterministic id generation prevents duplicate local creations

## Edge-case notes

- Missed windows: skipped forward deterministically to next valid future cycle.
- Duplicate suppression: retries/reconnects do not create duplicate next instances for same sequence.
- If recurrence-generated item would violate board validation constraints, generation is skipped safely.

## Validation notes

- Added targeted tests for:
  - recurrence model serialization/interval behavior
  - single-generation behavior on completion
  - sequence advancement from generated instances
  - missed-window date advancement behavior
