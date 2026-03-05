# Cline Prompt — Phase 2 (Sync + Realtime Completion)

Implement **Phase 2** for PlanDone, aligned to these docs:

- `README.md`
- `docs/ project_outline.md`
- `docs/architecture.md`
- `docs/sequence.md`
- `docs/uml.md`

## Objective

Complete the true offline-first synchronization loop:

`local write -> outbox queue -> sync push to Firestore -> listener hydration back to local DB`.

## Non-negotiables

1. No architecture redesign.
2. Local DB remains source of truth for UI.
3. Preserve optimistic UI behavior.
4. Implement LWW conflict strategy for v1.
5. Keep operation processing idempotent.

## Scope to implement now

1. Implement Firestore-backed `SyncRemoteAdapter` for supported entities.
2. Finalize outbox operation contract and retry metadata handling.
3. Ensure sync engine reliability:
   - retries
   - exponential backoff
   - failure persistence
   - force retry path
4. Add Firestore listeners to hydrate Drift local tables.
5. Ensure collaborator-origin changes are reflected locally.
6. Expand tests for success/failure/retry/hydration scenarios.
7. Update docs with sync architecture and troubleshooting guidance.

## Constraints

- No bypass writes directly from UI to Firestore.
- Outbox operation payloads must remain deterministic and debuggable.
- Preserve existing feature behavior unless required for correctness.

## Required output from you

1. Brief implementation plan before edits.
2. Code + tests for sync adapter/listener paths.
3. Summary of payload contract changes.
4. A table of error/retry scenarios and how they are handled.
5. Phase-2 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Offline operations sync successfully on reconnect.
- Failed operations remain in queue with retry metadata.
- Firestore updates from another client hydrate local DB.
- UI continues reading from local source of truth.
- Tests pass for sync behavior branches.

## Validation commands

- `flutter test`
- (optional) emulator/integration commands if configured
