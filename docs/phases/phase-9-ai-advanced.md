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

## Implementation status — 2026-08-26

The human-controlled Phase 9 vertical slice is implemented:

- `AiPlanningProvider` keeps generation swappable.
- `FirebaseAiPlanningProvider` uses Firebase AI Logic with Firebase Auth and
  App Check; no private model-provider secret is embedded in the APK.
- `AiPlanningDraftParser` accepts only the documented JSON object and rejects
  unknown fields, invalid types, duplicate/missing ids, oversized output,
  invalid parent direction, and hierarchy cycles.
- `AiPlanningPage` discloses what context is sent, keeps the response in memory,
  and supports edit, remove, sibling-only arrow reordering, reparent, reject,
  and explicit approval. Reordering moves a complete branch, preserves every
  parent link, and carries the reviewed sibling order into the approved commit.
- `AiPlanningCommitService` preflights board requirements, creates parents
  before children, labels approved records `ai-assisted`, and writes through
  `BoardRepository.createItem` so local persistence, activity history, and the
  outbox remain the only mutation path.

### Generated response contract

The model returns one JSON object:

```json
{
  "summary": "Why this breakdown is useful",
  "items": [
    {
      "id": "stable-draft-id",
      "title": "Concrete title",
      "type": "goal|project|task|action",
      "parentId": "optional-higher-level-draft-id",
      "description": "optional guidance",
      "tags": ["optional", "tags"],
      "estimatedEffortMinutes": 30
    }
  ]
}
```

Limits are enforced again in app code even though Firebase structured output
also receives a schema: 2,000 prompt characters, 64 absolute draft items (the
UI offers 12/24/32), 160-character titles, 1,200-character descriptions, eight
tags per item, and no cyclic or downward parent relationship.

### Activation status

On 2026-08-26, `plandone-staging` was activated on the no-cost Gemini Developer
API while remaining on the Spark plan. AI monitoring is off. Firebase AI Logic
is App Check-enforced, and the Android app is registered with Play Integrity
for the current off-Play signing certificate. The Firebase runtime profile now
sets `USE_FIREBASE_AI=true`; the local profile remains disabled.

The remaining acceptance gate is a real physical-device
generation/review/reject/approve smoke pass. Any future production signing
certificate must be registered before distributing that build.

Automated validation on 2026-08-26: `flutter analyze` reported no issues,
`flutter test` passed 224 tests with 10 skips, and the Firebase-profile Android
release APK built successfully.
