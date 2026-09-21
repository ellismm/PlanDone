# Phase 2 — Sync & Realtime Completion (Outbox -> Firestore -> Local Hydration)

## Why this phase exists

The project’s core promise is offline-first collaboration. That only becomes real when local writes synchronize reliably and collaborator changes are hydrated back into local state.

## Scope

### In scope

- Firestore-backed sync adapter implementation.
- Idempotent operation apply strategy for outbox records.
- Robust retry behavior (attempt count, next attempt, error capture).
- Connectivity/retry orchestration for background + manual sync.
- Firestore listeners that hydrate Drift tables.
- LWW (last-write-wins) conflict behavior for v1.

### Out of scope

- Invite and permissions governance UI (Phase 3).
- AI features and activity timeline (Phase 4).

## Key implementation targets

1. Implement `SyncRemoteAdapter` for board/column/work-item/member operations.
2. Ensure outbox payload shapes are stable/versioned enough for retries.
3. Add listener layer that maps remote docs -> local write model.
4. Track sync state in local metadata where useful (optional per table).
5. Add integration-style tests for offline/online reconciliation paths.

## Implemented architecture notes (Phase 2)

- `BoardRepositoryImpl` remains local-first and optimistic:
  - local write first
  - enqueue deterministic outbox operation
- `SyncEngine` processes outbox in FIFO order and handles retries with persistence.
- The workspace sync lifecycle bridge keeps a timer aligned with the earliest
  `nextAttemptAt`, so exponential-backoff retries run automatically while the
  app is active. App resume still forces an immediate recovery attempt.
- `FirestoreSyncRemoteAdapter` applies operations to Firestore with:
  - operation idempotency markers (`boards/{boardId}/_appliedOps/{operationId}`)
  - LWW checks (`updatedAtMicros`) for v1 conflict behavior
- `FirestoreBoardHydrator` listens to Firestore docs/subcollections and hydrates local store:
  - board
  - members
  - columns
  - work items

UI continues to render exclusively from local store snapshots.

## Payload contract summary (v1)

All outbox payloads include:

- `version` = `1`
- `boardId`

Entity-specific required fields:

- `board`: `name`, `ownerId`, `createdAt`, `updatedAt`
- `boardMember`: `userId` (+ `role` for create/update)
- `column`: `columnId` (+ `name`/`orderIndex` where relevant)
- `workItem`: `itemId` (+ `title`/`type` for create, `columnId` for move paths)

## Retry/error scenarios

| Scenario | Behavior |
|---|---|
| Remote write fails (network/server) | Operation remains in queue; `attemptCount++`; `lastError`, `nextAttemptAt`, `lastAttemptAt` set |
| Operation scheduled in future | Normal sync skips until `nextAttemptAt` |
| Earliest `nextAttemptAt` arrives | Workspace retry scheduler starts a normal sync pass automatically |
| Manual force sync | Runs with `ignoreRetrySchedule=true`, attempts immediately |
| Duplicate operation replay | Adapter no-ops via `_appliedOps` marker |
| Older write vs newer remote state | LWW skip via `updatedAtMicros` comparison |

## Phase 2 acceptance checklist

- [x] Offline operations can be queued locally and synced later.
- [x] Failed ops persist with retry metadata.
- [x] Firestore collaborator-origin changes hydrate local state.
- [x] Local DB/store remains UI source of truth.
- [x] Tests cover success/failure/retry scheduling/force/hydration branches.

## Suggested operation contract hardening

- Required fields in outbox operation payload by entity type.
- Deterministic operation IDs for idempotency where possible.
- Clear handling of delete-after-create race scenarios.

## Risks and mitigations

- **Risk:** duplicate operations produce bad state remotely.  
  **Mitigation:** idempotent writes and server merge discipline.
- **Risk:** listener loops create local churn.  
  **Mitigation:** compare timestamps + skip no-op updates.
- **Risk:** drift in payload schema over time.  
  **Mitigation:** version field in outbox payload + migration notes.

## Acceptance criteria

- Offline create/update/move/delete/reorder syncs successfully after reconnect.
- Failed operations are retained with retry metadata and backoff.
- Firestore-origin changes from another client appear in local DB and UI.
- Local DB remains source of truth for rendering.
- Sync test coverage includes success, failure, skip/future retry, and force-retry paths.

## Exit artifacts

- Sync architecture notes updated with concrete adapter/listener flow.
- Troubleshooting guide for stuck outbox/replay.
- “Phase 2 complete” checklist and known limitations.
