# Phase 14 — Card Density & Readability

## Objective

Improve daily scanability by making column/item titles easier to read while
reducing card crowding, especially on mobile.

## Implemented

1. Added card density controls:
   - `BoardCardDensity` (`comfortable`, `compact`) state in UI layer.
   - density selector in workspace top actions (compact and expanded app bars).
2. Improved title visibility:
   - column titles now support larger readable wrapping budget and tooltip.
   - item titles retain multi-line display and now expose full-title tooltip.
3. Reduced non-essential card chrome in compact mode:
   - parent context shown as subtle `Parent` link instead of full parent title row.
   - tightened vertical spacing/padding while preserving tap targets.
4. Improved item-per-screen density:
   - compact mode narrows kanban column width and card padding for higher content
     density.

## Readability and Density Summary

- Comfortable mode keeps richer context visible on card.
- Compact mode prioritizes scanning speed and list density.
- Secondary context is still available through item details and parent jump.

## Tradeoffs (Density vs Touch Comfort)

- Compact mode increases visible context by reducing whitespace and some inline
  metadata.
- To avoid harming usability, primary action tap targets remain at least 36x36
  for compact mode controls.
- Full parent title is moved off-card in compact mode to reduce visual clutter.

## Tests Added

- `test/features/board/presentation/board_item_tile_density_test.dart`
  - comfortable mode keeps richer parent metadata row.
  - compact mode reduces parent chrome and keeps long-title tooltip support.

## Acceptance Criteria Check

- [x] Titles are more readable with less truncation pain.
- [x] Users can switch density to view more plan context.
- [x] Core card interactions remain intact on mobile-safe targets.
- [x] Tests/docs updated for Phase 14 scope.
