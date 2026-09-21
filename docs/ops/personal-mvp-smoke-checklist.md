# Personal MVP Smoke Checklist

Use this checklist before calling a build ready for daily personal use.

## Sign-in and boot

- [x] App launches on physical Android device.
- [x] Firebase sign-in succeeds.
- [x] Existing board data loads after sign-in.
- [x] App relaunch restores the prior board context.

## Core item workflow

- [x] Create a new item from Workspace.
- [x] Edit title/description/metadata and save.
- [x] Move an item between columns.
- [x] Archive and unarchive an item.
- [ ] Use undo after a move or archive action.
- [x] Open item details without entering edit mode.

## Quick capture and inbox triage

- [x] Add a quick-capture item from Workspace.
- [x] Open Inbox view and confirm the capture appears.
- [x] Triage the capture into board, column, type, and optional parent.
- [x] Confirm the triaged item leaves inbox state and appears in the correct workspace view.

## Reminders

- [x] Create or edit an item with a start or due date near the present.
- [x] Confirm the reminder appears in the reminder center/banner when eligible.
- [x] Snooze the reminder and confirm it is suppressed until expiry.
- [x] Mute reminders temporarily and confirm alerts are suppressed.
- [x] Background or close the Android app and verify the local scheduled notification still fires.

## Recurrence

- [x] Create a recurring task or action.
- [x] Set cadence and late-completion policy.
- [x] Complete the item and confirm exactly one next instance is generated.
- [x] Verify the generated instance lands in the expected board/column.
- [x] Confirm repeated reopen/sync does not generate duplicates.

## Offline and sync recovery

- [x] Disable network.
- [ ] Create, edit, move, and archive at least one item while offline.
- [x] Re-enable network.
- [x] Trigger sync if needed.
- [x] Confirm offline edits persist and reconcile cleanly.

## Backup and restore

- [x] Open `Board Configuration -> Backup & Restore`.
- [x] Export the current board snapshot.
- [x] Confirm the JSON backup appears in the backup list.
- [x] Restore the backup.
- [x] Confirm the restored board appears as a new board with hierarchy, metadata, and recurrence intact.

## Final release decision

- [x] `flutter analyze` passed on 2026-08-30 with no issues.
- [x] `flutter test --concurrency=1` passed on 2026-08-30 (264 passed,
  11 platform skips).
- [x] `npm run test:rules` passed on 2026-08-30 (29 passed), including
  owner-role escalation, account cleanup, membership discovery, and owner-only
  board deletion regression coverage.
- [x] Firebase-profile `flutter build apk --release` passed on 2026-08-30.
- [ ] Manual smoke completed without blocking issues.
- [x] Any remaining issues are documented in [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md).

## Validation log

### 2026-08-30 — Tester build 0.1.0 (14)

- A clean Android release APK was built with application ID
  `com.example.plandone`, version name `0.1.0`, and version code `14`.
- Static analysis passed with no issues, the full serialized Flutter suite
  passed with 264 tests and 11 expected platform skips, and all 29 Firestore
  emulator rules tests passed.
- Firebase App Distribution accepted the release and distributed it to the
  requested staging tester, `leveled.dev@gmail.com`.
- The released APK SHA-256 is
  `30639d524c55efaf3e6c92785d2ab2fed0feec0e2c94c46236fd85866c91d48a`.

### 2026-08-29 — Firebase development-tooling security closeout

- Firebase CLI was upgraded from 13.35.1 to 15.28.2, the rules harness from
  3.0.4 to 5.0.2, and the test-only Firebase JavaScript SDK to 12.18.0.
- Backend development now explicitly requires Node.js 22+ and Java 21+; neither
  runtime is shipped in or required by the Android application.
- A clean `npm ci` succeeded. `npm audit --audit-level=high` reports no high or
  critical vulnerabilities; five moderate advisories remain in transitive
  packages pinned by the current Firebase CLI and cannot be safely overridden.
- Firestore emulator 1.22.0 started successfully and all 29 rules tests passed.
  Static analysis, the full 264-test serialized Flutter suite, and the
  Firebase-profile Android release build also passed.

### 2026-08-29 — Android backup and local-data privacy closeout

- Android OS backup is explicitly disabled, with defense-in-depth resource
  exclusions for legacy Auto Backup and Android 12+ cloud/device-transfer
  extraction.
