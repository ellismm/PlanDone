# Cline Prompt — Phase 8 (Reliability + Security + Daily-Use Polish)

Implement **Phase 8** for PlanDone, aligned to the revised roadmap.

## Objective

Harden PlanDone for consistent everyday usage with stronger reliability, security confidence, and UX polish under real workloads.

## Non-negotiables

1. Keep local-first/offline-first guarantees.
2. Preserve security-rule enforcement and role consistency.
3. Prioritize high-impact reliability fixes over cosmetic-only changes.
4. Avoid introducing workflow complexity that harms usability.

## Scope to implement now

1. Reliability pass:
   - offline/online transition behavior
   - retry/failure UX and recoverability
   - destructive-action safeguards
2. Security pass:
   - expand denied-path tests
   - verify least-privilege assumptions
3. UX polish pass:
   - empty/loading/error state consistency
   - action clarity and visual hierarchy
4. Performance pass for larger boards and deep hierarchies.
5. Update docs and readiness checklist.

## Constraints

- No broad new feature scope unrelated to reliability/security/polish.
- Keep changes measurable with clear before/after validation.
- Ensure regression coverage for critical board flows.

## Required output from you

1. Brief implementation plan.
2. Reliability/security test matrix summary.
3. Code + tests + docs.
4. Performance findings and limits.
5. Phase-8 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Common failure scenarios are understandable and recoverable.
- Security denied-path tests are comprehensive and passing.
- Performance is acceptable for representative large boards.
- UX polish improves confidence for daily use.

## Validation commands

- `npm run test:rules`
- `flutter test`
- (optional) targeted performance test commands
