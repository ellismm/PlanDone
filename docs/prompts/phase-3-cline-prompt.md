# Cline Prompt — Phase 3 (Collaboration + Permissions + Security Rules)

Implement **Phase 3** for PlanDone, aligned to these docs:

- `docs/ project_outline.md`
- `docs/uml.md`
- Firestore structure described in docs

## Objective

Deliver secure and reliable collaboration with board membership governance and role-based enforcement.

## Non-negotiables

1. Maintain offline-first behavior.
2. Do not redesign architecture.
3. Enforce role behavior consistently across UI/domain/backend rules.
4. Backend rules must deny unauthorized writes.

## Scope to implement now

1. Member invite/join/manage flow for boards.
2. Role-capability enforcement:
   - viewer: read-only
   - member: work item modifications
   - admin/owner: board + member management
3. Firestore security rules and index updates.
4. Rules/integration tests (emulator preferred).
5. Board-level validation settings implementation.
6. UX polish for role-gated actions and failure messaging.
7. Documentation updates for setup and permission matrix.

## Constraints

- Avoid duplicated permission logic that can drift.
- Keep permission checks explicit and testable.
- Ensure outbox replay respects current permission state.

## Required output from you

1. Brief implementation plan.
2. Code + rules + tests.
3. Permission matrix mapping implemented behavior.
4. Summary of denied-action behavior (UI + backend).
5. Phase-3 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Unauthorized actions are blocked at UI and backend rule layers.
- Collaboration works between at least two users with realtime updates.
- Membership and role updates take effect correctly.
- Validation settings are board-configurable and documented.
- Tests pass for role-based scenarios.

## Validation commands

- `flutter test`
- Firestore emulator/rules test command(s) as configured
