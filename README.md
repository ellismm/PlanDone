# PlanDone

PlanDone is an **offline-first**, collaborative Kanban app with a flexible 4-level hierarchy:

- Goal
- Project
- Task
- Action

This repository is now bootstrapped with a Flutter-friendly starter structure aligned to the docs in `docs/`:

- clean layering direction (`UI -> State -> Domain -> Repository -> Data Sources`)
- local-first write flow
- outbox operation queue abstraction
- basic Kanban board UI stub with optimistic updates

## Phase 1 foundation status

Phase 1 now includes:

- Auth-gated boot flow (unauthenticated -> auth, authenticated -> board)
- Auth feature layering (`UI -> State -> Domain -> Repository -> Data Source`)
- Email/password + Google sign-in APIs wired through Firebase-capable data source
- Sign-out support from board shell
- User-scoped board runtime context
- Drift default local runtime path (in-memory default in tests)

## Current status

This is a project starter (Phase 1 foundation), not full production functionality yet.

Implemented:

- Initial app shell (`MaterialApp` + Riverpod)
- Domain models for `Board`, `Column`, `WorkItem`
- Local store abstraction and in-memory implementation
- Outbox queue abstraction and in-memory implementation
- Repository implementing local-write + queue-op flow
- Simple Kanban screen that can move items between columns

## Run (after creating platform folders)

If Flutter is installed:

1. Create standard Flutter platform folders if needed:

```bash
flutter create .
```

2. Get packages:

```bash
flutter pub get
```

3. Run:

```bash
flutter run
```

### Runtime toggles

- `USE_IN_MEMORY_LOCAL_STORE=true` -> force in-memory board/theme stores (dev/test)
- `USE_FIREBASE_AUTH=true` -> enable Firebase auth runtime path
- `USE_FIREBASE_SYNC=true` -> enable Firestore sync adapter + listener hydration path (Phase 2)

Example:

```bash
flutter run --dart-define=USE_FIREBASE_AUTH=true
```

Enable auth + sync together:

```bash
flutter run --dart-define=USE_FIREBASE_AUTH=true --dart-define=USE_FIREBASE_SYNC=true
```

### Deploy latest APK to Android device

This script always rebuilds before install so deployment uses current workspace code:

```bash
scripts/deploy_android_latest.sh
```

Optional explicit target:

```bash
scripts/deploy_android_latest.sh <device-id>
```

## Phase 2 sync contract (offline-first loop)

Implemented loop:

`local write -> outbox queue -> SyncEngine push to Firestore -> Firestore listeners hydrate Drift -> UI reads local`

### Outbox payload contract

- Every outbox payload includes:
  - `version` (currently `1`)
  - `boardId`
- Work-item write payloads include deterministic fields for replay/debugging:
  - `itemId`, `columnId` (plus legacy-compatible `toColumnId`), `updatedAt`
- Operation IDs are deterministic enough for debugging and idempotent remote markers:
  - `op-<micros>-<type>-<entity>-<entityId>`

### Retry + failure handling

- Failed operations remain in queue.
- Metadata persisted in outbox:
  - `attemptCount`
  - `lastError`
  - `nextAttemptAt`
  - `lastAttemptAt`
- Exponential backoff with max cap is applied by `SyncEngine`.
- Force retry path is available via `syncPending(ignoreRetrySchedule: true)`.

### Conflict strategy (v1)

- LWW (Last Write Wins) via `updatedAtMicros` comparison in Firestore adapter.
- Older operations do not overwrite newer remote state.

### Idempotency

- Firestore adapter writes per-operation apply markers at:
  - `boards/{boardId}/_appliedOps/{operationId}`
- Duplicate operation IDs are skipped remotely.

## Troubleshooting sync

- **Outbox not draining**
  - Verify `USE_FIREBASE_SYNC=true` and Firebase initialization/config.
  - Check pending operations from UI outbox sheet.
  - Trigger manual sync from UI (`Sync now`).
- **Repeated failures**
  - Inspect `lastError`, `attemptCount`, `nextAttemptAt` in outbox table.
  - Use force retry path (manual sync) to bypass scheduled delay.
