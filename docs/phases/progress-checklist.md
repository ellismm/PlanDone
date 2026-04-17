# PlanDone Multi-Phase Progress Checklist

Use this file as your execution tracker while prompting Cline phase-by-phase.

---

## Per-Phase Deployment Gate

- [ ] `flutter test` passes for the phase changes
- [ ] App builds successfully for Android (`flutter build apk --debug`)
- [ ] Latest code is deployed to physical device (`flutter run -d <physical_device_id>`)
- [ ] Manual smoke-check of the phase flow on device completed

---

## Phase 1 — Foundation Completion

- [ ] Firebase config and packages added for target platforms
- [ ] Email/password auth implemented
- [ ] Google auth implemented
- [ ] Auth state bootstrapping + route guard implemented
- [ ] Drift local store set as default runtime path
- [ ] User-scoped board context wired through providers/repositories
- [ ] Offline board/item CRUD validated post-auth
- [ ] Tests added/updated for auth and local behavior
- [ ] Docs updated (setup + architecture boundaries)
- [ ] Phase 1 acceptance criteria confirmed

## Phase 2 — Sync & Realtime Completion

- [ ] Firestore-backed sync adapter implemented
- [ ] Outbox payload contracts hardened/documented
- [ ] Idempotent apply behavior validated
- [ ] Retry metadata/backoff behavior verified
- [ ] Reconnect sync behavior validated
- [ ] Firestore listeners hydrate local Drift DB
- [ ] LWW conflict behavior documented and implemented
- [ ] Tests added for success/failure/retry/realtime paths
- [ ] Sync troubleshooting docs updated
- [ ] Phase 2 acceptance criteria confirmed

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

## Phase 9 — AI + Advanced Automation (Deferred)

- [ ] AI adapter/service abstraction added
- [ ] AI prompt -> structured hierarchy parser implemented
- [ ] Draft/review/edit/approve flow implemented
- [ ] Approved AI items inserted through local-first pipeline
- [ ] AI safety/validation guardrails verified
- [ ] Tests/docs updated for AI workflows
- [ ] Phase 9 acceptance criteria confirmed

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

- [ ] End-to-end manual QA across offline/online transitions
- [x] Security/rules test pass recorded
- [x] `flutter test` clean pass
- [x] Key docs reviewed and consistent
- [x] Known limitations/backlog documented

Supporting docs:

- [personal-mvp-closeout.md](/home/messay/coding/own/PlanDone/docs/phases/personal-mvp-closeout.md)
- [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md)
- [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md)
- [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md)
