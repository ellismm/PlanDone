# Personal MVP Smoke Checklist

Use this checklist before calling a build ready for daily personal use.

## Sign-in and boot

- [ ] App launches on physical Android device.
- [ ] Firebase sign-in succeeds.
- [ ] Existing board data loads after sign-in.
- [ ] App relaunch restores the prior board context.

## Core item workflow

- [ ] Create a new item from Workspace.
- [ ] Edit title/description/metadata and save.
- [ ] Move an item between columns.
- [ ] Archive and unarchive an item.
- [ ] Use undo after a move or archive action.
- [ ] Open item details without entering edit mode.

## Quick capture and inbox triage

- [ ] Add a quick-capture item from Workspace.
- [ ] Open Inbox view and confirm the capture appears.
- [ ] Triage the capture into board, column, type, and optional parent.
- [ ] Confirm the triaged item leaves inbox state and appears in the correct workspace view.

## Reminders

- [ ] Create or edit an item with a start or due date near the present.
- [ ] Confirm the reminder appears in the reminder center/banner when eligible.
- [ ] Snooze the reminder and confirm it is suppressed until expiry.
- [ ] Mute reminders temporarily and confirm alerts are suppressed.
- [ ] Background or close the Android app and verify the local scheduled notification still fires.

## Recurrence

- [ ] Create a recurring task or action.
- [ ] Set cadence and late-completion policy.
- [ ] Complete the item and confirm exactly one next instance is generated.
- [ ] Verify the generated instance lands in the expected board/column.
- [ ] Confirm repeated reopen/sync does not generate duplicates.

## Offline and sync recovery

- [ ] Disable network.
- [ ] Create, edit, move, and archive at least one item while offline.
- [ ] Re-enable network.
- [ ] Trigger sync if needed.
- [ ] Confirm offline edits persist and reconcile cleanly.

## Backup and restore

- [ ] Open `Board Configuration -> Backup & Restore`.
- [ ] Export the current board snapshot.
- [ ] Confirm the JSON backup appears in the backup list.
- [ ] Restore the backup.
- [ ] Confirm the restored board appears as a new board with hierarchy, metadata, and recurrence intact.

## Final release decision

- [x] `flutter analyze` passed on 2026-04-17.
- [x] `flutter test` passed on 2026-04-17.
- [x] `flutter test --concurrency=1` passed on 2026-04-17.
- [x] `npm run test:rules` passed on 2026-04-17.
- [x] `flutter build apk --release` passed on 2026-04-17.
- [ ] Manual smoke completed without blocking issues.
- [ ] Any remaining issues are documented in [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md).
