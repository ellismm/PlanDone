# Cline Prompt — Phase 1 (Foundation Completion)

Implement **Phase 1** for PlanDone, aligned to these docs:

- `README.md`
- `docs/ project_outline.md`
- `docs/architecture.md`
- `docs/sequence.md`
- `docs/uml.md`
- `docs/branding/theme-system.md`

## Objective

Complete the app foundation so that authentication and local-first board workflows are production-grade before remote sync work.

## Non-negotiables

1. Do **not** redesign architecture.
2. Preserve layering: `UI -> State -> Domain -> Repository -> Data Sources`.
3. Keep local DB as source of truth.
4. Preserve flexible 4-level hierarchy (Goal/Project/Task/Action).
5. Keep app offline-first.

## Scope to implement now

1. Firebase Auth integration:
   - Email/password sign up/sign in
   - Google sign in
   - Sign out
2. Auth-gated app boot flow:
   - unauthenticated users see auth flow
   - authenticated users see board shell
3. User-scoped repository/provider wiring for board context.
4. Drift local store is default runtime path (in-memory only for tests/dev toggles).
5. Keep existing board/item operations stable offline.
6. Add/update tests for auth + route guards + local workflows.
7. Update docs/setup notes for auth and Firebase configuration.

## Constraints

- No broad refactors outside phase scope.
- Keep current working functionality unless required for correctness.
- Prefer incremental changes with clear commit-sized logical groupings.

## Required output from you

1. A short implementation plan before edits.
2. Code changes + tests.
3. A concise changed-file summary grouped by feature.
4. A checklist mapping to Phase 1 acceptance criteria.
5. A “what remains for Phase 2” handoff list.

## Acceptance criteria (must satisfy)

- User can authenticate via email/password and Google.
- Session state drives initial app routing.
- Board workflow functions while offline after login.
- Tests pass and include new auth-path coverage.
- Architecture direction remains intact.

## Validation commands

- `flutter pub get`
- `flutter test`
- (optional) `flutter run`
