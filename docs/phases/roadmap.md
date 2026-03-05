# PlanDone Delivery Roadmap (Usability-First Revision)

## 1) Project evaluation summary

Based on docs + current implementation, PlanDone has a strong technical base and should now prioritize **day-to-day usability, product structure, and operational reliability** before AI expansion.

### What is already solid

- Layered architecture is consistent (`UI -> State -> Domain -> Repository -> Data Sources`).
- Local-first/offline-first flow exists and is mostly stable:
  - local write first
  - outbox queue
  - sync engine
  - Firestore hydration listeners
- Collaboration + role permissions are implemented across app + rules.
- Board/item interactions are rich for a starter (drag/move/filter/hierarchy context).

### Biggest gaps against the product vision

- The UX is still effectively single-page and modal-heavy for frequent use.
- No dedicated board-configuration experience despite growing complexity.
- Workflow logic still relies on column names in places (e.g., done semantics), not formal workflow states.
- Planning views (hierarchy/backlog/focus/history) are not first-class multi-view pages.
- Cloud backend setup exists, but environment/ops maturity for reliable daily use is still limited.

## 2) Guiding constraints (non-negotiables)

1. Offline-first remains primary.
2. Local DB remains source of truth for UI.
3. Four-level hierarchy remains flexible (Goal/Project/Task/Action).
4. Sync path remains: local -> outbox -> Firestore -> listener hydrate -> local.
5. No architecture redesign unless explicitly requested.
6. Avoid enterprise-heavy complexity that harms usability.

## 3) Revised phase structure

- **Phase 1:** Foundation Completion (auth + stable local baseline)
- **Phase 2:** Sync & Realtime Completion (outbox + Firestore + hydration)
- **Phase 3:** Collaboration & Permissions (roles, invites, rules)
- **Phase 4:** UX Foundation & Navigation Refactor
- **Phase 5:** Workflow Semantics & Designated Columns
- **Phase 6:** Planning Views & Hierarchy Management
- **Phase 7:** Cloud Backend Infrastructure Baseline
- **Phase 8:** Reliability, Security & Daily-Use Polish
- **Phase 9 (Deferred):** AI Breakdown + Advanced Automation
- **Phase 10:** Quick Capture Inbox
- **Phase 11:** Saved Filter Presets
- **Phase 12:** Item Activity History
- **Phase 13:** Undo Safety Stack
- **Phase 14:** Card Density & Readability
- **Phase 15:** Item Details & Metadata System
- **Phase 16:** Hierarchy Visual Clarity
- **Phase 17:** Notifications & Alert Preferences
- **Phase 18:** Recurring Tasks & Cycle Rules
- **Phase 19:** Smart Autofill & Predictive Defaults (Non-AI)

## 4) Recommended execution sequence

1. Lock Phase 1–3 acceptance outcomes.
2. Execute Phase 4 to establish multi-page structure and discoverability.
3. Execute Phase 5 to formalize workflow states and configurable designated columns.
4. Execute Phase 6 to ship practical planning views.
5. Execute Phase 7 for cloud environment hardening (dev/staging/prod posture).
6. Execute Phase 8 for reliability/security/performance polish.
7. Execute Phase 10 for fast daily capture flow.
8. Execute Phase 11 for reusable planning filter presets.
9. Execute Phase 12 for traceability via item activity history.
10. Execute Phase 13 for reversible high-impact actions.
11. Execute Phase 14 for card readability and denser planning surfaces.
12. Execute Phase 15 for details-first workflow and richer metadata.
13. Execute Phase 16 for hierarchy color/parent clarity improvements.
14. Execute Phase 17 for notifications and alert preferences.
15. Execute Phase 18 for recurring task lifecycle automation.
16. Execute Phase 19 for deterministic smart autofill defaults.
17. Execute deferred Phase 9 once usability/reliability baseline through Phase 19 is proven.

## 5) Go/no-go gates between phases

- **Gate to Phase 4:** Collaboration model secure and permission-consistent.
- **Gate to Phase 5:** Navigation and dedicated config surfaces are stable.
- **Gate to Phase 6:** Workflow semantics are decoupled from raw column names.
- **Gate to Phase 7:** Product flow stable enough to harden cloud operations.
- **Gate to Phase 8:** Cloud baseline and observability foundations in place.
- **Gate to Phase 10:** Daily-use UX and reliability targets are met.
- **Gate to Phase 11:** Quick capture flow is stable and discoverable.
- **Gate to Phase 12:** Filter presets are stable across views.
- **Gate to Phase 13:** Activity history baseline is available for traceability.
- **Gate to Phase 14:** Undo safety is stable for high-impact actions.
- **Gate to Phase 15:** Card readability baseline is validated on target devices.
- **Gate to Phase 16:** Metadata model and details-view behavior are stable.
- **Gate to Phase 17:** Hierarchy visual cues are clear and accessible.
- **Gate to Phase 18:** Notification preference model is stable.
- **Gate to Phase 19:** Recurrence behavior is deterministic and idempotent.
- **Gate to Phase 9 (Deferred):** Usability enhancements through Phase 19 are stable.

## 6) Supporting files

- `phase-1-foundation.md`
- `phase-2-sync-realtime.md`
- `phase-3-collaboration-permissions.md`
- `phase-4-ux-navigation.md`
- `phase-5-workflow-columns.md`
- `phase-6-planning-views.md`
- `phase-7-cloud-backend-baseline.md`
- `phase-8-reliability-security-polish.md`
- `phase-9-ai-advanced.md`
- `phase-10-quick-capture-inbox.md`
- `phase-11-saved-filter-presets.md`
- `phase-12-item-activity-history.md`
- `phase-13-undo-safety-stack.md`
- `phase-14-card-density-readability.md`
- `phase-15-item-details-metadata.md`
- `phase-16-hierarchy-visual-clarity.md`
- `phase-17-notifications-preferences.md`
- `phase-18-recurring-tasks.md`
- `phase-19-smart-autofill-defaults.md`
- `progress-checklist.md`
- `../prompts/phase-1-cline-prompt.md`
- `../prompts/phase-2-cline-prompt.md`
- `../prompts/phase-3-cline-prompt.md`
- `../prompts/phase-4-cline-prompt.md`
- `../prompts/phase-5-cline-prompt.md`
- `../prompts/phase-6-cline-prompt.md`
- `../prompts/phase-7-cline-prompt.md`
- `../prompts/phase-8-cline-prompt.md`
- `../prompts/phase-9-cline-prompt.md`
- `../prompts/phase-10-cline-prompt.md`
- `../prompts/phase-11-cline-prompt.md`
- `../prompts/phase-12-cline-prompt.md`
- `../prompts/phase-13-cline-prompt.md`
- `../prompts/phase-14-cline-prompt.md`
- `../prompts/phase-15-cline-prompt.md`
- `../prompts/phase-16-cline-prompt.md`
- `../prompts/phase-17-cline-prompt.md`
- `../prompts/phase-18-cline-prompt.md`
- `../prompts/phase-19-cline-prompt.md`
