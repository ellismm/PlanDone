# Phase 1 — Foundation Completion (Auth + Stable Local-First Baseline)

## Why this phase exists

Your docs define PlanDone as offline-first and collaborative, but collaboration quality depends on a stable identity layer and reliable local domain behavior first. Phase 1 finishes this baseline before deeper sync/collaboration work.

## Scope

### In scope

- Firebase project wiring and runtime configuration for Flutter.
- Authentication UX and flows:
  - Email/password sign up + sign in
  - Google sign in
  - Sign out
- App bootstrap and routing rules:
  - unauthenticated -> auth entry
  - authenticated -> board shell
- User-scoped board context in repository/state.
- Drift as default runtime store (in-memory retained for tests/dev).
- Validation that core board/item actions still work fully offline.

### Out of scope

- Firestore sync engine completion (Phase 2).
- Invite + role governance UI (Phase 3).
- AI breakdown and activity log (Phase 4).

## Key implementation targets

1. Add auth feature module (`lib/src/features/auth/...`) using Riverpod + clean layering.
2. Introduce session-aware providers and keep board providers tied to active user.
3. Ensure local data paths never block on network availability.
4. Add tests covering:
   - auth state transitions
   - route guard behavior
   - board access with authenticated user context

## Risks and mitigations

- **Risk:** auth integration leaks into domain logic.  
  **Mitigation:** keep auth concerns in state/repository boundaries.
- **Risk:** local seed data or tests become brittle with user scoping.  
  **Mitigation:** centralize default test identities + helper builders.

## Acceptance criteria

- User can register/login/logout with email/password and Google.
- App does not show board experience unless authenticated.
- Core board operations work while offline (local DB source of truth).
- Existing core tests remain green; new auth tests added.
- No architectural inversion (no UI -> Data shortcuts).

## Exit artifacts

- Updated `README.md` setup notes (auth + firebase config steps).
- New/updated architecture notes for auth boundaries.
- Clear “Phase 1 done / Phase 2 next” handoff checklist.

## Implementation notes (current)

- Auth flow is now gated at app boot via session provider:
  - `session == null` -> auth page
  - `session != null` -> board shell
- Android auth now supports:
  - email/password sign-up with display name
  - email/password sign-in
  - Google sign-in
  - password reset
  - biometric quick unlock after a prior successful Android sign-in
- Missing Android Firebase config now degrades into a friendly setup warning instead of a bootstrap crash.
- Drift remains the default runtime path for board local data.
- In-memory board/local settings path remains available for tests/dev toggles.
- Board runtime is scoped by authenticated user identity to preserve separation.