- The rules exclude the live Drift database and WAL files, app settings,
  authentication and secure preferences, app-private files, and app-managed
  JSON snapshots from automatic transfer.
- The boot receiver is non-exported and remains eligible for its protected
  system broadcasts.
- The manual JSON export/import feature remains available. Privacy-source
  tests, backup round-trip tests, the full 264-test serialized Flutter suite,
  static analysis, packaged-manifest/resource inspection, and the
  Firebase-profile Android release build passed.

### 2026-08-29 — Hierarchy expansion persistence

- Entering Hierarchy no longer clears the current expanded/collapsed branch
  state.
- Collapse state is stored locally per signed-in user using board-qualified
  item IDs, so every board restores its own tree without syncing personal view
  state to collaborators.
- Expand/collapse controls update immediately and retry persistence on the next
  action if local preference storage is temporarily unavailable.
- Regression coverage verifies the state survives both view switching and a
  complete workspace restart. The full 260-test serialized Flutter suite,
  static analysis, and the Firebase-profile Android release build passed.

### 2026-08-29 — AI draft reordering closeout

- AI draft cards now expose explicit up/down controls for ordering sibling
  items. Root goals reorder among roots, while children remain constrained to
  their current parent.
- Moving an item moves its complete visible branch, preserves parent links, and
  keeps the reviewed sibling order when approved items enter the local-first
  repository and outbox.
- The generation controls now stack responsively on phone-sized screens,
  eliminating the narrow-layout overflow found during widget validation.
- Ordering domain tests, phone-sized review/approval coverage, the full
  258-test serialized Flutter suite, static analysis, and the Firebase-profile
  Android release build passed.
- Tester build `0.1.0 (13)` was distributed to the existing staging App
  Distribution tester on 2026-08-29.

### 2026-08-29 — Account deletion closeout

- Account deletion now verifies a recent Firebase sign-in before destructive
  cleanup begins.
- Owned boards are deleted with their members, columns, work items, and applied
  operation markers before Firebase Authentication is removed.
- The account leaves shared boards without deleting content belonging to those
  boards, and user/device records are removed.
- Cleanup is retry-safe. A preflight or cloud-cleanup failure leaves Firebase
  Authentication intact so the user can retry.
- Targeted cleanup/UI tests, the full 254-test serialized Flutter suite, all 29
  emulator rules tests, static analysis, and the Firebase-profile Android
  release build passed.
- The required Firestore rules were deployed to `plandone-staging`.

### 2026-08-29 — Firestore authorization closeout

- Firestore rules now require the `owner` membership UID to match the board's
  immutable `ownerId`.
- Admins and owners cannot grant a second member the `owner` role.
- A legacy malformed extra-owner membership cannot delete the board; only the
  authenticated board `ownerId` can perform that action.
- All 23 emulator rules tests passed and the compiled rules were deployed to
  `plandone-staging`.

### 2026-08-26 — Firebase staging / Samsung SM-S938U1

- Password reset passed end to end: request, email delivery, reset link, new-password sign-in, and data reload.
- Device-local data migration preserved two boards, memberships, columns, and items under the Firebase user.
- Cloud recovery republished the migrated local workspace to `plandone-staging`; the sync queue drained to zero.
- Offline-created `M3 Offline Sync Test` reconciled to Firestore with its description and `Doing` column intact.
- Android registered a real `RTC_WAKEUP` reminder alarm; closed-process delivery and notification tap-to-open were verified on-device.
- `My Board` exported to app-managed JSON and restored under a generated board ID. The restored copy matched the original at 3 columns, 82 items, and 1 owner membership, then was removed. The saved backup was retained.
- Archive/unarchive and read-only item details passed on-device. Undo restoration remains covered by controller and phone-sized widget tests but still needs one direct device confirmation.
- Quick capture and hierarchy-valid Inbox triage passed. A cross-board source mismatch discovered during the check was fixed and regression-tested.
- Reminder mute suppressed the active alert and clearing mute restored it immediately.
- Daily completion-gated recurrence with single-step late handling generated one next instance in `My Board / To Do`; explicit sync and reopen retained exactly one active and one completed instance.
- Archived items now render correctly in Hierarchy view, with regression coverage. The Undo interaction window was increased from 8 to 15 seconds for device usability.
