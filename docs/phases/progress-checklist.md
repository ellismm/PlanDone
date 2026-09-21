# PlanDone Multi-Phase Progress Checklist

Use this file as the implementation and release-readiness tracker. Completed
phase items describe shipped code and automated coverage; the separate final
release gate records device-only validation that must not be inferred from
unit or widget tests.

---

## Per-Phase Deployment Gate

- [x] `flutter test` passes for the phase changes
- [x] App builds successfully for Android
- [x] Latest application build is deployed to a physical device (Firebase App Distribution build 15)
- [x] Manual smoke-check of the phase flow on device completed

---

## Phase 1 — Foundation Completion

- [x] Firebase config and packages added for target platforms
- [x] Email/password auth implemented
- [x] Google auth implemented
- [x] Auth state bootstrapping + route guard implemented
- [x] Drift local store set as default runtime path
- [x] User-scoped board context wired through providers/repositories
- [x] Offline board/item CRUD implemented and covered post-auth
- [x] Tests added/updated for auth and local behavior
- [x] Docs updated (setup + architecture boundaries)
- [x] Phase 1 acceptance criteria confirmed

## Phase 2 — Sync & Realtime Completion

- [x] Firestore-backed sync adapter implemented
- [x] Outbox payload contracts hardened/documented
- [x] Idempotent apply behavior validated
- [x] Retry metadata/backoff behavior verified
- [x] Reconnect sync behavior validated
- [x] Firestore listeners hydrate local Drift DB
- [x] LWW conflict behavior documented and implemented
- [x] Tests added for success/failure/retry/realtime paths
- [x] Sync troubleshooting docs updated
- [x] Phase 2 acceptance criteria confirmed

## Phase 3 — Collaboration & Permissions

- [x] Member invite/join/manage flows implemented
- [x] Role enforcement in UI/state/repository layers
- [x] Firestore rules created/updated
- [x] Firestore indexes created/updated
- [x] Rules tests added (emulator preferred)
- [x] Board-level validation rule config implemented
- [x] Multi-user collaboration validation completed
- [x] Docs updated with permission matrix + setup steps
- [x] Phase 3 acceptance criteria confirmed

## Phase 4 — UX Foundation & Navigation Refactor

- [x] Route-based app shell/navigation model implemented
- [x] Dedicated board workspace page boundaries established
- [x] Dedicated board configuration page implemented
- [x] Board-page monolith split into smaller units
- [x] Navigation tests and docs updated
- [x] Phase 4 acceptance criteria confirmed

## Phase 5 — Workflow Semantics & Designated Columns

- [x] Column semantic model added (state/kind behavior)
- [x] Designated starter workflow template(s) implemented
- [x] Name-based done logic removed in favor of semantics
- [x] Board-level workflow configuration implemented
- [x] Migration strategy for existing boards completed
- [x] Tests/docs updated for workflow semantics
- [x] Phase 5 acceptance criteria confirmed

## Phase 6 — Planning Views & Hierarchy Management

- [x] Multi-view board workspace implemented (kanban/hierarchy/backlog/focus)
- [x] Shared filters/query logic reused across views
- [x] Hierarchy operations improved (re-parent/bulk actions)
- [x] View-switching UX validated for continuity
- [x] Tests/docs updated for planning views
- [x] Phase 6 acceptance criteria confirmed

## Phase 7 — Cloud Backend Infrastructure Baseline

- [x] Environment strategy documented (dev/staging/prod)
- [x] Firebase config standards per environment documented
- [x] CI path for rules/tests/lint configured
- [x] Emulator + deployment workflows documented
- [x] Cloud ownership/user-required setup actions documented
- [x] Phase 7 acceptance criteria confirmed

## Phase 8 — Reliability, Security & Daily-Use Polish

- [x] Reliability test matrix executed (offline/online/retry/conflict)
- [x] Security denied-path tests expanded and passing
- [x] Failure/recovery UX improvements completed
- [x] Performance pass completed for larger boards
- [x] Daily-use readiness checklist completed
- [x] Phase 8 acceptance criteria confirmed

