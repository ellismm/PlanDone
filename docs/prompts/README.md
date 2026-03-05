# PlanDone Phase Execution Prompts

These prompts are designed for sequential execution with Cline.

## Suggested order

1. `phase-1-cline-prompt.md`
2. `phase-2-cline-prompt.md`
3. `phase-3-cline-prompt.md`
4. `phase-4-cline-prompt.md`
5. `phase-5-cline-prompt.md`
6. `phase-6-cline-prompt.md`
7. `phase-7-cline-prompt.md`
8. `phase-8-cline-prompt.md`
9. `phase-9-cline-prompt.md` (still deferred)
10. `phase-10-cline-prompt.md`
11. `phase-11-cline-prompt.md`
12. `phase-12-cline-prompt.md`
13. `phase-13-cline-prompt.md`
14. `phase-14-cline-prompt.md`
15. `phase-15-cline-prompt.md`
16. `phase-16-cline-prompt.md`
17. `phase-17-cline-prompt.md`
18. `phase-18-cline-prompt.md`
19. `phase-19-cline-prompt.md`

## Usage notes

- Run one phase at a time.
- Do not start the next phase until acceptance criteria for the current phase are complete.
- For every completed phase, run validation + deployment before proceeding:
  - `flutter test`
  - `flutter build apk --debug`
  - `flutter run -d <physical_device_id>`
- Keep architecture direction fixed: `UI -> State -> Domain -> Repository -> Data Sources`.
- Keep local DB as source of truth.
- Keep AI work deferred until the usability-first phases are completed.
