# Phase 3 — Collaboration, Roles, and Security Rules

## Why this phase exists

PlanDone is collaborative by definition. Local role checks are useful, but real collaboration quality requires backend-enforced permissions and complete member governance.

## Scope

### In scope

- Member invite/join flows for boards.
- Role-based capability enforcement (viewer/member/admin/owner) across:
  - UI affordances
  - state/controller guardrails
  - repository checks
  - Firestore security rules
- Board management operations (rename/config/members).
- Board-level validation rule settings (while keeping title globally required only).
- Required Firestore indexes and rules documentation.

### Out of scope

- AI planning/breakdown logic (Phase 4).

## Key implementation targets

1. Build membership APIs and UI workflows (add/update/remove members).
2. Align role checks with docs philosophy:
   - viewer: read-only
   - member: item-level modifications
   - admin/owner: board + member governance
3. Add Firestore rules tests (emulator-driven preferred).
4. Ensure sync behavior respects role constraints when replaying outbox ops.

## Risks and mitigations

- **Risk:** mismatch between app checks and security rules.  
  **Mitigation:** treat rules as source of truth; add failing tests for forbidden actions.
- **Risk:** stale local role data causes temporary UI mismatch.  
  **Mitigation:** prioritize listener hydration for member records and graceful failure handling.

## Acceptance criteria

- Unauthorized operations are blocked both in UI flow and by backend rules.
- Two-user collaboration scenario works with realtime updates.
- Membership changes propagate and take effect promptly.
- Validation rule behaviors are configurable per board and documented.
- Rule/index setup is reproducible via docs.

## Exit artifacts

- `firestore.rules` and supporting test files.
- Collaboration setup/testing guide.
- Permission matrix reference in docs.
