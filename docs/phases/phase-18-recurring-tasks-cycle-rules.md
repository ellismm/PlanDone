# Phase 18 — Recurring Tasks & Cycle Rules

## Why this phase exists

Daily workflows need repeatable task cycles that stay deterministic offline and do not create duplicate instances during retries or reconnects.

## Scope

### In scope

- Recurrence model on supported work-item types (`task` and `action`).
- Completion-gated recurring generation.
- Deterministic late-completion policy for missed windows.
- Duplicate-safe generation behavior.
- Recurrence visibility/editing from item details and edit surfaces.

### Out of scope

- External calendar integrations.
- Enterprise RRULE behavior and complex exceptions.
- Non-completion-gated recurrence for the MVP.

## Implementation summary (completed)

- Added canonical recurrence model:
  - `WorkItemRecurrence`
  - cadence: `daily`, `weekly`, `customDays`
  - interval
  - root id + sequence for deterministic chain identity
  - `missedWindowPolicy`
- Preserved optional recurrence metadata on canonical `WorkItem`.
- Added deterministic recurring generation in the repository when completion transitions from incomplete to complete.
- Added duplicate suppression via `rootItemId + sequence` checks and deterministic generated ids.
- Added three late-completion policies:
  - `nextEligible`: skip forward until the next future cycle
  - `singleStep`: advance exactly one cycle even if it is already overdue
  - `manualCatchUp`: do not auto-generate if the next cycle was already missed
- Kept the MVP recurrence UX intentionally **completion-gated only**.

## Recurrence generation behavior

- Generation trigger: item completion transition.
- Guardrails:
  - only `task` and `action`
  - recurrence enabled
  - completion-gated behavior
- Next instance dates:
  - start/target-end/due advance by cadence and interval
  - late-completion policy decides what to do if the expected next window is already in the past
- Duplicate suppression:
  - checks existing instances for the same `rootItemId + sequence`
  - deterministic ids prevent duplicate local creations during retry/reconnect

## MVP decision

The personal MVP keeps recurrence intentionally simple:

- completion-gated only
- deterministic late-completion policy
- no calendar-engine complexity

## Edge-case notes

- `nextEligible` favors keeping the chain aligned to the next usable future slot.
- `singleStep` favors preserving a single next item even if the user completed the prior one late.
- `manualCatchUp` favors avoiding noisy overdue regeneration after long gaps.
- If a generated item would violate board validation constraints, generation is skipped safely.

## Validation notes

- Added tests for serialization, single-generation behavior, late-completion policy behavior, and duplicate suppression.
- Full `flutter test` passes.