## Phase 9 — AI + Advanced Automation

- [x] AI adapter/service abstraction added
- [x] AI prompt -> structured hierarchy parser implemented
- [x] Draft/review/edit/approve flow implemented
- [x] Approved AI items inserted through local-first pipeline
- [x] AI safety/validation guardrails verified
- [x] Tests/docs updated for AI workflows
- [x] Firebase AI Logic + App Check activated and live generation smoke-tested
- [x] Phase 9 acceptance criteria confirmed

## Phase 10 — Quick Capture Inbox

- [x] Global quick-capture entry point implemented
- [x] Inbox triage flow (assign type/board/column/parent) implemented
- [x] Offline capture behavior validated
- [x] Tests/docs updated
- [x] Phase 10 acceptance criteria confirmed

## Phase 11 — Saved Filter Presets

- [x] Save/apply/update/delete filter presets implemented
- [x] Presets work across supported workspace views
- [x] User-scoped persistence validated
- [x] Tests/docs updated
- [x] Phase 11 acceptance criteria confirmed

## Phase 12 — Item Activity History

- [x] Activity event model defined and stored locally
- [x] Readable timeline UI in item details implemented
- [x] High-value actions emit history events
- [x] Tests/docs updated
- [x] Phase 12 acceptance criteria confirmed

## Phase 13 — Undo Safety Stack

- [x] Reversible operation model defined for high-impact actions
- [x] Undo UX implemented with sensible timeout/limits
- [x] Data integrity validated for undo paths
- [x] Tests/docs updated
- [x] Phase 13 acceptance criteria confirmed

## Phase 14 — Card Density & Readability

- [x] Card density options implemented (compact/comfortable baseline)
- [x] Title truncation/readability improved in key views
- [x] Secondary card chrome reduced or relocated
- [x] Widget/docs updates completed
- [x] Phase 14 acceptance criteria confirmed

## Phase 15 — Item Details & Metadata System

- [x] Read-first item details view implemented
- [x] Expanded metadata fields persisted and rendered
- [x] Metadata visibility/required settings implemented
- [x] Auto-managed lifecycle dates validated
- [x] Tests/docs updated
- [x] Phase 15 acceptance criteria confirmed

## Phase 16 — Hierarchy Visual Clarity

- [x] Hierarchy color grouping behavior implemented
- [x] Parent-path display preferences implemented
- [x] Hierarchy density improved for more visible context
- [x] Accessibility and contrast checks completed
- [x] Tests/docs updated
- [x] Phase 16 acceptance criteria confirmed

## Phase 17 — Notifications & Alert Preferences

- [x] Notification preferences model + UI implemented
- [x] Due/start reminder scheduling implemented
- [x] Snooze/mute behavior implemented where applicable
- [x] Offline/online rescheduling behavior validated
- [x] Tests/docs updated
- [x] Phase 17 acceptance criteria confirmed

## Phase 18 — Recurring Tasks & Cycle Rules

- [x] Recurrence settings + model implemented
- [x] Completion-gated recurrence behavior implemented
- [x] Duplicate prevention across sync/retry validated
- [x] Recurrence controls integrated into item details
- [x] Tests/docs updated
- [x] Phase 18 acceptance criteria confirmed

## Phase 19 — Smart Autofill & Predictive Defaults (Non-AI)

- [x] Deterministic suggestion engine implemented
- [x] Autofill hints integrated into create/edit/triage flows
- [x] User controls for suggestion behavior implemented
- [x] Local settings persistence for suggestion behavior added
- [x] Tests/docs updated
- [x] Phase 19 acceptance criteria confirmed

## Final Release Readiness

- [x] End-to-end manual QA across offline/online transitions
- [x] Security/rules test pass recorded
- [x] `flutter test` clean pass
- [x] Key docs reviewed and reconciled with build 15
- [x] Known limitations/backlog documented

Supporting docs:

- [personal-mvp-closeout.md](/home/messay/coding/own/PlanDone/docs/phases/personal-mvp-closeout.md)
- [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md)
- [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md)
- [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md)