- **Collaborator updates not visible**
  - Ensure Drift path is active (`USE_IN_MEMORY_LOCAL_STORE=false`) and hydration listener is enabled.
  - Confirm listener targets the active board scope.

## Phase 3 collaboration + permissions

Phase 3 is implemented with role-governed collaboration across domain/UI/backend layers.

### Permission matrix (implemented)

| Role | Read board | Modify work items | Manage board (name/columns/validation) | Manage members (invite/role/remove) | Accept own pending invite |
| --- | --- | --- | --- | --- | --- |
| viewer | ✅ | ❌ | ❌ | ❌ | n/a |
| member | ✅ | ✅ | ❌ | ❌ | ✅ (only when pending) |
| admin | ✅ | ✅ | ✅ | ✅ | n/a |
| owner | ✅ | ✅ | ✅ | ✅ | n/a |

### Denied-action behavior

- **UI layer**
  - Role-gated actions are disabled or intercepted with explicit feedback.
  - Guarded actions surface `SnackBar` messages for permission and validation failures.
  - Examples:
    - Viewer/member trying board-management actions: `Current role cannot manage board settings.`
    - Viewer trying item mutation: `Current role cannot modify items in this board.`
    - Unauthorized member governance: `Current role cannot manage board members.`

- **Domain/repository layer**
  - `BoardRepositoryImpl` centralizes capability checks via `_requireCapability(...)`.
  - Denials throw `BoardPermissionDeniedException`.
  - Validation settings are enforced by `BoardValidationPolicy` and throw `BoardValidationException`.

- **Backend/rules layer**
  - Firestore rules enforce the same role model on writes.
  - Owner role is protected against downgrade/removal.
  - Pending invites (`joinedAtEpochMillis <= 0`) are prevented from item mutation until accepted.

- **Sync/outbox layer**
  - Firestore `permission-denied` maps to `SyncRemotePermissionDeniedException`.
  - `SyncEngine` treats permission denied as non-retryable and drops the op from queue.

### Board validation settings

Per-board toggles are supported and persisted in `board.validationSettings`:

- `requireParentForProjects`
- `requireParentForTasks`
- `requireParentForActions`
- `enforceParentTypeOrder`

Admins/owners can edit these via **Validation** action in the board UI.

### Firestore rules + emulator tests

Added artifacts:

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json` (emulator config, Firestore port `8085`)
- `test/firestore/firestore_rules_test.js`
- `package.json` scripts for rules tests

Run:

```bash
npm install
npm run test:rules
flutter test
```

## Phase 4 UX foundation + navigation

Phase 4 introduces a route-based primary shell:

- `/workspace` -> board execution workspace
- `/board-configuration` -> board scope/settings/members/columns/validation/workflow
- `/planning` -> planning entry point and planning-view selection

This keeps `UI -> State -> Domain -> Repository -> Data Sources` intact while improving discoverability of common actions.

## Phase 7 cloud/backend ops baseline

Operational docs:

- Environment matrix: `docs/ops/environment-matrix.md`
- Backend runbook: `docs/ops/runbook.md`

Common commands:

```bash
npm run test:rules
npm run emulators:firestore
FIREBASE_PROJECT=plandone-dev npm run deploy:firestore
flutter analyze
flutter test
```

## Firebase Auth setup (Phase 1)

1. Create Firebase project and register Flutter app targets.
2. Add Firebase config files for each platform.
3. Enable auth providers in Firebase Console:
   - Email/Password
   - Google
4. Add/generated Firebase options initialization if required by your environment.
5. Run with auth enabled:

```bash
flutter run --dart-define=USE_FIREBASE_AUTH=true
```

> Note: If Firebase is not configured, keep `USE_FIREBASE_AUTH=false` (default) to use local in-memory auth for development.

## Next steps

1. Replace in-memory data sources with Drift local DB.
2. Add outbox persistence and retry metadata.
3. Add Firebase Auth + Firestore adapters.
4. Add sync engine with idempotent operation processing.
5. Add role-aware board membership and security-rule-aligned behavior.
