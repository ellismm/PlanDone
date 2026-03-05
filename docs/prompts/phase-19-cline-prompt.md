# Cline Prompt — Phase 19 (Smart Autofill & Predictive Defaults, Non-AI)

Implement **Phase 19** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Speed up everyday item creation/editing with deterministic, non-AI autofill suggestions based on recent user patterns.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Keep suggestions deterministic, explainable, and optional.
3. Preserve role/permission boundaries.
4. Do not introduce AI/LLM dependencies in this phase.

## Scope to implement now

1. Add deterministic suggestion engine using recent local patterns.
2. Suggest defaults for board/column/type/parent/tags/estimate where applicable.
3. Add user controls to enable/disable suggestion dimensions.
4. Ensure manual overrides remain primary and frictionless.
5. Add/update tests for deterministic outputs and fallback behavior.
6. Update docs and readiness checklist.

## Constraints

- No cloud inference or model-serving scope.
- Keep logic lightweight and maintainable.
- Avoid hidden behavior that users cannot understand.

## Required output from you

1. Brief implementation plan.
2. Autofill heuristic summary.
3. Code + tests + docs.
4. Edge-case notes (cold start/no history, stale suggestions).
5. Phase-19 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Suggestions improve speed for common workflows.
- Users can override or disable suggestions easily.
- Suggestion behavior is deterministic and settings-controlled.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted suggestion engine tests
