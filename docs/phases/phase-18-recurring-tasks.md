# Phase 18 — Recurring Tasks & Cycle Rules

## Why this phase exists

Many real workflows are recurring. Users need recurring-item support that respects completion state and avoids noisy duplicates.

## Scope

### In scope

- Recurrence settings for supported items (`task` and `action`).
- Completion-gated recurring generation.
- Deterministic late-completion policy for missed windows.
- Local-first duplicate-safe generation.
- Visibility and editing of recurrence state in item details.

### Out of scope

- External calendar sync.
- Enterprise RRULE parity.
- Non-completion-gated recurrence for the MVP.

## Implementation summary (completed)

- Added `WorkItemRecurrence` to the canonical item model.
- Added cadence/interval support plus deterministic root/sequence identity.
- Added `missedWindowPolicy` with:
  - `nextEligible`
  - `singleStep`
  - `manualCatchUp`
- Added completion-triggered next-instance generation with duplicate suppression.
- Integrated recurrence controls and recurrence summaries into item details/editing.
- Preserved existing validation and permission boundaries.

## Recurrence rules reference

- Only `task` and `action` items may recur.
- The MVP keeps recurrence **completion-gated only**.
- Completing an eligible recurring item attempts to generate exactly one next instance.
- Duplicate generation is prevented through root/sequence checks and deterministic ids.
- Late completion is handled by the selected missed-window policy.

## Validation notes

- Added targeted tests for recurrence model behavior, duplicate suppression, and late-completion handling.
- Full `flutter test` passes.
