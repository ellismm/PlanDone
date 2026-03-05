# Phase 16 — Hierarchy Visual Clarity

## Why this phase exists

Hierarchy planning is powerful but currently visually heavy. This phase makes parent/child relationships clearer while keeping screens denser and easier to scan.

## Scope

### In scope

- Optional color grouping for items under the same top-level goal.
- User-selectable or auto-assigned non-conflicting group colors.
- More subtle parent-path display on cards.
- Ability to hide parent path on cards and inspect full hierarchy in details.
- Improved hierarchy view spacing to show more plan context per screen.

### Out of scope

- Full redesign of hierarchy semantics or data model.
- Advanced dependency graph visualization.

## Key implementation targets

1. Add hierarchy color policy (auto/random non-conflicting + manual override).
2. Apply consistent color cues across hierarchy-aware views.
3. Make parent context display configurable (shown/subtle/hidden on card).
4. Tune hierarchy row density and indentation for readability at scale.
5. Add tests for color assignment stability and parent-display preferences.

## Risks and mitigations

- **Risk:** color overuse harms accessibility.  
  **Mitigation:** restrained palette + text contrast checks.
- **Risk:** hidden parent context causes confusion.  
  **Mitigation:** clear details-view fallback and optional breadcrumbs.

## Acceptance criteria

- Hierarchy relationships are easier to understand at a glance.
- More items are visible per screen in hierarchy planning views.
- Parent context can be hidden on cards without losing access in details.
- Tests/docs are updated and coherent.

## Exit artifacts

- Hierarchy visual rules and color behavior guide.
- Updated hierarchy view documentation.
- Phase completion summary.

## Implementation Summary

- Added hierarchy visual settings in `BoardValidationSettings`:
  - `hierarchyColorGroupingByGoal`
  - `hierarchyParentPathMode` (`visible | subtle | hidden`)
  - `hierarchyGoalColorOverrides` (`goalId -> color`)
- Added deterministic hierarchy visual resolver:
  - top-level goal resolution per item
  - stable auto color assignment with non-conflicting palette selection
  - manual override support for per-goal colors
- Applied hierarchy-only color accents:
  - branch guide lines tinted by top-level goal color
  - subtle left-border/background accents on hierarchy cards
- Added parent-path visibility preference support on cards:
  - `visible`: explicit parent label
  - `subtle`: toned-down parent path text
  - `hidden`: no parent path text on cards
- Improved hierarchy density:
  - tighter guide indentation
  - reduced hierarchy row spacing for more on-screen context
- Ensured full hierarchy context remains available in item details:
  - added full path display (`Root > ... > Current`)
- Added board configuration controls for hierarchy visuals:
  - toggle goal color grouping
  - parent-path display mode selector
  - manual per-goal color override dropdowns
- Added tests for color stability, overrides, and preference serialization.
