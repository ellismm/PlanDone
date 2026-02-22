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

## Next steps

1. Replace in-memory data sources with Drift local DB.
2. Add outbox persistence and retry metadata.
3. Add Firebase Auth + Firestore adapters.
4. Add sync engine with idempotent operation processing.
5. Add role-aware board membership and security-rule-aligned behavior.
