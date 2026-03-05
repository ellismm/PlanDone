# Phase 19 - Smart Autofill & Predictive Defaults (Non-AI)

## Why this phase exists

Item creation/editing should be faster for daily usage without introducing opaque or cloud-based behavior.

## Scope

### In scope

- Deterministic local suggestion engine based on recent board patterns.
- Suggested defaults for type, column, parent, tags, estimate, and triage board where applicable.
- Per-user controls to enable/disable suggestion dimensions.
- Manual override remains first-class and frictionless.
- Tests/docs for deterministic output and fallback behavior.

### Out of scope

- AI/LLM-based suggestions.
- Cloud inference/model-serving.

## Implementation summary (completed)

- Added `AutofillSettings` (user-scoped) with toggles for:
  - overall enable
  - board/column/type/parent/tag/estimate suggestion dimensions
- Added local settings repository implementations:
  - `DriftAutofillSettingsRepository`
  - `InMemoryAutofillSettingsRepository`
- Added deterministic policy engine:
  - `AutofillSuggestionPolicy.forCreateItem(...)`
  - `AutofillSuggestionPolicy.suggestBoardForInboxTriage(...)`
- Integrated suggestions into key flows:
  - Add Item dialog pre-fills suggested type/column/parent/tags/estimate
  - explicit "Apply suggested defaults" action to re-apply
  - Inbox triage board target pre-selection from deterministic overlap scoring
- Added user controls in both Workspace and Board Configuration surfaces.

## Heuristic summary

- History window: last N recent local items (deterministic ordering by `updatedAt` desc).
- Type: most frequent recent type.
- Column: most frequent recent column for selected/effective type.
- Parent: most frequent valid higher-level parent for selected type.
- Tags: top-frequency tags from type-scoped recent history.
- Estimate: median of recent positive estimates for selected/effective type.
- Triage board: highest deterministic score from tag overlap + title token overlap.

## Edge-case notes

- Cold start/no history: falls back to stable defaults (`action`, first active column, no parent/tags/estimate).
- Stale suggestions: strictly local and deterministic; user can reapply manually or disable dimensions.
- Manual override safety: any user-edited value stays primary unless they explicitly reapply defaults.

## Validation notes

- Added tests for:
  - deterministic suggestion outputs
  - cold-start fallback behavior
  - triage-board suggestion scoring
  - settings persistence in memory + drift
