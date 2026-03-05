# Phase 12 — Item Activity History

## Why this phase exists

Daily planning confidence improves when users can see what changed, when, and by whom (when available) without digging through sync internals.

## Scope

### In scope

- Activity event model for major work-item actions.
- Local timeline view in item details.
- Event coverage for high-value actions:
  - create/update
  - move/reparent
  - archive/unarchive
  - complete/reopen
- Offline-safe event recording.

### Out of scope

- Full enterprise audit/compliance module.
- External analytics platform integration.

## Key implementation targets

1. Define activity event schema with stable event types.
2. Persist activity locally with bounded retention policy.
3. Render readable timeline in item details surface.
4. Ensure critical mutations emit events consistently.
5. Add tests for event emission ordering and rendering.

## Risks and mitigations

- **Risk:** activity spam/noise.  
  **Mitigation:** scope to high-value events + concise labels.
- **Risk:** storage growth.  
  **Mitigation:** retention limits and efficient indexing.

## Acceptance criteria

- Users can inspect meaningful item history.
- High-value actions generate consistent timeline events.
- History remains available offline.
- Tests/docs are updated and coherent.

## Exit artifacts

- Activity model + timeline docs.
- Event emission tests.
- Phase completion summary.

## Implemented IA notes

- Added canonical `WorkItemActivityEvent` model with stable event types.
- Activity events persist locally with bounded per-item retention.
- Item details surface now includes readable `Activity` timeline.
- High-value item mutations emit events: create/update/move/re-parent/archive/complete/reopen.
