# Phase 9 — AI Breakdown, Advanced Insights & Controlled Automation

## Why this phase exists

AI remains part of the long-term vision, but it should be introduced only after usability, workflow clarity, and reliability are proven. This phase adds AI-assisted planning while preserving user control and local-first guarantees.

## Scope

### In scope

- AI breakdown workflow:
  - natural-language prompt input
  - structured hierarchy proposal (Goal/Project/Task/Action)
  - review-before-commit UX
- Strict schema/parser validation for AI-generated structures.
- Local staging model for generated drafts.
- Optional advanced insights tied to planning quality (non-destructive suggestions).
- Commit approved results through the same local-first + outbox pipeline.

### Out of scope

- Autonomous agent behavior that bypasses explicit user approval.
- Opaque AI writes directly to cloud data stores.

## Key implementation targets

1. Add swappable AI provider abstraction and adapters.
2. Define explicit generated-data contracts with validation/error handling.
3. Build editable review flow (edit/remove/reorder/reparent before commit).
4. Capture AI-related actions in activity/audit timeline where appropriate.
5. Add tests for parser safety, review flow, and commit invariants.

## AI safety and consistency rules

- No direct production mutation without user confirmation.
- All approved AI output must pass repository/domain validation rules.
- Generated hierarchy must preserve flexible parent-child relationships.
- AI integration must not force enterprise-heavy process complexity.

## Risks and mitigations

- **Risk:** low-quality or malformed model output.  
  **Mitigation:** schema validation + mandatory user review/edit stage.
- **Risk:** AI suggestions reduce trust if inconsistent.  
  **Mitigation:** transparent explanations, easy rejection, deterministic commit behavior.
- **Risk:** AI path diverges from local-first architecture.  
  **Mitigation:** enforce the same repository/outbox write pathway.

## Acceptance criteria

- Users can generate hierarchy suggestions from natural language.
- Users can review/edit/reject/approve before any commit.
- Approved suggestions are written locally and sync through normal pathways.
- Safety guards and tests are documented and passing.

## Exit artifacts

- AI architecture and provider contract note.
- Generated-schema and validation reference.
- Phase-9 checklist completion summary.
