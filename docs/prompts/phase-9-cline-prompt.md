# Cline Prompt — Phase 9 (AI Breakdown + Controlled Automation)

Implement **Phase 9** for PlanDone, aligned to the deferred AI roadmap.

## Objective

Add AI-assisted planning capabilities that remain human-controlled, schema-validated, and fully compatible with the local-first architecture.

## Non-negotiables

1. No AI-driven writes without explicit user approval.
2. Preserve local-first write path (`Repository -> local -> outbox -> sync`).
3. Keep generated hierarchy flexible (Goal/Project/Task/Action).
4. Keep AI adapter/provider swappable.

## Scope to implement now

1. AI prompt input and provider abstraction.
2. Structured hierarchy generation parser + strict validation.
3. Staged review flow:
   - preview
   - edit/reorder/reparent/remove
   - explicit approve/reject
4. Commit approved output through standard local-first pathways.
5. Add/update tests and docs for AI safety and workflow behavior.

## Constraints

- Avoid lock-in to a single model/provider in core logic.
- Treat malformed AI output as recoverable user-facing errors.
- Do not bypass existing validation and permission rules.

## Required output from you

1. Brief implementation plan.
2. AI architecture/contracts summary.
3. Code + tests + docs.
4. Safety/risk notes and mitigations.
5. Phase-9 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can generate hierarchy suggestions from natural language.
- Users can review/edit/reject/approve before commit.
- Approved suggestions are persisted via local-first + sync-compatible flow.
- AI safety/validation behavior is tested and documented.

## Validation commands

- `flutter test`
- (optional) integration checks for AI adapter stubs/mocks
