# Phase 19 — Smart Autofill & Predictive Defaults (Non-AI)

## Why this phase exists

Users can move faster if repetitive fields are pre-filled intelligently using deterministic heuristics from recent behavior.

## Scope

### In scope

- Heuristic autofill defaults for item creation/editing (non-LLM).
- Suggestions from recent board/column/type/parent patterns.
- Optional suggested tags and estimate defaults from user history.
- Clear user override controls and ability to disable suggestions.
- Privacy-safe local inference from local data by default.

### Out of scope

- Cloud AI inference or generative breakdown logic.
- Opaque scoring models that are hard to explain.

## Key implementation targets

1. Define lightweight suggestion engine using recent deterministic patterns.
2. Integrate suggestion hints into create/edit flow without blocking manual input.
3. Add user preference controls for enabling/disabling autofill dimensions.
4. Track suggestion acceptance rates locally for tuning.
5. Add tests for deterministic suggestion outputs and fallback behavior.

## Risks and mitigations

- **Risk:** wrong suggestions reduce trust.  
  **Mitigation:** always optional, transparent, and easy to override.
- **Risk:** suggestion logic drifts into hidden complexity.  
  **Mitigation:** keep heuristics simple and documented.

## Acceptance criteria

- Common fields are pre-filled accurately for frequent workflows.
- Suggestions never block manual control.
- Behavior is deterministic, explainable, and settings-controlled.
- Tests/docs are updated and coherent.

## Exit artifacts

- Autofill heuristics spec.
- Settings and UX behavior reference.
- Phase completion summary.
