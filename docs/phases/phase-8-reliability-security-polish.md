# Phase 8 — Reliability, Security & Daily-Use Polish

## Why this phase exists

After navigation, workflow semantics, planning views, and cloud baseline improvements, PlanDone should be hardened for consistent everyday use: predictable behavior, safe operations, and polished UX under real workloads.

## Scope

### In scope

- Reliability hardening:
  - sync edge-case handling
  - retry/failure UX improvements
  - safer destructive actions and recovery affordances
- Security hardening:
  - rule coverage expansion
  - denied-path regression tests
  - least-privilege verification
- Product polish:
  - visual clarity and action hierarchy
  - desktop/web ergonomics (if applicable)
  - empty/loading/error state consistency
- Performance pass for larger boards and dense hierarchies.

### Out of scope

- New major product surfaces not tied to reliability/polish.
- AI automation feature set (Phase 9).

## Key implementation targets

1. Add reliability test matrix for offline/online transitions and conflict edges.
2. Expand security negative tests and rules confidence checks.
3. Improve user-facing failure explanations and remediation hints.
4. Benchmark and optimize large-board interactions.
5. Finalize “daily-use readiness” definition and validation checklist.

## Risks and mitigations

- **Risk:** polish work becomes unbounded and delays delivery.  
  **Mitigation:** prioritize by severity/impact and enforce a fixed readiness rubric.
- **Risk:** reliability fixes regress existing flows.  
  **Mitigation:** lock baseline regression tests before refactoring sensitive paths.

## Acceptance criteria

- Common sync and permission failures are understandable and recoverable.
- Security tests cover critical denied-action scenarios.
- Performance remains acceptable on representative large datasets.
- UX polish materially improves daily interaction confidence.

## Exit artifacts

- Reliability/security test report.
- Performance notes and known limits.
- Phase-8 checklist completion summary.

---

## Phase-8 implementation summary (current status)

### 1) Brief implementation plan

1. Improve sync recoverability UX and automatic sync re-entry points.
2. Add destructive-action confirmations for high-impact operations.
3. Expand Firestore denied-path tests for least-privilege rules.
4. Add targeted large-fixture performance tests and apply low-risk view optimization.
5. Update docs/checklists with measured validation and limits.

### 2) Reliability/security test matrix summary

| Area | Scenario | Coverage |
| --- | --- | --- |
| Reliability | Manual sync, queued retries, sync status reporting | `board_controller_sync_test.dart` + workspace sync banner/outbox sheet |
| Reliability | Auto sync after resume / new pending ops | `_WorkspaceSyncLifecycleBridge` in workspace |
| Reliability | Destructive-action guardrails | Confirmation prompts for bulk archive/unarchive and member removal |
| Security | Admin cannot delete board | `firestore_rules_test.js` |
| Security | Non-member cannot write `_appliedOps` | `firestore_rules_test.js` |
| Security | Pending invite cannot self-escalate role | `firestore_rules_test.js` |
| Security | Member cannot manage columns | `firestore_rules_test.js` |

### 3) Code + tests + docs changes

- Reliability/UX:
  - `lib/src/features/board/presentation/board_controller.dart`
    - added `SyncUiState`, `outboxStatusProvider`, sync status transitions
  - `lib/src/features/board/presentation/board_page.dart`
    - sync status banner + retry affordance
    - richer outbox sheet (attempts/retry/error + retry action)
    - lifecycle auto-sync bridge for resume/pending changes
    - destructive confirmations for bulk archive/unarchive and member removal
    - reduced repeated per-column filtering work in Kanban rendering
  - `lib/src/features/board/presentation/board_configuration_page.dart`
    - destructive confirmation for member removal
- Tests:
  - `test/features/board/presentation/board_controller_sync_test.dart`
  - `test/firestore/firestore_rules_test.js` (expanded denied-path coverage)
  - `test/features/board/data/repositories/board_repository_performance_test.dart`
- Docs:
  - this phase summary
  - `docs/phases/progress-checklist.md` Phase 8 completion marks

### 4) Performance findings and limits

- Added targeted in-memory large-fixture checks:
  - bulk update on 700 generated items
  - deep hierarchy re-parent on 350-node chain
- Workspace Kanban now computes filtered column item lists once per render pass instead of recomputing the same filter/sort per column section.
- Limits:
  - current performance validation is local in-memory fixture based; device/network-specific runtime profiling is still recommended before broad rollout.

### 5) Phase-8 acceptance checklist results

- [x] Common failure scenarios are understandable and recoverable.
- [x] Security denied-path tests are expanded and passing.
- [x] Performance is acceptable for representative large board fixtures.
- [x] UX polish improves daily-use confidence (status clarity, safeguards, error visibility).
