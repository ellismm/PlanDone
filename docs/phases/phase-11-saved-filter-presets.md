# Phase 11 — Saved Filter Presets

## Why this phase exists

Power users repeatedly apply the same filters. Presets reduce repetitive setup and improve daily planning speed.

## Scope

### In scope

- Save current filter/search/scope as named preset.
- Apply, update, rename, and delete presets.
- User-scoped persistence for presets.
- Support across core planning/workspace views where filter parity exists.

### Out of scope

- Team-shared/global presets.
- Complex query builder DSL.

## Key implementation targets

1. Define a canonical preset model aligned with existing filter providers.
2. Add CRUD for presets in settings or filter UI surface.
3. Apply presets safely across view switches.
4. Add migration/default handling for older sessions.
5. Add tests for persistence and application correctness.

## Risks and mitigations

- **Risk:** preset drift as filters evolve.  
  **Mitigation:** version preset payloads and safe fallback behavior.
- **Risk:** confusing preset UX.  
  **Mitigation:** keep actions minimal and clearly labeled.

## Acceptance criteria

- Users can save and reuse filter presets quickly.
- Presets persist correctly per user.
- Applying presets updates the expected filter context.
- Tests/docs are updated and coherent.

## Exit artifacts

- Preset behavior reference doc.
- Tests covering preset lifecycle.
- Phase completion summary.

## Implemented IA notes

- Workspace filter controls now include `Filter presets`.
- Preset sheet supports save/apply/update/rename/delete.
- Presets restore canonical filter/query context (type/state/tag/text/scope/date toggles/view).
- Presets are user-scoped and stored locally with graceful fallback defaults.
