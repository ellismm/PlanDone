import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_navigation_shell.dart';
import '../../../app_routes.dart';
import '../../../core/runtime/runtime_flags.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models/board_failures.dart';
import '../domain/models/board.dart';
import '../domain/models/board_filter_preset.dart';
import '../domain/models/board_member.dart';
import '../domain/models/board_reminder_alert.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/board_workflow_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_activity_event.dart';
import '../domain/models/work_item_recurrence.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/autofill_suggestion_policy.dart';
import '../domain/policies/board_permissions.dart';
import 'board_controller.dart';
import 'board_item_tile.dart';
import 'hierarchy_visuals.dart';

class BoardPage extends ConsumerWidget {
  const BoardPage({super.key});

  void _showActionFeedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _confirmDestructiveAction(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _formatRetryTime(DateTime retryAt) {
    final diff = retryAt.difference(DateTime.now());
    if (diff.inSeconds <= 0) return 'now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  Future<bool> _runGuardedAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return true;
    } on BoardPermissionDeniedException catch (error) {
      _showActionFeedback(context, error.message);
    } on BoardValidationException catch (error) {
      _showActionFeedback(context, error.message);
    } catch (error) {
      _showActionFeedback(context, 'Action failed: $error');
    }
    return false;
  }

  Future<T?> _runGuardedActionWithResult<T>(
    BuildContext context,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on BoardPermissionDeniedException catch (error) {
      _showActionFeedback(context, error.message);
    } on BoardValidationException catch (error) {
      _showActionFeedback(context, error.message);
    } catch (error) {
      _showActionFeedback(context, 'Action failed: $error');
    }
    return null;
  }

  List<DropdownMenuItem<int?>> _goalColorMenuItems({
    required int autoColor,
  }) {
    return [
      DropdownMenuItem<int?>(
        value: null,
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(autoColor),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Auto (random unused)'),
          ],
        ),
      ),
      for (var i = 0; i < hierarchyGoalColorPalette.length; i++)
        DropdownMenuItem<int?>(
          value: hierarchyGoalColorPalette[i],
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Color(hierarchyGoalColorPalette[i]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text('Palette ${i + 1}'),
            ],
          ),
        ),
    ];
  }

  void _showUndoSnackBar(
    BuildContext context,
    WidgetRef ref, {
    required BoardUndoOperation operation,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(operation.message),
        duration: BoardController.undoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _runGuardedAction(
              context,
              () async {
                final restored = await ref
                    .read(boardControllerProvider)
                    .undoPendingOperation();
                if (!restored) {
                  _showActionFeedback(context, 'Undo window expired.');
                }
              },
            );
          },
        ),
      ),
    );
    controller.closed.then((_) {
      ref
          .read(boardControllerProvider)
          .clearPendingUndo(operationId: operation.operationId);
    });
  }

  Future<void> _moveItemWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required String toColumnId,
  }) async {
    if (item.columnId == toColumnId) return;
    final moved = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).moveItem(
            itemId: item.itemId,
            toColumnId: toColumnId,
          ),
    );
    if (!moved) return;
    final undo = ref.read(boardControllerProvider).stageMoveUndo(
          item: item,
          fromBoardId: item.boardId,
          fromColumnId: item.columnId,
          toBoardId: item.boardId,
          toColumnId: toColumnId,
        );
    _showUndoSnackBar(context, ref, operation: undo);
  }

  Future<void> _toggleArchiveWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
  }) async {
    final nextArchived = !item.archived;
    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateItem(
            itemId: item.itemId,
            archived: nextArchived,
          ),
    );
    if (!updated) return;
    final undo = ref.read(boardControllerProvider).stageArchiveUndo(
          item: item,
          fromArchived: item.archived,
          toArchived: nextArchived,
        );
    _showUndoSnackBar(context, ref, operation: undo);
  }

  Future<void> _deleteItemWithUndo(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
  }) async {
    final hasChildren = allItems.any((entry) => entry.parentId == item.itemId);
    if (hasChildren) {
      _showActionFeedback(
        context,
        'Cannot delete an item with children. Re-parent or delete children first.',
      );
      return;
    }
    final confirmed = await _confirmDestructiveAction(
      context,
      title: 'Delete item?',
      message: 'Delete "${item.title}"?',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    final deleted = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteItem(itemId: item.itemId),
    );
    if (!deleted) return;
    final undo = ref.read(boardControllerProvider).stageDeleteUndo(item: item);
    _showUndoSnackBar(context, ref, operation: undo);
  }

  Future<String?> _pickTargetColumnForBoard(
    BuildContext context,
    WidgetRef ref, {
    required String boardId,
  }) async {
    final targetSnapshot =
        await ref.read(localBoardStoreProvider).getBoard(boardId);
    final ordered = [...targetSnapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (ordered.isEmpty) return null;

    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose target column'),
        children: [
          for (final column in ordered)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(column.columnId),
              child: Text(column.name),
            ),
        ],
      ),
    );
  }

  Future<void> _handleDropToBoardTarget(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required String targetBoardId,
  }) async {
    final targetColumnId =
        await _pickTargetColumnForBoard(context, ref, boardId: targetBoardId);
    if (targetColumnId == null) return;

    final sourceBoardId = item.boardId;
    final sourceColumnId = item.columnId;

    final moved = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).moveItemToBoard(
            itemId: item.itemId,
            toBoardId: targetBoardId,
            toColumnId: targetColumnId,
          ),
    );
    if (!moved) return;
    final undo = ref.read(boardControllerProvider).stageMoveUndo(
          item: item,
          fromBoardId: sourceBoardId,
          fromColumnId: sourceColumnId,
          toBoardId: targetBoardId,
          toColumnId: targetColumnId,
        );
    _showUndoSnackBar(context, ref, operation: undo);
  }

  String _filterLabel(BoardVisibilityFilter filter) {
    return switch (filter) {
      BoardVisibilityFilter.tasksOnly => 'Tasks (containers)',
      BoardVisibilityFilter.goalsOnly => 'Goals',
      BoardVisibilityFilter.projectsOnly => 'Projects',
      BoardVisibilityFilter.actionsOnly => 'Action (doable)',
      BoardVisibilityFilter.allItems => 'All',
    };
  }

  String _stateFilterLabel(BoardItemStateFilter filter) {
    return switch (filter) {
      BoardItemStateFilter.any => 'Any state',
      BoardItemStateFilter.active => 'Active',
      BoardItemStateFilter.done => 'Done',
      BoardItemStateFilter.blocked => 'Blocked',
      BoardItemStateFilter.cancelled => 'Cancelled',
      BoardItemStateFilter.urgent => 'Urgent',
      BoardItemStateFilter.overdue => 'Overdue',
      BoardItemStateFilter.dueSoon => 'Due ≤ 7d',
    };
  }

  String _reminderKindLabel(BoardReminderKind kind) {
    return switch (kind) {
      BoardReminderKind.start => 'Start',
      BoardReminderKind.due => 'Due',
    };
  }

  Future<void> _showNotificationPreferencesDialog(
    BuildContext context,
    WidgetRef ref, {
    required NotificationPreferences initial,
  }) async {
    var preferences = initial;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isMuted =
              preferences.mutedUntil?.isAfter(DateTime.now()) ?? false;
          return AlertDialog(
            title: const Text('Notification preferences'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: preferences.enabled,
                    title: const Text('Enable reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences = preferences.copyWith(enabled: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: preferences.remindOnDueDate,
                    title: const Text('Due date reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences =
                            preferences.copyWith(remindOnDueDate: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: preferences.remindOnStartDate,
                    title: const Text('Start date reminders'),
                    onChanged: (value) {
                      setState(() {
                        preferences =
                            preferences.copyWith(remindOnStartDate: value);
                      });
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.dueReminderMinutesBefore,
                    decoration: const InputDecoration(
                      labelText: 'Due reminder lead time',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('At due time')),
                      DropdownMenuItem(
                          value: 15, child: Text('15 minutes before')),
                      DropdownMenuItem(
                          value: 30, child: Text('30 minutes before')),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                      DropdownMenuItem(
                          value: 240, child: Text('4 hours before')),
                      DropdownMenuItem(
                          value: 1440, child: Text('1 day before')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences = preferences.copyWith(
                            dueReminderMinutesBefore: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.startReminderMinutesBefore,
                    decoration: const InputDecoration(
                      labelText: 'Start reminder lead time',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('At start time')),
                      DropdownMenuItem(
                          value: 10, child: Text('10 minutes before')),
                      DropdownMenuItem(
                          value: 15, child: Text('15 minutes before')),
                      DropdownMenuItem(
                          value: 30, child: Text('30 minutes before')),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences = preferences.copyWith(
                            startReminderMinutesBefore: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: preferences.defaultSnoozeMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Default snooze duration',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 hour')),
                      DropdownMenuItem(value: 240, child: Text('4 hours')),
                      DropdownMenuItem(value: 1440, child: Text('1 day')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        preferences =
                            preferences.copyWith(defaultSnoozeMinutes: value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mute reminders'),
                    subtitle: Text(
                      isMuted
                          ? 'Muted until ${preferences.mutedUntil!.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}'
                          : 'Not muted',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (isMuted)
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                preferences =
                                    preferences.copyWith(clearMutedUntil: true);
                              });
                            },
                            child: const Text('Clear'),
                          )
                        else
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                preferences = preferences.copyWith(
                                  mutedUntil: DateTime.now()
                                      .add(const Duration(hours: 8)),
                                );
                              });
                            },
                            child: const Text('8h'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await _runGuardedAction(
                    context,
                    () => ref
                        .read(boardControllerProvider)
                        .updateNotificationPreferences(preferences),
                  );
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAutofillSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required AutofillSettings initial,
  }) async {
    var settings = initial;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Autofill suggestions'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: settings.enabled,
                    title: const Text('Enable deterministic suggestions'),
                    onChanged: (value) {
                      setState(() {
                        settings = settings.copyWith(enabled: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    value: settings.suggestType,
                    title: const Text('Suggest item type'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestType: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestColumn,
                    title: const Text('Suggest column'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestColumn: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestParent,
                    title: const Text('Suggest parent'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestParent: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestTags,
                    title: const Text('Suggest tags'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestTags: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestEstimate,
                    title: const Text('Suggest estimate'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestEstimate: value),
                            )
                        : null,
                  ),
                  SwitchListTile(
                    value: settings.suggestBoard,
                    title: const Text('Suggest triage board'),
                    onChanged: settings.enabled
                        ? (value) => setState(
                              () => settings =
                                  settings.copyWith(suggestBoard: value),
                            )
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await _runGuardedAction(
                    context,
                    () => ref
                        .read(boardControllerProvider)
                        .updateAutofillSettings(settings),
                  );
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showReminderCenterSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<BoardReminderAlert> reminders,
    required NotificationPreferences preferences,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reminders (${reminders.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showNotificationPreferencesDialog(
                        context,
                        ref,
                        initial: preferences,
                      );
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text('Preferences'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: reminders.isEmpty
                    ? const Center(child: Text('No active reminders.'))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: reminders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final reminder = reminders[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              reminder.isOverdue
                                  ? Icons.warning_amber_rounded
                                  : Icons.notifications_active_outlined,
                              color: reminder.isOverdue
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            title: Text(reminder.item.title),
                            subtitle: Text(
                              '${_reminderKindLabel(reminder.kind)} • ${reminder.message}',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .snoozeReminder(
                                        reminderId: reminder.reminderId,
                                      ),
                                );
                              },
                              child: const Text('Snooze'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _densityLabel(BoardCardDensity density) {
    return switch (density) {
      BoardCardDensity.comfortable => 'Comfortable',
      BoardCardDensity.compact => 'Compact',
    };
  }

  Future<void> _showWorkspaceFiltersSheet(
    BuildContext context,
    WidgetRef ref, {
    required BoardVisibilityFilter visibilityFilter,
    required BoardItemStateFilter stateFilter,
    required String tagFilter,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) async {
    var selectedVisibility = visibilityFilter;
    var selectedState = stateFilter;
    var selectedTag = tagFilter;
    var selectedOverdue = showOverdueOnly;
    var selectedDueSoon = showDueSoonOnly;
    var selectedArchived = showArchivedOnly;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filters',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BoardVisibilityFilter>(
                    initialValue: selectedVisibility,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final value in BoardVisibilityFilter.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_filterLabel(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedVisibility = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<BoardItemStateFilter>(
                    initialValue: selectedState,
                    decoration: const InputDecoration(labelText: 'State'),
                    items: [
                      for (final value in BoardItemStateFilter.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_stateFilterLabel(value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedState = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: selectedTag,
                    decoration: const InputDecoration(
                      labelText: 'Tag contains',
                      hintText: 'e.g. ux',
                    ),
                    onChanged: (value) => selectedTag = value,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Overdue'),
                        selected: selectedOverdue,
                        onSelected: (value) {
                          setState(() {
                            selectedOverdue = value;
                            if (value) selectedDueSoon = false;
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Due ≤ 7d'),
                        selected: selectedDueSoon,
                        onSelected: (value) {
                          setState(() {
                            selectedDueSoon = value;
                            if (value) selectedOverdue = false;
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Archived'),
                        selected: selectedArchived,
                        onSelected: (value) {
                          setState(() => selectedArchived = value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          ref
                              .read(boardVisibilityFilterProvider.notifier)
                              .state = BoardVisibilityFilter.allItems;
                          ref
                              .read(boardItemStateFilterProvider.notifier)
                              .state = BoardItemStateFilter.any;
                          ref.read(boardTagFilterProvider.notifier).state = '';
                          ref.read(showOverdueOnlyProvider.notifier).state =
                              false;
                          ref.read(showDueSoonOnlyProvider.notifier).state =
                              false;
                          ref.read(showArchivedOnlyProvider.notifier).state =
                              false;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Reset'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          ref
                              .read(boardVisibilityFilterProvider.notifier)
                              .state = selectedVisibility;
                          ref
                              .read(boardItemStateFilterProvider.notifier)
                              .state = selectedState;
                          ref.read(boardTagFilterProvider.notifier).state =
                              selectedTag.trim();
                          ref.read(showOverdueOnlyProvider.notifier).state =
                              selectedOverdue;
                          ref.read(showDueSoonOnlyProvider.notifier).state =
                              selectedDueSoon;
                          ref.read(showArchivedOnlyProvider.notifier).state =
                              selectedArchived;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSavePresetDialog(
    BuildContext context,
    WidgetRef ref, {
    BoardFilterPreset? existing,
  }) async {
    var presetName = existing?.name ?? '';
    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Save filter preset' : 'Rename preset'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Preset name',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => presetName = value,
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = presetName.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            child: Text(existing == null ? 'Save' : 'Rename'),
          ),
        ],
      ),
    );
    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;

    if (existing == null) {
      await _runGuardedAction(
        context,
        () => ref
            .read(boardControllerProvider)
            .saveCurrentFilterPreset(name: name),
      );
    } else {
      await _runGuardedAction(
        context,
        () => ref.read(boardControllerProvider).renameFilterPreset(
              preset: existing,
              name: name,
            ),
      );
    }
  }

  Future<void> _showFilterPresetsSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<BoardFilterPreset> presets,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter presets',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _showSavePresetDialog(context, ref);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Save current'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (presets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No presets yet. Save your current filters.'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: presets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(preset.name),
                        subtitle: Text(
                          'Updated ${preset.updatedAt.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'apply':
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .applyFilterPreset(preset),
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                                break;
                              case 'update':
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .saveCurrentFilterPreset(
                                        name: preset.name,
                                        presetId: preset.presetId,
                                      ),
                                );
                                break;
                              case 'rename':
                                await _showSavePresetDialog(
                                  context,
                                  ref,
                                  existing: preset,
                                );
                                break;
                              case 'delete':
                                final shouldDelete =
                                    await _confirmDestructiveAction(
                                  context,
                                  title: 'Delete preset?',
                                  message:
                                      'Delete "${preset.name}" filter preset?',
                                  confirmLabel: 'Delete',
                                );
                                if (!shouldDelete) break;
                                await _runGuardedAction(
                                  context,
                                  () => ref
                                      .read(boardControllerProvider)
                                      .deleteFilterPreset(preset.presetId),
                                );
                                break;
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'apply',
                              child: Text('Apply preset'),
                            ),
                            PopupMenuItem(
                              value: 'update',
                              child: Text('Update from current filters'),
                            ),
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await _runGuardedAction(
                            context,
                            () => ref
                                .read(boardControllerProvider)
                                .applyFilterPreset(preset),
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesFilter(WorkItem item, BoardVisibilityFilter filter) {
    return switch (filter) {
      BoardVisibilityFilter.tasksOnly => item.type == WorkItemType.task,
      BoardVisibilityFilter.goalsOnly => item.type == WorkItemType.goal,
      BoardVisibilityFilter.projectsOnly => item.type == WorkItemType.project,
      BoardVisibilityFilter.actionsOnly => item.type == WorkItemType.action,
      BoardVisibilityFilter.allItems => true,
    };
  }

  bool _matchesStateFilter({
    required WorkItem item,
    required BoardItemStateFilter stateFilter,
    required Map<String, BoardColumn> columnsById,
  }) {
    if (stateFilter == BoardItemStateFilter.any) return true;

    final now = DateTime.now();
    final dueAt = item.dueAt;
    final horizon = now.add(const Duration(days: 7));
    final column = columnsById[item.columnId];
    final isDone = item.completedAt != null || column?.isDoneState == true;
    final isCancelled = column?.isCancelledState == true;
    final isBlocked = column?.isBlockedState == true;
    final isUrgent = column?.kind == BoardColumnKind.urgent;
    final isOverdue =
        dueAt != null && item.completedAt == null && dueAt.isBefore(now);
    final isDueSoon = dueAt != null &&
        item.completedAt == null &&
        !dueAt.isBefore(now) &&
        !dueAt.isAfter(horizon);

    return switch (stateFilter) {
      BoardItemStateFilter.any => true,
      BoardItemStateFilter.active => !isDone && !isCancelled,
      BoardItemStateFilter.done => isDone,
      BoardItemStateFilter.blocked => isBlocked,
      BoardItemStateFilter.cancelled => isCancelled,
      BoardItemStateFilter.urgent => isUrgent,
      BoardItemStateFilter.overdue => isOverdue,
      BoardItemStateFilter.dueSoon => isDueSoon,
    };
  }

  int _typeRank(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 0,
      WorkItemType.project => 1,
      WorkItemType.task => 2,
      WorkItemType.action => 3,
    };
  }

  bool _isRecommendedParentType({
    required WorkItemType child,
    required WorkItemType parent,
  }) {
    return _typeRank(parent) < _typeRank(child);
  }

  Set<String> _focusRelatedItemIds(List<WorkItem> items, String focusedItemId) {
    final byId = {for (final item in items) item.itemId: item};
    final childMap = <String, List<WorkItem>>{};
    for (final item in items) {
      final parentId = item.parentId;
      if (parentId == null) continue;
      childMap.putIfAbsent(parentId, () => []).add(item);
    }

    final visible = <String>{focusedItemId};

    var cursor = byId[focusedItemId];
    while (cursor?.parentId != null) {
      final parent = byId[cursor!.parentId!];
      if (parent == null) break;
      visible.add(parent.itemId);
      cursor = parent;
    }

    final queue = <String>[focusedItemId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      final children = childMap[id] ?? const [];
      for (final child in children) {
        if (visible.add(child.itemId)) {
          queue.add(child.itemId);
        }
      }
    }

    return visible;
  }

  bool _isVisibleInCurrentModes({
    required WorkItem item,
    required BoardVisibilityFilter filter,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    if (item.isInbox) return false;
    if (!_matchesFilter(item, filter)) return false;
    if (!_matchesStateFilter(
      item: item,
      stateFilter: stateFilter,
      columnsById: columnsById,
    )) {
      return false;
    }
    if (tagFilter.trim().isNotEmpty) {
      final normalized = tagFilter.trim().toLowerCase();
      final hasTag =
          item.tags.any((tag) => tag.toLowerCase().contains(normalized));
      if (!hasTag) return false;
    }
    if (textQuery.trim().isNotEmpty &&
        !item.title.toLowerCase().contains(textQuery.trim().toLowerCase())) {
      return false;
    }
    if (showOverdueOnly) {
      final dueAt = item.dueAt;
      final isOverdue = dueAt != null &&
          item.completedAt == null &&
          dueAt.isBefore(DateTime.now());
      if (!isOverdue) return false;
    }
    if (showDueSoonOnly) {
      final dueAt = item.dueAt;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 7));
      final isDueSoon = dueAt != null &&
          item.completedAt == null &&
          !dueAt.isBefore(now) &&
          !dueAt.isAfter(horizon);
      if (!isDueSoon) return false;
    }
    if (showArchivedOnly) {
      if (!item.archived) return false;
    } else if (item.archived) {
      return false;
    }
    if (!focusModeEnabled || focusRelatedItemIds == null) return true;
    return focusRelatedItemIds.contains(item.itemId);
  }

  List<WorkItem> _sortedVisibleItems({
    required List<WorkItem> items,
    required String columnId,
    required BoardVisibilityFilter filter,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    final visible = items.where((i) {
      if (i.columnId != columnId) return false;
      return _isVisibleInCurrentModes(
        item: i,
        filter: filter,
        stateFilter: stateFilter,
        focusModeEnabled: focusModeEnabled,
        focusRelatedItemIds: focusRelatedItemIds,
        textQuery: textQuery,
        tagFilter: tagFilter,
        columnsById: columnsById,
        showOverdueOnly: showOverdueOnly,
        showDueSoonOnly: showDueSoonOnly,
        showArchivedOnly: showArchivedOnly,
      );
    }).toList();

    int urgencyRank(WorkItem item) {
      final now = DateTime.now();
      if (item.completedAt != null) return 3;
      if (item.dueAt != null && item.dueAt!.isBefore(now)) return 0;
      if (item.dueAt != null) return 1;
      return 2;
    }

    visible.sort((a, b) {
      final urgency = urgencyRank(a).compareTo(urgencyRank(b));
      if (urgency != 0) return urgency;

      if (a.dueAt != null && b.dueAt != null) {
        final due = a.dueAt!.compareTo(b.dueAt!);
        if (due != 0) return due;
      }

      final updated = b.updatedAt.compareTo(a.updatedAt);
      if (updated != 0) return updated;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return visible;
  }

  Future<void> _confirmDeleteColumn(
    BuildContext context,
    WidgetRef ref, {
    required String columnId,
    required String name,
    required bool canDelete,
  }) async {
    if (!canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must keep at least one column.')),
      );
      return;
    }

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete column?'),
            content:
                Text('Delete "$name"? Items will be moved to another column.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).deleteColumn(columnId),
    );
  }

  Future<void> _showAddColumnDialog(BuildContext context, WidgetRef ref) async {
    String columnName = '';

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add column'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Column name'),
            textInputAction: TextInputAction.done,
            onChanged: (value) => columnName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = columnName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createColumn(name),
    );
  }

  Future<void> _showRenameColumnDialog(
    BuildContext context,
    WidgetRef ref, {
    required String columnId,
    required String currentName,
  }) async {
    String columnName = currentName;

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename column'),
          content: TextField(
            autofocus: true,
            decoration: InputDecoration(hintText: currentName),
            textInputAction: TextInputAction.done,
            onChanged: (value) => columnName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = columnName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;
    await _runGuardedAction(
      context,
      () => ref
          .read(boardControllerProvider)
          .renameColumn(columnId: columnId, name: name),
    );
  }

  Future<void> _showCreateBoardDialog(
      BuildContext context, WidgetRef ref) async {
    String boardName = '';

    final submittedName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create board'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Board name'),
            textInputAction: TextInputAction.done,
            onChanged: (value) => boardName = value,
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = boardName.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(name);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final name = submittedName?.trim();
    if (name == null || name.isEmpty) return;

    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createBoard(name),
    );
  }

  String _roleLabel(BoardRole role) {
    final name = role.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  Future<void> _showValidationSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardValidationSettings initial,
  }) async {
    var settings = initial;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Validation settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      value: settings.requireParentForProjects,
                      title: const Text('Require parent for projects'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForProjects: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.requireParentForTasks,
                      title: const Text('Require parent for tasks'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForTasks: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.requireParentForActions,
                      title: const Text('Require parent for actions'),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            requireParentForActions: value,
                          );
                        });
                      },
                    ),
                    SwitchListTile(
                      value: settings.enforceParentTypeOrder,
                      title: const Text('Enforce parent type order'),
                      subtitle: const Text(
                        'Parent must be a higher-level type than child.',
                      ),
                      onChanged: (value) {
                        setState(() {
                          settings = settings.copyWith(
                            enforceParentTypeOrder: value,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final ok = await _runGuardedAction(
                      context,
                      () => ref
                          .read(boardControllerProvider)
                          .updateBoardValidationSettings(settings),
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _workflowKindLabel(BoardColumnKind kind) {
    return switch (kind) {
      BoardColumnKind.planning => 'Planning',
      BoardColumnKind.backlog => 'Backlog',
      BoardColumnKind.ready => 'Ready',
      BoardColumnKind.inProgress => 'In Progress',
      BoardColumnKind.blocked => 'Blocked',
      BoardColumnKind.urgent => 'Urgent',
      BoardColumnKind.review => 'Review',
      BoardColumnKind.done => 'Done',
      BoardColumnKind.cancelled => 'Cancelled',
      BoardColumnKind.custom => 'Custom',
    };
  }

  Future<void> _showWorkflowSettingsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
  }) async {
    var workflow = snapshot.board.workflowSettings;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Workflow settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: workflow.templateId,
                      decoration:
                          const InputDecoration(labelText: 'Workflow template'),
                      items: const [
                        DropdownMenuItem(
                          value: BoardWorkflowSettings.legacyTemplateId,
                          child: Text('Legacy kanban'),
                        ),
                        DropdownMenuItem(
                          value: BoardWorkflowSettings.designatedTemplateId,
                          child: Text('Designated starter'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          workflow = workflow.copyWith(templateId: value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: workflow.allowCustomColumns,
                      title: const Text('Allow custom columns'),
                      onChanged: (value) {
                        setState(() {
                          workflow =
                              workflow.copyWith(allowCustomColumns: value);
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final currentTemplateId =
                        snapshot.board.workflowSettings.templateId;
                    final shouldApplyTemplate =
                        workflow.templateId != currentTemplateId &&
                            workflow.templateId ==
                                BoardWorkflowSettings.designatedTemplateId;

                    final ok = await _runGuardedAction(
                      context,
                      () async {
                        await ref
                            .read(boardControllerProvider)
                            .updateBoardWorkflowSettings(workflow);
                        if (shouldApplyTemplate) {
                          await ref
                              .read(boardControllerProvider)
                              .applyWorkflowTemplate(workflow.templateId);
                        }
                      },
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showColumnSemanticsDialog(
    BuildContext context,
    WidgetRef ref, {
    required BoardColumn column,
  }) async {
    var kind = column.kind;
    var isDoneState = column.isDoneState;
    var isBlockedState = column.isBlockedState;
    var isCancelledState = column.isCancelledState;
    var isEnabled = column.isEnabled;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Semantics: ${column.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<BoardColumnKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Kind'),
                      items: [
                        for (final entry in BoardColumnKind.values)
                          DropdownMenuItem(
                            value: entry,
                            child: Text(_workflowKindLabel(entry)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => kind = value);
                      },
                    ),
                    SwitchListTile(
                      value: isDoneState,
                      title: const Text('Done state'),
                      onChanged: (value) => setState(() => isDoneState = value),
                    ),
                    SwitchListTile(
                      value: isBlockedState,
                      title: const Text('Blocked state'),
                      onChanged: (value) =>
                          setState(() => isBlockedState = value),
                    ),
                    SwitchListTile(
                      value: isCancelledState,
                      title: const Text('Cancelled state'),
                      onChanged: (value) =>
                          setState(() => isCancelledState = value),
                    ),
                    SwitchListTile(
                      value: isEnabled,
                      title: const Text('Enabled'),
                      onChanged: (value) => setState(() => isEnabled = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final ok = await _runGuardedAction(
                      context,
                      () => ref
                          .read(boardControllerProvider)
                          .updateColumnSemantics(
                            columnId: column.columnId,
                            kind: kind,
                            isDoneState: isDoneState,
                            isBlockedState: isBlockedState,
                            isCancelledState: isCancelledState,
                            isEnabled: isEnabled,
                          ),
                    );
                    if (ok && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMemberManagementSheet(
    BuildContext context,
    WidgetRef ref, {
    required BoardSnapshot snapshot,
    required String currentUserId,
  }) async {
    var inviteUserId = '';
    var inviteRole = BoardRole.member;

    final members = [...snapshot.members]..sort((a, b) {
        if (a.role == BoardRole.owner && b.role != BoardRole.owner) return -1;
        if (a.role != BoardRole.owner && b.role == BoardRole.owner) return 1;
        return a.userId.compareTo(b.userId);
      });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Board members',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'User ID',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => inviteUserId = value,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<BoardRole>(
                          value: inviteRole,
                          items: const [
                            DropdownMenuItem(
                                value: BoardRole.viewer, child: Text('Viewer')),
                            DropdownMenuItem(
                                value: BoardRole.member, child: Text('Member')),
                            DropdownMenuItem(
                                value: BoardRole.admin, child: Text('Admin')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => inviteRole = value);
                          },
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final uid = inviteUserId.trim();
                            if (uid.isEmpty) return;
                            final ok = await _runGuardedAction(
                              context,
                              () => ref
                                  .read(boardControllerProvider)
                                  .inviteMember(userId: uid, role: inviteRole),
                            );
                            if (ok && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Text('Invite'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: members.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final pending =
                              BoardPermissions.isInvitePending(member);
                          final isOwner = member.role == BoardRole.owner;
                          final canModifyRole = !isOwner;
                          final canRemove = !isOwner;

                          return ListTile(
                            dense: true,
                            title: Text(member.userId),
                            subtitle: Text(
                              pending
                                  ? '${_roleLabel(member.role)} • Invite pending'
                                  : _roleLabel(member.role),
                            ),
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                if (isOwner)
                                  const Chip(label: Text('Owner'))
                                else
                                  DropdownButton<BoardRole>(
                                    value: member.role,
                                    items: const [
                                      DropdownMenuItem(
                                          value: BoardRole.viewer,
                                          child: Text('Viewer')),
                                      DropdownMenuItem(
                                          value: BoardRole.member,
                                          child: Text('Member')),
                                      DropdownMenuItem(
                                          value: BoardRole.admin,
                                          child: Text('Admin')),
                                    ],
                                    onChanged: !canModifyRole
                                        ? null
                                        : (value) async {
                                            if (value == null ||
                                                value == member.role) {
                                              return;
                                            }
                                            await _runGuardedAction(
                                              context,
                                              () => ref
                                                  .read(boardControllerProvider)
                                                  .updateMemberRole(
                                                    userId: member.userId,
                                                    role: value,
                                                  ),
                                            );
                                            if (context.mounted) {
                                              Navigator.of(context).pop();
                                            }
                                          },
                                  ),
                                IconButton(
                                  tooltip: member.userId == currentUserId
                                      ? 'Remove yourself'
                                      : 'Remove member',
                                  onPressed: !canRemove
                                      ? null
                                      : () async {
                                          final confirmed =
                                              await _confirmDestructiveAction(
                                            context,
                                            title:
                                                member.userId == currentUserId
                                                    ? 'Leave board?'
                                                    : 'Remove member?',
                                            message: member.userId ==
                                                    currentUserId
                                                ? 'You will lose access to this board.'
                                                : 'Remove ${member.userId} from this board?',
                                            confirmLabel: 'Remove',
                                          );
                                          if (!confirmed) return;
                                          await _runGuardedAction(
                                            context,
                                            () => ref
                                                .read(boardControllerProvider)
                                                .removeMember(member.userId),
                                          );
                                          if (context.mounted) {
                                            Navigator.of(context).pop();
                                          }
                                        },
                                  icon:
                                      const Icon(Icons.person_remove_outlined),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddTaskDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool canManageBoard,
  }) async {
    final snapshot = ref.read(boardStreamProvider).valueOrNull;
    if (snapshot == null) return;
    final columns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (columns.isEmpty) return;
    final autofillSettings = ref.read(autofillSettingsProvider).valueOrNull ??
        const AutofillSettings();

    String itemTitle = '';
    final parentCandidates = [...snapshot.items]..sort((a, b) {
        final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
        if (byType != 0) return byType;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    AutofillSuggestionDraft computeSuggestion(WorkItemType? selectedType) {
      return AutofillSuggestionPolicy.forCreateItem(
        snapshot: snapshot,
        settings: autofillSettings,
        selectedType: selectedType,
      );
    }

    final initialSuggestion = computeSuggestion(null);
    WorkItemType selectedType = initialSuggestion.type ?? WorkItemType.action;
    String selectedColumnId = initialSuggestion.columnId != null &&
            columns.any((entry) => entry.columnId == initialSuggestion.columnId)
        ? initialSuggestion.columnId!
        : columns.first.columnId;
    String? selectedParentId = initialSuggestion.parentId != null &&
            parentCandidates.any(
              (entry) => entry.itemId == initialSuggestion.parentId,
            )
        ? initialSuggestion.parentId
        : null;
    var tagsText = initialSuggestion.tags.join(', ');
    var estimatedEffortText =
        initialSuggestion.estimatedEffortMinutes?.toString() ?? '';
    int? selectedGoalColor;
    final autoGoalColor = chooseRandomUnusedGoalColor(
      items: snapshot.items,
      overrides: snapshot.board.validationSettings.hierarchyGoalColorOverrides,
      random: Random(),
    );
    var columnTouched = false;
    var parentTouched = false;
    var tagsTouched = false;
    var estimateTouched = false;

    void applySuggestionForType(
      WorkItemType type, {
      bool force = false,
    }) {
      final suggestion = computeSuggestion(type);
      if ((force || !columnTouched) &&
          suggestion.columnId != null &&
          columns.any((entry) => entry.columnId == suggestion.columnId)) {
        selectedColumnId = suggestion.columnId!;
      }
      if (force || !parentTouched) {
        selectedParentId = suggestion.parentId != null &&
                parentCandidates.any(
                  (entry) => entry.itemId == suggestion.parentId,
                )
            ? suggestion.parentId
            : null;
      }
      if (force || !tagsTouched) {
        tagsText = suggestion.tags.join(', ');
      }
      if (force || !estimateTouched) {
        estimatedEffortText =
            suggestion.estimatedEffortMinutes?.toString() ?? '';
      }
    }

    final submitted = await showDialog<
        (String, WorkItemType, String, String?, List<String>, int?, int?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Title'),
                    textInputAction: TextInputAction.done,
                    onChanged: (value) => itemTitle = value,
                    onSubmitted: (value) {
                      final title = value.trim();
                      if (title.isEmpty) return;
                      final tags = tagsText
                          .split(',')
                          .map((tag) => tag.trim())
                          .where((tag) => tag.isNotEmpty)
                          .toList();
                      Navigator.of(context).pop((
                        title,
                        selectedType,
                        selectedColumnId,
                        selectedParentId,
                        tags,
                        int.tryParse(estimatedEffortText.trim()),
                        selectedGoalColor,
                      ));
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: autofillSettings.enabled
                          ? () {
                              setState(() {
                                applySuggestionForType(selectedType,
                                    force: true);
                              });
                            }
                          : null,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Apply suggested defaults'),
                    ),
                  ),
                  DropdownButtonFormField<WorkItemType>(
                    initialValue: selectedType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                          value: WorkItemType.goal, child: Text('Goal')),
                      DropdownMenuItem(
                          value: WorkItemType.project, child: Text('Project')),
                      DropdownMenuItem(
                          value: WorkItemType.task,
                          child: Text('Task (container)')),
                      DropdownMenuItem(
                          value: WorkItemType.action,
                          child: Text('Action (doable)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedType = value;
                        if (selectedType != WorkItemType.goal) {
                          selectedGoalColor = null;
                        }
                        applySuggestionForType(value);
                      });
                    },
                  ),
                  if (selectedType == WorkItemType.goal && canManageBoard) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedGoalColor,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Goal color',
                        border: OutlineInputBorder(),
                      ),
                      items: _goalColorMenuItems(autoColor: autoGoalColor),
                      onChanged: (value) {
                        setState(() {
                          selectedGoalColor = value;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedColumnId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Column'),
                    items: [
                      for (final column in columns)
                        DropdownMenuItem(
                            value: column.columnId, child: Text(column.name)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedColumnId = value;
                        columnTouched = true;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedParentId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Parent (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final item in parentCandidates)
                        DropdownMenuItem<String?>(
                          value: item.itemId,
                          child: Text(
                            '${item.type.name.toUpperCase()}: ${item.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedParentId = value;
                        parentTouched = true;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: tagsText,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma separated)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      tagsText = value;
                      tagsTouched = true;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: estimatedEffortText,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Estimated effort (minutes)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      estimatedEffortText = value;
                      estimateTouched = true;
                    },
                  ),
                  if (selectedParentId != null)
                    Builder(
                      builder: (_) {
                        final parent = parentCandidates
                            .where((x) => x.itemId == selectedParentId)
                            .cast<WorkItem?>()
                            .firstWhere((_) => true, orElse: () => null);
                        if (parent == null) return const SizedBox.shrink();
                        final recommended = _isRecommendedParentType(
                          child: selectedType,
                          parent: parent.type,
                        );
                        if (recommended) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Tip: ${selectedType.name.toUpperCase()} items are usually nested under a higher-level type.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade700,
                                    ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final title = itemTitle.trim();
                  if (title.isEmpty) return;
                  final tags = tagsText
                      .split(',')
                      .map((tag) => tag.trim())
                      .where((tag) => tag.isNotEmpty)
                      .toList();
                  Navigator.of(context).pop((
                    title,
                    selectedType,
                    selectedColumnId,
                    selectedParentId,
                    tags,
                    int.tryParse(estimatedEffortText.trim()),
                    selectedGoalColor,
                  ));
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted == null) return;
    final created = await _runGuardedActionWithResult(
      context,
      () => ref.read(boardControllerProvider).createItem(
            title: submitted.$1,
            type: submitted.$2,
            toColumnId: submitted.$3,
            parentId: submitted.$4,
            tags: submitted.$5,
            estimatedEffortMinutes: submitted.$6,
          ),
    );
    if (created == null) return;
    if (!canManageBoard || created.type != WorkItemType.goal) return;

    final nextColor = submitted.$7 ?? autoGoalColor;
    final nextOverrides = Map<String, int>.from(
      snapshot.board.validationSettings.hierarchyGoalColorOverrides,
    )..[created.itemId] = nextColor;

    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).updateBoardValidationSettings(
            snapshot.board.validationSettings.copyWith(
              hierarchyColorGroupingByGoal: true,
              hierarchyGoalColorOverrides: nextOverrides,
            ),
          ),
    );
  }

  Future<void> _showQuickCaptureDialog(
      BuildContext context, WidgetRef ref) async {
    var title = '';
    var tagsText = '';

    final submitted = await showDialog<(String, List<String>)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick capture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'What do you need to remember?',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => title = value,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isEmpty) return;
                Navigator.of(context).pop((normalized, const <String>[]));
              },
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                hintText: 'tags (optional, comma separated)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => tagsText = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = title.trim();
              if (normalized.isEmpty) return;
              final tags = tagsText
                  .split(',')
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .toList();
              Navigator.of(context).pop((normalized, tags));
            },
            child: const Text('Capture'),
          ),
        ],
      ),
    );

    if (submitted == null) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).createInboxCapture(
            title: submitted.$1,
            tags: submitted.$2,
          ),
    );
    if (ok && context.mounted) {
      ref.read(boardWorkspaceSurfaceProvider.notifier).state =
          BoardWorkspaceSurface.inbox;
    }
  }

  Future<void> _showTriageInboxDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<Board> boards,
  }) async {
    if (boards.isEmpty) return;
    final autofillSettings = ref.read(autofillSettingsProvider).valueOrNull ??
        const AutofillSettings();
    final boardSnapshots = <BoardSnapshot>[];
    for (final board in boards) {
      try {
        final snapshot =
            await ref.read(localBoardStoreProvider).getBoard(board.boardId);
        boardSnapshots.add(snapshot);
      } catch (_) {
        // Ignore unavailable board snapshots; fallback still deterministic.
      }
    }

    var targetBoardId = boards
            .where((board) => board.boardId == item.boardId)
            .map((board) => board.boardId)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null) ??
        boards.first.boardId;
    targetBoardId = AutofillSuggestionPolicy.suggestBoardForInboxTriage(
          inboxItem: item,
          boardSnapshots: boardSnapshots,
          settings: autofillSettings,
          fallbackBoardId: targetBoardId,
        ) ??
        targetBoardId;
    var selectedType = item.type;
    String? selectedColumnId;
    String? selectedParentId;

    final submitted = await showDialog<(String, String, WorkItemType, String?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Triage inbox item'),
          content: FutureBuilder<BoardSnapshot>(
            future: ref.read(localBoardStoreProvider).getBoard(targetBoardId),
            builder: (context, snapshotAsync) {
              if (!snapshotAsync.hasData) {
                return const SizedBox(
                  width: 320,
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final targetSnapshot = snapshotAsync.data!;
              final columns = [...targetSnapshot.columns]
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
              if (columns.isEmpty) {
                return const SizedBox(
                  width: 320,
                  child: Text('Target board has no columns.'),
                );
              }
              selectedColumnId ??= columns.first.columnId;
              if (!columns
                  .any((column) => column.columnId == selectedColumnId)) {
                selectedColumnId = columns.first.columnId;
              }
              final candidates = targetSnapshot.items
                  .where((candidate) => candidate.itemId != item.itemId)
                  .toList()
                ..sort((a, b) => a.title.compareTo(b.title));
              if (selectedParentId != null &&
                  !candidates.any(
                      (candidate) => candidate.itemId == selectedParentId)) {
                selectedParentId = null;
              }

              return SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: targetBoardId,
                        decoration:
                            const InputDecoration(labelText: 'Target board'),
                        items: [
                          for (final board in boards)
                            DropdownMenuItem(
                              value: board.boardId,
                              child: Text(board.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null || value == targetBoardId) return;
                          setState(() {
                            targetBoardId = value;
                            selectedColumnId = null;
                            selectedParentId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedColumnId,
                        decoration:
                            const InputDecoration(labelText: 'Target column'),
                        items: [
                          for (final column in columns)
                            DropdownMenuItem(
                              value: column.columnId,
                              child: Text(column.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => selectedColumnId = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkItemType>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                              value: WorkItemType.goal, child: Text('Goal')),
                          DropdownMenuItem(
                              value: WorkItemType.project,
                              child: Text('Project')),
                          DropdownMenuItem(
                              value: WorkItemType.task, child: Text('Task')),
                          DropdownMenuItem(
                              value: WorkItemType.action,
                              child: Text('Action')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => selectedType = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedParentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Parent (optional)'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          for (final candidate in candidates)
                            DropdownMenuItem<String?>(
                              value: candidate.itemId,
                              child: Text(
                                '${candidate.type.name.toUpperCase()}: ${candidate.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => selectedParentId = value),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final columnId = selectedColumnId;
                if (columnId == null) return;
                Navigator.of(context).pop(
                    (targetBoardId, columnId, selectedType, selectedParentId));
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null) return;
    await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).triageInboxItem(
            itemId: item.itemId,
            toBoardId: submitted.$1,
            toColumnId: submitted.$2,
            type: submitted.$3,
            parentId: submitted.$4,
          ),
    );
  }

  Future<void> _showOutboxSheet(BuildContext context, WidgetRef ref) async {
    final pending = await ref.read(outboxQueueProvider).listPending();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pending sync operations (${pending.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: pending.isEmpty
                          ? null
                          : () async {
                              final report = await ref
                                  .read(boardControllerProvider)
                                  .syncNow(ignoreRetrySchedule: true);
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              _showActionFeedback(
                                context,
                                'Sync complete: ${report.processed} processed, ${report.failed} failed',
                              );
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry now'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (pending.isEmpty)
                  const Text('No pending operations')
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final op = pending[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                              '${op.type.name.toUpperCase()} ${op.entity}'),
                          subtitle: Text([
                            op.entityId,
                            if (op.attemptCount > 0)
                              'Attempts: ${op.attemptCount}',
                            if (op.nextAttemptAt != null)
                              'Retry in ${_formatRetryTime(op.nextAttemptAt!)}',
                            if (op.lastError?.isNotEmpty == true)
                              'Last error: ${op.lastError}',
                          ].join('\n')),
                          isThreeLine: true,
                          trailing: Text(
                            op.createdAt.toIso8601String().substring(11, 19),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _boardScopeLabel(List<Board> boards, Set<String> selectedBoardIds) {
    if (boards.isEmpty) return 'No boards';
    if (selectedBoardIds.isEmpty || selectedBoardIds.length >= boards.length) {
      return 'All boards';
    }
    if (selectedBoardIds.length == 1) {
      final boardId = selectedBoardIds.first;
      final board = boards
          .where((entry) => entry.boardId == boardId)
          .cast<Board?>()
          .firstWhere((_) => true, orElse: () => null);
      return board?.name ?? '1 board';
    }
    return '${selectedBoardIds.length} boards';
  }

  Future<void> _showBoardSelectionSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<Board> boards,
    required Set<String> selectedBoardIds,
    required String currentBoardId,
  }) async {
    if (boards.isEmpty) return;

    final allBoardIds = {for (final board in boards) board.boardId};
    var working = selectedBoardIds.isEmpty
        ? {...allBoardIds}
        : {...selectedBoardIds.where(allBoardIds.contains)};
    if (working.isEmpty) {
      working = {...allBoardIds};
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final allSelected = working.length == allBoardIds.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Board selection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All boards'),
                    value: allSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          working = {...allBoardIds};
                        } else {
                          working = {currentBoardId};
                        }
                      });
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final board in boards)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () {
                              setState(() {
                                working.add(board.boardId);
                              });
                              ref
                                  .read(boardControllerProvider)
                                  .switchBoard(board.boardId);
                            },
                            leading: Checkbox(
                              value: working.contains(board.boardId),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    working.add(board.boardId);
                                  } else if (working.length > 1) {
                                    working.remove(board.boardId);
                                  }
                                });
                              },
                            ),
                            title: Text(board.name),
                            trailing: board.boardId == currentBoardId
                                ? const Chip(label: Text('Active'))
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        final normalized = working.length >= allBoardIds.length
                            ? <String>{}
                            : working;
                        ref
                            .read(workspaceSelectedBoardIdsProvider.notifier)
                            .state = normalized;

                        final allowedIds =
                            normalized.isEmpty ? allBoardIds : normalized;
                        if (!allowedIds
                            .contains(ref.read(currentBoardIdProvider))) {
                          final fallback = boards
                              .where(
                                  (entry) => allowedIds.contains(entry.boardId))
                              .map((entry) => entry.boardId)
                              .cast<String?>()
                              .firstWhere((_) => true, orElse: () => null);
                          if (fallback != null) {
                            ref
                                .read(boardControllerProvider)
                                .switchBoard(fallback);
                          }
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQuickAddChildActionDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem parent,
    required List<BoardColumn> columns,
  }) async {
    if (columns.isEmpty) return;

    String itemTitle = '';
    var selectedColumnId = parent.columnId;

    final submitted = await showDialog<(String, String)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add child action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Parent: ${parent.title}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Action title',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => itemTitle = value,
                    onSubmitted: (value) {
                      final title = value.trim();
                      if (title.isEmpty) return;
                      Navigator.of(context).pop((title, selectedColumnId));
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedColumnId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Column'),
                    items: [
                      for (final column in columns)
                        DropdownMenuItem(
                          value: column.columnId,
                          child: Text(column.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedColumnId = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = itemTitle.trim();
                    if (title.isEmpty) return;
                    Navigator.of(context).pop((title, selectedColumnId));
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted == null) return;
    await _runGuardedAction(
      context,
      () async {
        await ref.read(boardControllerProvider).createItem(
              title: submitted.$1,
              type: WorkItemType.action,
              toColumnId: submitted.$2,
              parentId: parent.itemId,
            );
      },
    );
  }

  String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
  String _minutesLabel(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}m';
  }

  String _hierarchyPath({
    required WorkItem item,
    required List<WorkItem> allItems,
  }) {
    final byId = {for (final entry in allItems) entry.itemId: entry};
    final segments = <String>[item.title];
    var cursor = item;
    final visited = <String>{item.itemId};
    while (cursor.parentId != null) {
      final parent = byId[cursor.parentId!];
      if (parent == null) break;
      if (!visited.add(parent.itemId)) break;
      segments.insert(0, parent.title);
      cursor = parent;
    }
    return segments.join(' > ');
  }

  String _activityLabel(WorkItemActivityType type) {
    return switch (type) {
      WorkItemActivityType.created => 'Created',
      WorkItemActivityType.updated => 'Updated',
      WorkItemActivityType.moved => 'Moved',
      WorkItemActivityType.reparented => 'Re-parented',
      WorkItemActivityType.archived => 'Archived',
      WorkItemActivityType.unarchived => 'Unarchived',
      WorkItemActivityType.completed => 'Completed',
      WorkItemActivityType.reopened => 'Reopened',
    };
  }

  Future<void> _showItemDetailsSheet(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
    required BoardValidationSettings settings,
  }) async {
    final parent = item.parentId == null
        ? null
        : allItems
            .where((entry) => entry.itemId == item.parentId)
            .cast<WorkItem?>()
            .firstWhere((_) => true, orElse: () => null);
    final timelineFuture =
        ref.read(workItemActivityTimelineProvider(item.itemId).future);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(item.type.name.toUpperCase())),
                    if (item.archived) const Chip(label: Text('ARCHIVED')),
                    if (item.isInbox) const Chip(label: Text('INBOX')),
                    if (item.completedAt != null)
                      const Chip(label: Text('DONE')),
                  ],
                ),
                const SizedBox(height: 8),
                if (parent != null)
                  Text('Parent: ${parent.title}',
                      style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  'Path: ${_hierarchyPath(item: item, allItems: allItems)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (settings.showCreatedDate)
                  Text('Created: ${item.createdAt.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall),
                Text('Updated: ${item.updatedAt.toLocal().toIso8601String()}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (settings.showStartDate && item.startAt != null)
                  Text('Start: ${item.startAt!.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (settings.showTargetEndDate && item.targetEndAt != null)
                  Text(
                      'Target end: ${item.targetEndAt!.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (settings.showDueDate && item.dueAt != null)
                  Text('Due: ${item.dueAt!.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (settings.showCompletedDate && item.completedAt != null)
                  Text(
                      'Completed: ${item.completedAt!.toLocal().toIso8601String()}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (item.recurrence != null && item.recurrence!.enabled)
                  Text(
                    'Recurs: ${item.recurrence!.cadence.name} every ${item.recurrence!.interval} (${item.recurrence!.completionGated ? 'completion-gated' : 'time-based'})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (settings.showEstimatedEffort &&
                    item.estimatedEffortMinutes != null)
                  Text(
                    'Estimated effort: ${_minutesLabel(item.estimatedEffortMinutes!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (settings.showActualEffort &&
                    item.actualEffortMinutes != null)
                  Text(
                    'Actual effort: ${_minutesLabel(item.actualEffortMinutes!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (item.tags.isNotEmpty)
                  Text('Tags: ${item.tags.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Text('Activity',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                FutureBuilder<List<WorkItemActivityEvent>>(
                  future: timelineFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(),
                      );
                    }
                    final events = snapshot.data!;
                    if (events.isEmpty) {
                      return const Text('No activity yet for this item.');
                    }
                    return Column(
                      children: [
                        for (final event in events)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(_activityLabel(event.type)),
                            subtitle: Text(
                              event.createdAt.toLocal().toIso8601String(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showEditItemSheet(
                        context,
                        ref,
                        item: item,
                        allItems: allItems,
                        settings: settings,
                      );
                    },
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditItemSheet(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
    required BoardValidationSettings settings,
  }) async {
    final parentCandidates = allItems
        .where((x) => x.itemId != item.itemId)
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    var title = item.title;
    var description = item.description ?? '';
    DateTime? selectedStartAt = item.startAt;
    DateTime? selectedTargetEndAt = item.targetEndAt;
    DateTime? selectedDueAt = item.dueAt;
    var estimatedEffortText = item.estimatedEffortMinutes?.toString() ?? '';
    var actualEffortText = item.actualEffortMinutes?.toString() ?? '';
    var tagsText = item.tags.join(', ');
    String? selectedParentId = item.parentId;
    var recurrenceEnabled = item.recurrence?.enabled == true;
    var recurrenceCadence =
        item.recurrence?.cadence ?? WorkItemRecurrenceCadence.weekly;
    var recurrenceIntervalText = (item.recurrence?.interval ?? 1).toString();
    var recurrenceCompletionGated = item.recurrence?.completionGated ?? true;
    final recurrenceSupported =
        item.type == WorkItemType.task || item.type == WorkItemType.action;
    final permissionProfile = ref.read(boardPermissionProfileProvider);
    final canManageBoard =
        permissionProfile?.has(BoardCapability.manageBoard) ?? false;
    int? selectedGoalColor = item.type == WorkItemType.goal
        ? settings.hierarchyGoalColorOverrides[item.itemId]
        : null;
    final autoGoalColor = chooseRandomUnusedGoalColor(
      items: allItems.where((entry) => entry.itemId != item.itemId),
      overrides: settings.hierarchyGoalColorOverrides,
      random: Random(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Widget buildDateField({
              required String label,
              required DateTime? value,
              required ValueChanged<DateTime?> onChanged,
            }) {
              return InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  helperText: switch (label) {
                    'Start date' when settings.requireStartDate =>
                      'Required by board settings',
                    'Target end date' when settings.requireTargetEndDate =>
                      'Required by board settings',
                    'Due date' when settings.requireDueDate =>
                      'Required by board settings',
                    _ => null,
                  },
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(value == null ? 'No date' : _dateOnly(value)),
                    ),
                    IconButton(
                      tooltip: 'Pick $label',
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: value ?? now,
                          firstDate: DateTime(now.year - 10),
                          lastDate: DateTime(now.year + 20),
                        );
                        if (picked != null) {
                          onChanged(picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                    ),
                    IconButton(
                      tooltip: 'Clear $label',
                      onPressed: value == null ? null : () => onChanged(null),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Edit item',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: title,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => title = value,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => description = value,
                      ),
                      const SizedBox(height: 12),
                      if (settings.showStartDate)
                        buildDateField(
                          label: 'Start date',
                          value: selectedStartAt,
                          onChanged: (value) =>
                              setState(() => selectedStartAt = value),
                        ),
                      if (settings.showStartDate) const SizedBox(height: 12),
                      if (settings.showTargetEndDate)
                        buildDateField(
                          label: 'Target end date',
                          value: selectedTargetEndAt,
                          onChanged: (value) =>
                              setState(() => selectedTargetEndAt = value),
                        ),
                      if (settings.showTargetEndDate)
                        const SizedBox(height: 12),
                      if (settings.showDueDate)
                        buildDateField(
                          label: 'Due date',
                          value: selectedDueAt,
                          onChanged: (value) =>
                              setState(() => selectedDueAt = value),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedParentId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Parent',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('None')),
                          for (final candidate in parentCandidates)
                            DropdownMenuItem<String?>(
                              value: candidate.itemId,
                              child: Text(
                                candidate.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => selectedParentId = value),
                      ),
                      if (item.type == WorkItemType.goal && canManageBoard) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: selectedGoalColor,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Goal color',
                            border: OutlineInputBorder(),
                          ),
                          items: _goalColorMenuItems(autoColor: autoGoalColor),
                          onChanged: (value) {
                            setState(() => selectedGoalColor = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: tagsText,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma separated)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => tagsText = value,
                      ),
                      if (settings.showEstimatedEffort) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: estimatedEffortText,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Estimated effort (minutes)',
                            helperText: settings.requireEstimatedEffort
                                ? 'Required by board settings'
                                : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) => estimatedEffortText = value,
                        ),
                      ],
                      if (settings.showActualEffort) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: actualEffortText,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Actual effort (minutes)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => actualEffortText = value,
                        ),
                      ],
                      if (recurrenceSupported) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: recurrenceEnabled,
                          title: const Text('Recurring item'),
                          subtitle: const Text(
                            'Create next instance after completion.',
                          ),
                          onChanged: (value) {
                            setState(() => recurrenceEnabled = value);
                          },
                        ),
                        if (recurrenceEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<WorkItemRecurrenceCadence>(
                            initialValue: recurrenceCadence,
                            decoration: const InputDecoration(
                              labelText: 'Recurrence cadence',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.daily,
                                child: Text('Daily'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.weekly,
                                child: Text('Weekly'),
                              ),
                              DropdownMenuItem(
                                value: WorkItemRecurrenceCadence.customDays,
                                child: Text('Custom days'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => recurrenceCadence = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: recurrenceIntervalText,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: recurrenceCadence ==
                                      WorkItemRecurrenceCadence.weekly
                                  ? 'Every N week(s)'
                                  : 'Every N day(s)',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) =>
                                recurrenceIntervalText = value,
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: recurrenceCompletionGated,
                            title: const Text('Completion-gated'),
                            subtitle: const Text(
                              'Only generate next cycle after this item is completed.',
                            ),
                            onChanged: (value) {
                              setState(() => recurrenceCompletionGated = value);
                            },
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final normalizedTitle = title.trim();
                              if (normalizedTitle.isEmpty) return;

                              final normalizedDescription = description.trim();
                              final startAt = selectedStartAt;
                              final clearStartAt = selectedStartAt == null;
                              final targetEndAt = selectedTargetEndAt;
                              final clearTargetEndAt =
                                  selectedTargetEndAt == null;
                              final dueAt = selectedDueAt;
                              final clearDueAt = selectedDueAt == null;
                              final estimatedEffortMinutes =
                                  int.tryParse(estimatedEffortText.trim());
                              final actualEffortMinutes =
                                  int.tryParse(actualEffortText.trim());
                              final clearEstimatedEffort =
                                  estimatedEffortText.trim().isEmpty;
                              final clearActualEffort =
                                  actualEffortText.trim().isEmpty;
                              final recurrenceInterval = int.tryParse(
                                recurrenceIntervalText.trim(),
                              );
                              if (recurrenceEnabled &&
                                  (recurrenceInterval == null ||
                                      recurrenceInterval <= 0)) {
                                _showActionFeedback(
                                  context,
                                  'Recurrence interval must be a positive number.',
                                );
                                return;
                              }
                              final recurrence = recurrenceEnabled
                                  ? WorkItemRecurrence(
                                      enabled: true,
                                      cadence: recurrenceCadence,
                                      interval: recurrenceInterval ?? 1,
                                      completionGated:
                                          recurrenceCompletionGated,
                                      rootItemId: item.recurrence?.rootItemId ??
                                          item.itemId,
                                      sequence: item.recurrence?.sequence ?? 0,
                                    )
                                  : null;

                              final tags = tagsText
                                  .split(',')
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();

                              final ok = await _runGuardedAction(
                                context,
                                () => ref
                                    .read(boardControllerProvider)
                                    .updateItem(
                                      itemId: item.itemId,
                                      title: normalizedTitle,
                                      description: normalizedDescription.isEmpty
                                          ? null
                                          : normalizedDescription,
                                      clearDescription:
                                          normalizedDescription.isEmpty,
                                      parentId: selectedParentId,
                                      clearParent: selectedParentId == null,
                                      startAt: startAt,
                                      clearStartAt: clearStartAt,
                                      targetEndAt: targetEndAt,
                                      clearTargetEndAt: clearTargetEndAt,
                                      dueAt: dueAt,
                                      clearDueAt: clearDueAt,
                                      estimatedEffortMinutes:
                                          estimatedEffortMinutes,
                                      clearEstimatedEffort:
                                          clearEstimatedEffort,
                                      actualEffortMinutes: actualEffortMinutes,
                                      clearActualEffort: clearActualEffort,
                                      recurrence: recurrence,
                                      clearRecurrence: !recurrenceEnabled,
                                      tags: tags,
                                    ),
                              );
                              if (ok && context.mounted) {
                                if (item.type == WorkItemType.goal &&
                                    canManageBoard) {
                                  final nextOverrides = Map<String, int>.from(
                                    settings.hierarchyGoalColorOverrides,
                                  );
                                  if (selectedGoalColor == null) {
                                    nextOverrides.remove(item.itemId);
                                  } else {
                                    nextOverrides[item.itemId] =
                                        selectedGoalColor!;
                                  }
                                  await _runGuardedAction(
                                    context,
                                    () => ref
                                        .read(boardControllerProvider)
                                        .updateBoardValidationSettings(
                                          settings.copyWith(
                                            hierarchyColorGroupingByGoal: true,
                                            hierarchyGoalColorOverrides:
                                                nextOverrides,
                                          ),
                                        ),
                                  );
                                }
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleItemSelection(WidgetRef ref, String itemId) {
    final current = ref.read(selectedBoardItemIdsProvider);
    final next = <String>{...current};
    if (!next.add(itemId)) {
      next.remove(itemId);
    }
    ref.read(selectedBoardItemIdsProvider.notifier).state = next;
  }

  List<WorkItem> _sharedVisibleItems({
    required List<WorkItem> items,
    required BoardVisibilityFilter filter,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
  }) {
    final visible = items
        .where(
          (item) => _isVisibleInCurrentModes(
            item: item,
            filter: filter,
            stateFilter: stateFilter,
            focusModeEnabled: focusModeEnabled,
            focusRelatedItemIds: focusRelatedItemIds,
            textQuery: textQuery,
            tagFilter: tagFilter,
            columnsById: columnsById,
            showOverdueOnly: showOverdueOnly,
            showDueSoonOnly: showDueSoonOnly,
            showArchivedOnly: showArchivedOnly,
          ),
        )
        .toList();

    visible.sort((a, b) {
      final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
      if (byType != 0) return byType;

      final byDone = (a.completedAt != null ? 1 : 0)
          .compareTo(b.completedAt != null ? 1 : 0);
      if (byDone != 0) return byDone;

      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return visible;
  }

  Widget _buildInboxView({
    required BuildContext context,
    required WidgetRef ref,
    required List<WorkItem> allItems,
    required List<BoardColumn> columns,
    required List<Board> boards,
    required bool canModifyItems,
    required Set<String> selectedItemIds,
    required String? focusedItemId,
    required BoardCardDensity density,
    required BoardValidationSettings settings,
  }) {
    final compactDensity = density == BoardCardDensity.compact;
    final inboxItems = allItems.where((item) => item.isInbox).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (inboxItems.isEmpty) {
      return const Center(
        child: Text('Inbox is empty. Use Quick capture to add ideas fast.'),
      );
    }

    return ListView(
      padding: EdgeInsets.all(compactDensity ? 4 : 8),
      children: [
        for (final item in inboxItems)
          Padding(
            padding: EdgeInsets.only(bottom: compactDensity ? 2 : 8),
            child: BoardItemTile(
              item: item,
              columns: columns,
              allItems: allItems,
              focused: focusedItemId == item.itemId,
              selected: selectedItemIds.contains(item.itemId),
              childCount: allItems
                  .where((entry) => entry.parentId == item.itemId)
                  .length,
              onSelect: () {
                ref.read(focusedItemIdProvider.notifier).state = item.itemId;
              },
              onAddChildAction: () {
                _showQuickAddChildActionDialog(
                  context,
                  ref,
                  parent: item,
                  columns: columns,
                );
              },
              onEdit: () {
                _showEditItemSheet(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                  settings: settings,
                );
              },
              onViewDetails: () {
                _showItemDetailsSheet(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                  settings: settings,
                );
              },
              onToggleArchive: () {
                _toggleArchiveWithUndo(context, ref, item: item);
              },
              density: density,
              parentPathMode: settings.hierarchyParentPathMode,
              onMoveToColumn: (toColumnId) => _moveItemWithUndo(
                context,
                ref,
                item: item,
                toColumnId: toColumnId,
              ),
              onToggleSelected: () => _toggleItemSelection(ref, item.itemId),
              onReparent: canModifyItems
                  ? () => _showReparentDialog(
                        context,
                        ref,
                        item: item,
                        allItems: allItems,
                      )
                  : null,
              onTriage: canModifyItems
                  ? () => _showTriageInboxDialog(
                        context,
                        ref,
                        item: item,
                        boards: boards,
                      )
                  : null,
              onDelete: canModifyItems
                  ? () => _deleteItemWithUndo(
                        context,
                        ref,
                        item: item,
                        allItems: allItems,
                      )
                  : null,
              onJumpToParent: item.parentId == null
                  ? null
                  : () {
                      ref.read(boardVisibilityFilterProvider.notifier).state =
                          BoardVisibilityFilter.allItems;
                      ref.read(focusedItemIdProvider.notifier).state =
                          item.parentId;
                      ref.read(focusModeEnabledProvider.notifier).state = true;
                    },
              canModifyItems: canModifyItems,
            ),
          ),
      ],
    );
  }

  Future<void> _showReparentDialog(
    BuildContext context,
    WidgetRef ref, {
    required WorkItem item,
    required List<WorkItem> allItems,
  }) async {
    String? selectedParentId = item.parentId;
    final candidates = allItems
        .where((candidate) => candidate.itemId != item.itemId)
      ..toList();

    final submittedParent = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Re-parent item'),
            content: DropdownButtonFormField<String?>(
              initialValue: selectedParentId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Parent',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None (make root item)'),
                ),
                for (final candidate in candidates)
                  DropdownMenuItem<String?>(
                    value: candidate.itemId,
                    child: Text(
                      '${candidate.type.name.toUpperCase()}: ${candidate.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => selectedParentId = value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selectedParentId),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (submittedParent == item.parentId) return;
    final updated = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).reparentItem(
            itemId: item.itemId,
            parentId: submittedParent,
            clearParent: submittedParent == null,
          ),
    );
    if (!updated) return;
    final undo = ref.read(boardControllerProvider).stageReparentUndo(
          item: item,
          fromParentId: item.parentId,
          toParentId: submittedParent,
        );
    _showUndoSnackBar(context, ref, operation: undo);
  }

  Future<void> _showBulkMoveDialog(
    BuildContext context,
    WidgetRef ref, {
    required List<BoardColumn> columns,
    required Set<String> selectedItemIds,
  }) async {
    if (columns.isEmpty || selectedItemIds.isEmpty) return;
    var targetColumnId = columns.first.columnId;

    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Move ${selectedItemIds.length} selected item(s)'),
          content: DropdownButtonFormField<String>(
            initialValue: targetColumnId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Target column',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final column in columns)
                DropdownMenuItem(
                    value: column.columnId, child: Text(column.name)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => targetColumnId = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(targetColumnId),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).bulkUpdateItems(
            itemIds: selectedItemIds.toList(),
            toColumnId: submitted,
          ),
    );
    if (ok) {
      ref.read(selectedBoardItemIdsProvider.notifier).state = <String>{};
    }
  }

  Future<void> _showBulkTagDialog(
    BuildContext context,
    WidgetRef ref, {
    required Set<String> selectedItemIds,
    required bool remove,
  }) async {
    if (selectedItemIds.isEmpty) return;
    var tagsText = '';

    final submittedTags = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${remove ? 'Remove' : 'Add'} tags for '
            '${selectedItemIds.length} selected item(s)'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'comma,separated,tags',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => tagsText = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final tags = tagsText
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              if (tags.isEmpty) return;
              Navigator.of(context).pop(tags);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (submittedTags == null || submittedTags.isEmpty) return;
    final ok = await _runGuardedAction(
      context,
      () => ref.read(boardControllerProvider).bulkUpdateItems(
            itemIds: selectedItemIds.toList(),
            addTags: remove ? const [] : submittedTags,
            removeTags: remove ? submittedTags : const [],
          ),
    );
    if (ok) {
      ref.read(selectedBoardItemIdsProvider.notifier).state = <String>{};
    }
  }

  Widget _buildAlternativeView({
    required BuildContext context,
    required WidgetRef ref,
    required BoardPlanningView planningView,
    required List<BoardColumn> columns,
    required List<WorkItem> allItems,
    required BoardVisibilityFilter filter,
    required BoardItemStateFilter stateFilter,
    required bool focusModeEnabled,
    required Set<String>? focusRelatedItemIds,
    required String textQuery,
    required String tagFilter,
    required Map<String, BoardColumn> columnsById,
    required bool showOverdueOnly,
    required bool showDueSoonOnly,
    required bool showArchivedOnly,
    required String? focusedItemId,
    required bool canModifyItems,
    required Set<String> collapsedHierarchyItemIds,
    required Set<String> selectedItemIds,
    required BoardCardDensity density,
    required BoardValidationSettings settings,
  }) {
    final allItemsById = {for (final entry in allItems) entry.itemId: entry};
    final hierarchyColorEnabled = settings.hierarchyColorGroupingByGoal;
    final goalColors = hierarchyColorEnabled
        ? resolveGoalColors(
            items: allItems,
            overrides: settings.hierarchyGoalColorOverrides,
          )
        : const <String, int>{};

    final visibleItems = _sharedVisibleItems(
      items: allItems,
      filter: filter,
      stateFilter: stateFilter,
      focusModeEnabled: focusModeEnabled,
      focusRelatedItemIds: focusRelatedItemIds,
      textQuery: textQuery,
      tagFilter: tagFilter,
      columnsById: columnsById,
      showOverdueOnly: showOverdueOnly,
      showDueSoonOnly: showDueSoonOnly,
      showArchivedOnly: showArchivedOnly,
    );

    Widget buildItemCard(
      WorkItem item, {
      double indent = 0,
      int hierarchyDepth = 0,
      bool showHierarchyGuides = false,
      bool hasChildren = false,
      bool isCollapsed = false,
      VoidCallback? onToggleCollapsed,
    }) {
      final compactDensity = density == BoardCardDensity.compact;
      final topGoalId = hierarchyColorEnabled
          ? topLevelGoalIdForItem(item, allItemsById)
          : null;
      final accentColorValue = topGoalId == null ? null : goalColors[topGoalId];
      final accentColor =
          accentColorValue == null ? null : Color(accentColorValue);
      final tile = BoardItemTile(
        item: item,
        columns: columns,
        allItems: allItems,
        focused: focusedItemId == item.itemId,
        selected: selectedItemIds.contains(item.itemId),
        childCount:
            allItems.where((entry) => entry.parentId == item.itemId).length,
        onSelect: () {
          ref.read(focusedItemIdProvider.notifier).state = item.itemId;
        },
        onToggleSelected: () => _toggleItemSelection(ref, item.itemId),
        onAddChildAction: () {
          _showQuickAddChildActionDialog(
            context,
            ref,
            parent: item,
            columns: columns,
          );
        },
        onEdit: () {
          _showEditItemSheet(
            context,
            ref,
            item: item,
            allItems: allItems,
            settings: settings,
          );
        },
        onViewDetails: () {
          _showItemDetailsSheet(
            context,
            ref,
            item: item,
            allItems: allItems,
            settings: settings,
          );
        },
        onToggleArchive: () {
          _toggleArchiveWithUndo(context, ref, item: item);
        },
        density: density,
        showCompactParentSubtitle: showHierarchyGuides,
        parentPathMode: settings.hierarchyParentPathMode,
        onMoveToColumn: (toColumnId) => _moveItemWithUndo(
          context,
          ref,
          item: item,
          toColumnId: toColumnId,
        ),
        onReparent: canModifyItems
            ? () => _showReparentDialog(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                )
            : null,
        onDelete: canModifyItems
            ? () => _deleteItemWithUndo(
                  context,
                  ref,
                  item: item,
                  allItems: allItems,
                )
            : null,
        onJumpToParent: item.parentId == null
            ? null
            : () {
                ref.read(boardVisibilityFilterProvider.notifier).state =
                    BoardVisibilityFilter.allItems;
                ref.read(focusedItemIdProvider.notifier).state = item.parentId;
                ref.read(focusModeEnabledProvider.notifier).state = true;
              },
        canModifyItems: canModifyItems,
        accentColor: accentColor,
      );

      final guidedTile = !showHierarchyGuides || hierarchyDepth <= 0
          ? tile
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: hierarchyDepth * 10.0 + 12,
                    child: CustomPaint(
                      painter: _HierarchyGuidePainter(
                        depth: hierarchyDepth,
                        color: (accentColor ??
                                Theme.of(context).colorScheme.outlineVariant)
                            .withValues(
                          alpha: compactDensity ? 0.75 : 0.55,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (hasChildren)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: InkWell(
                      onTap: onToggleCollapsed,
                      borderRadius: BorderRadius.circular(10),
                      child: Icon(
                        isCollapsed ? Icons.chevron_right : Icons.expand_more,
                        size: compactDensity ? 16 : 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  SizedBox(width: compactDensity ? 16 : 18),
                Expanded(child: tile),
              ],
            );

      return Padding(
        padding: EdgeInsets.only(
          left: showHierarchyGuides ? 0 : indent,
          right: compactDensity
              ? (showHierarchyGuides ? 2 : 4)
              : (showHierarchyGuides ? 4 : 8),
          bottom: compactDensity
              ? (showHierarchyGuides ? 1 : 2)
              : (showHierarchyGuides ? 3 : 6),
        ),
        child: guidedTile,
      );
    }

    if (visibleItems.isEmpty) {
      return const Center(child: Text('No items match current filters.'));
    }

    if (planningView == BoardPlanningView.backlog) {
      final backlogKinds = {
        BoardColumnKind.planning,
        BoardColumnKind.backlog,
        BoardColumnKind.ready,
      };
      final backlogItems = visibleItems.where((item) {
        final kind = columnsById[item.columnId]?.kind;
        return backlogKinds.contains(kind);
      }).toList();

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final item in backlogItems) buildItemCard(item),
        ],
      );
    }

    if (planningView == BoardPlanningView.focus) {
      final now = DateTime.now();
      final soon = now.add(const Duration(days: 7));
      final flagged = visibleItems.where((item) {
        final column = columnsById[item.columnId];
        final isBlocked = column?.isBlockedState == true;
        final isUrgent = column?.kind == BoardColumnKind.urgent;
        final isOverdue = item.dueAt != null &&
            item.completedAt == null &&
            item.dueAt!.isBefore(now);
        final isDueSoon = item.dueAt != null &&
            item.completedAt == null &&
            !item.dueAt!.isBefore(now) &&
            !item.dueAt!.isAfter(soon);
        return isBlocked || isUrgent || isOverdue || isDueSoon;
      }).toList();

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Text('Focus queue (${flagged.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in flagged) buildItemCard(item),
        ],
      );
    }

    // Hierarchy view.
    final byId = {for (final item in visibleItems) item.itemId: item};
    final childrenByParent = <String?, List<WorkItem>>{};
    for (final item in visibleItems) {
      final parentKey = byId.containsKey(item.parentId) ? item.parentId : null;
      childrenByParent.putIfAbsent(parentKey, () => []).add(item);
    }

    void sortByPriority(List<WorkItem> items) {
      items.sort((a, b) {
        final byType = _typeRank(a.type).compareTo(_typeRank(b.type));
        if (byType != 0) return byType;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    for (final entry in childrenByParent.values) {
      sortByPriority(entry);
    }

    List<Widget> buildTree(String? parentId, int depth) {
      final nodes = childrenByParent[parentId] ?? const [];
      final rows = <Widget>[];
      for (final node in nodes) {
        final hasChildren =
            (childrenByParent[node.itemId] ?? const []).isNotEmpty;
        final isCollapsed = collapsedHierarchyItemIds.contains(node.itemId);
        rows.add(
          buildItemCard(
            node,
            hierarchyDepth: depth,
            showHierarchyGuides: true,
            hasChildren: hasChildren,
            isCollapsed: isCollapsed,
            onToggleCollapsed: !hasChildren
                ? null
                : () {
                    final next = <String>{...collapsedHierarchyItemIds};
                    if (!next.add(node.itemId)) {
                      next.remove(node.itemId);
                    }
                    ref.read(collapsedHierarchyItemIdsProvider.notifier).state =
                        next;
                  },
          ),
        );
        if (!isCollapsed) {
          rows.addAll(buildTree(node.itemId, depth + 1));
        }
      }
      return rows;
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: buildTree(null, 0),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(boardStreamProvider);
    final permissionProfile = ref.watch(boardPermissionProfileProvider);
    final canModifyItems =
        permissionProfile?.has(BoardCapability.modifyItems) ?? false;
    final canManageBoard =
        permissionProfile?.has(BoardCapability.manageBoard) ?? false;
    final canJoinInvite =
        permissionProfile?.has(BoardCapability.joinInvite) ?? false;
    final boardsAsync = ref.watch(boardsProvider);
    final currentBoardId = ref.watch(currentBoardIdProvider);
    final visibilityFilter = ref.watch(boardVisibilityFilterProvider);
    final planningView = ref.watch(boardPlanningViewProvider);
    final collapsedHierarchyItemIds =
        ref.watch(collapsedHierarchyItemIdsProvider);
    final stateFilter = ref.watch(boardItemStateFilterProvider);
    final tagFilter = ref.watch(boardTagFilterProvider);
    final selectedItemIds = ref.watch(selectedBoardItemIdsProvider);
    final focusedItemId = ref.watch(focusedItemIdProvider);
    final focusModeEnabled = ref.watch(focusModeEnabledProvider);
    final textQuery = ref.watch(boardTextQueryProvider);
    final searchExpanded = ref.watch(workspaceSearchExpandedProvider);
    final workspaceSurface = ref.watch(boardWorkspaceSurfaceProvider);
    final selectedBoardIds = ref.watch(workspaceSelectedBoardIdsProvider);
    final showOverdueOnly = ref.watch(showOverdueOnlyProvider);
    final showDueSoonOnly = ref.watch(showDueSoonOnlyProvider);
    final showArchivedOnly = ref.watch(showArchivedOnlyProvider);
    final cardDensity = ref.watch(boardCardDensityProvider);
    final lastAutoFocusedDoingBoardId =
        ref.watch(lastAutoFocusedDoingBoardIdProvider);
    final pendingOutboxCountAsync = ref.watch(pendingOutboxCountProvider);
    final pendingCount = pendingOutboxCountAsync.valueOrNull ?? 0;
    final outboxStatusAsync = ref.watch(outboxStatusProvider);
    final outboxStatus = outboxStatusAsync.valueOrNull;
    final syncUiState = ref.watch(syncUiStateProvider);
    final filterPresetsAsync = ref.watch(boardFilterPresetsProvider);
    final filterPresets =
        filterPresetsAsync.valueOrNull ?? const <BoardFilterPreset>[];
    final activeDraggedItem = ref.watch(activeDraggedItemProvider);
    final remindersAsync = ref.watch(boardActiveRemindersProvider);
    final reminderPreferencesAsync = ref.watch(notificationPreferencesProvider);
    final autofillSettingsAsync = ref.watch(autofillSettingsProvider);
    final compactAppBar = MediaQuery.sizeOf(context).width < 760;
    final inboxCount =
        boardAsync.valueOrNull?.items.where((item) => item.isInbox).length ?? 0;

    return AppPrimaryScaffold(
      activeRoute: AppRoutes.workspace,
      title: 'Workspace',
      actions: [
        IconButton(
          tooltip: 'Quick capture',
          onPressed: canModifyItems
              ? () => _showQuickCaptureDialog(context, ref)
              : () => _showActionFeedback(
                    context,
                    'Current role cannot create items in this board.',
                  ),
          icon: const Icon(Icons.flash_on_outlined),
        ),
        IconButton(
          tooltip: workspaceSurface == BoardWorkspaceSurface.inbox
              ? 'Show board'
              : 'Show inbox',
          onPressed: () {
            ref.read(boardWorkspaceSurfaceProvider.notifier).state =
                workspaceSurface == BoardWorkspaceSurface.inbox
                    ? BoardWorkspaceSurface.board
                    : BoardWorkspaceSurface.inbox;
          },
          icon: Badge(
            isLabelVisible: workspaceSurface != BoardWorkspaceSurface.inbox &&
                inboxCount > 0,
            label: Text('$inboxCount'),
            child: Icon(
              workspaceSurface == BoardWorkspaceSurface.inbox
                  ? Icons.inbox
                  : Icons.inbox_outlined,
            ),
          ),
        ),
        IconButton(
          tooltip: cardDensity == BoardCardDensity.compact
              ? 'Switch to comfortable density'
              : 'Switch to compact density',
          onPressed: () {
            ref.read(boardCardDensityProvider.notifier).state =
                cardDensity == BoardCardDensity.compact
                    ? BoardCardDensity.comfortable
                    : BoardCardDensity.compact;
          },
          icon: Icon(
            cardDensity == BoardCardDensity.compact
                ? Icons.density_large
                : Icons.density_small,
          ),
        ),
        if (remindersAsync.valueOrNull != null)
          IconButton(
            tooltip: 'Reminders',
            onPressed: () {
              final reminders = remindersAsync.valueOrNull ?? const [];
              final preferences = reminderPreferencesAsync.valueOrNull ??
                  const NotificationPreferences();
              _showReminderCenterSheet(
                context,
                ref,
                reminders: reminders,
                preferences: preferences,
              );
            },
            icon: Badge(
              isLabelVisible: (remindersAsync.valueOrNull?.length ?? 0) > 0,
              label: Text('${remindersAsync.valueOrNull?.length ?? 0}'),
              child: const Icon(Icons.notifications_none_outlined),
            ),
          ),
        IconButton(
          tooltip: 'Autofill suggestions',
          onPressed: () {
            final settings =
                autofillSettingsAsync.valueOrNull ?? const AutofillSettings();
            _showAutofillSettingsDialog(
              context,
              ref,
              initial: settings,
            );
          },
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
        if (compactAppBar)
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (value) async {
              if (value.startsWith('density:')) {
                final name = value.substring('density:'.length);
                final selected = BoardCardDensity.values.firstWhere(
                  (entry) => entry.name == name,
                  orElse: () => BoardCardDensity.comfortable,
                );
                ref.read(boardCardDensityProvider.notifier).state = selected;
                return;
              }
              if (value == 'autofill_preferences') {
                final settings = autofillSettingsAsync.valueOrNull ??
                    const AutofillSettings();
                await _showAutofillSettingsDialog(
                  context,
                  ref,
                  initial: settings,
                );
                return;
              }

              switch (value) {
                case 'clear_focus':
                  ref.read(focusedItemIdProvider.notifier).state = null;
                  ref.read(focusModeEnabledProvider.notifier).state = false;
                  break;
                case 'toggle_focus':
                  if (focusedItemId != null) {
                    final notifier =
                        ref.read(focusModeEnabledProvider.notifier);
                    notifier.state = !notifier.state;
                  }
                  break;
                case 'open_outbox':
                  await _showOutboxSheet(context, ref);
                  break;
                case 'sync_now':
                  if (syncUiState.isSyncing) return;
                  try {
                    final report = await ref
                        .read(boardControllerProvider)
                        .syncNow(ignoreRetrySchedule: true);
                    if (!context.mounted) return;
                    final deniedSegment = report.permissionDenied > 0
                        ? ', ${report.permissionDenied} permission denied'
                        : '';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Sync complete: ${report.processed} processed, ${report.failed} failed$deniedSegment',
                        ),
                      ),
                    );
                  } catch (error) {
                    if (!context.mounted) return;
                    _showActionFeedback(context, 'Sync failed: $error');
                  }
                  break;
                case 'accept_invite':
                  await _runGuardedAction(
                    context,
                    () => ref.read(boardControllerProvider).acceptInvite(),
                  );
                  break;
                case 'sign_out':
                  await ref.read(authControllerProvider).signOut();
                  break;
              }
            },
            itemBuilder: (_) => [
              for (final density in BoardCardDensity.values)
                PopupMenuItem(
                  value: 'density:${density.name}',
                  child: Row(
                    children: [
                      if (cardDensity == density)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(_densityLabel(density)),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'autofill_preferences',
                child: Text('Autofill suggestions'),
              ),
              const PopupMenuDivider(),
              if (focusedItemId != null)
                const PopupMenuItem(
                  value: 'clear_focus',
                  child: Text('Clear focus'),
                ),
              PopupMenuItem(
                value: 'toggle_focus',
                enabled: focusedItemId != null,
                child: Text(focusModeEnabled
                    ? 'Disable focus mode'
                    : 'Enable focus mode'),
              ),
              PopupMenuItem(
                value: 'open_outbox',
                child: Text('Pending sync operations ($pendingCount)'),
              ),
              PopupMenuItem(
                value: 'sync_now',
                enabled: !syncUiState.isSyncing,
                child: const Text('Sync now'),
              ),
              if (canJoinInvite)
                const PopupMenuItem(
                  value: 'accept_invite',
                  child: Text('Accept board invite'),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'sign_out',
                child: Text('Sign out'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.more_vert),
            ),
          )
        else ...[
          PopupMenuButton<BoardCardDensity>(
            tooltip: 'Card density',
            onSelected: (value) {
              ref.read(boardCardDensityProvider.notifier).state = value;
            },
            itemBuilder: (_) {
              return [
                for (final density in BoardCardDensity.values)
                  PopupMenuItem(
                    value: density,
                    child: Row(
                      children: [
                        if (density == cardDensity)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(_densityLabel(density)),
                      ],
                    ),
                  ),
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  _densityLabel(cardDensity),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ),
          if (focusedItemId != null)
            IconButton(
              tooltip: 'Clear focus',
              onPressed: () {
                ref.read(focusedItemIdProvider.notifier).state = null;
                ref.read(focusModeEnabledProvider.notifier).state = false;
              },
              icon: const Icon(Icons.center_focus_weak),
            ),
          IconButton(
            tooltip: 'Toggle focus mode',
            onPressed: focusedItemId == null
                ? null
                : () {
                    final notifier =
                        ref.read(focusModeEnabledProvider.notifier);
                    notifier.state = !notifier.state;
                  },
            icon: Icon(focusModeEnabled
                ? Icons.filter_center_focus
                : Icons.filter_center_focus_outlined),
          ),
          IconButton(
            tooltip: 'Pending sync operations',
            onPressed: () => _showOutboxSheet(context, ref),
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: syncUiState.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authControllerProvider).signOut();
            },
            icon: const Icon(Icons.logout),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: syncUiState.isSyncing
                ? null
                : () async {
                    try {
                      final report = await ref
                          .read(boardControllerProvider)
                          .syncNow(ignoreRetrySchedule: true);
                      if (!context.mounted) return;
                      final deniedSegment = report.permissionDenied > 0
                          ? ', ${report.permissionDenied} permission denied'
                          : '';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sync complete: ${report.processed} processed, ${report.failed} failed$deniedSegment',
                          ),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      _showActionFeedback(context, 'Sync failed: $error');
                    }
                  },
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          if (canJoinInvite)
            IconButton(
              tooltip: 'Accept board invite',
              onPressed: () {
                _runGuardedAction(
                  context,
                  () => ref.read(boardControllerProvider).acceptInvite(),
                );
              },
              icon: const Icon(Icons.how_to_reg_outlined),
            ),
        ],
        if (selectedItemIds.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Bulk actions',
            onSelected: (value) {
              final snapshot = ref.read(boardStreamProvider).valueOrNull;
              final columns = snapshot == null
                  ? const <BoardColumn>[]
                  : [...snapshot.columns]
                ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
              switch (value) {
                case 'bulk_move':
                  _showBulkMoveDialog(
                    context,
                    ref,
                    columns: columns,
                    selectedItemIds: selectedItemIds,
                  );
                  break;
                case 'bulk_archive':
                  _confirmDestructiveAction(
                    context,
                    title: 'Archive selected items?',
                    message:
                        'Archive ${selectedItemIds.length} selected item(s)?',
                    confirmLabel: 'Archive',
                  ).then((confirmed) {
                    if (!confirmed) return;
                    _runGuardedAction(
                      context,
                      () => ref.read(boardControllerProvider).bulkUpdateItems(
                            itemIds: selectedItemIds.toList(),
                            archived: true,
                          ),
                    );
                    ref.read(selectedBoardItemIdsProvider.notifier).state = {};
                  });
                  break;
                case 'bulk_unarchive':
                  _confirmDestructiveAction(
                    context,
                    title: 'Unarchive selected items?',
                    message:
                        'Unarchive ${selectedItemIds.length} selected item(s)?',
                    confirmLabel: 'Unarchive',
                  ).then((confirmed) {
                    if (!confirmed) return;
                    _runGuardedAction(
                      context,
                      () => ref.read(boardControllerProvider).bulkUpdateItems(
                            itemIds: selectedItemIds.toList(),
                            archived: false,
                          ),
                    );
                    ref.read(selectedBoardItemIdsProvider.notifier).state = {};
                  });
                  break;
                case 'bulk_add_tags':
                  _showBulkTagDialog(
                    context,
                    ref,
                    selectedItemIds: selectedItemIds,
                    remove: false,
                  );
                  break;
                case 'bulk_remove_tags':
                  _showBulkTagDialog(
                    context,
                    ref,
                    selectedItemIds: selectedItemIds,
                    remove: true,
                  );
                  break;
                case 'clear_selected':
                  ref.read(selectedBoardItemIdsProvider.notifier).state = {};
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'bulk_move',
                child: Text('Bulk move selected'),
              ),
              PopupMenuItem(
                value: 'bulk_archive',
                child: Text('Archive selected'),
              ),
              PopupMenuItem(
                value: 'bulk_unarchive',
                child: Text('Unarchive selected'),
              ),
              PopupMenuItem(
                value: 'bulk_add_tags',
                child: Text('Add tags to selected'),
              ),
              PopupMenuItem(
                value: 'bulk_remove_tags',
                child: Text('Remove tags from selected'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear_selected',
                child: Text('Clear selection'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Badge(
                label: Text('${selectedItemIds.length}'),
                child: const Icon(Icons.checklist_outlined),
              ),
            ),
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canModifyItems
            ? () => workspaceSurface == BoardWorkspaceSurface.inbox
                ? _showQuickCaptureDialog(context, ref)
                : _showAddTaskDialog(
                    context,
                    ref,
                    canManageBoard: canManageBoard,
                  )
            : () => _showActionFeedback(
                  context,
                  'Current role cannot create items in this board.',
                ),
        icon: Icon(workspaceSurface == BoardWorkspaceSurface.inbox
            ? Icons.flash_on_outlined
            : Icons.add),
        label: Text(workspaceSurface == BoardWorkspaceSurface.inbox
            ? 'Quick Capture'
            : 'Add Item'),
      ),
      body: boardAsync.when(
        data: (snapshot) {
          final boards = boardsAsync.valueOrNull ?? const [];
          final columns = [...snapshot.columns]
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          final columnsById = {
            for (final column in columns) column.columnId: column,
          };
          final allItemsById = {
            for (final entry in snapshot.items) entry.itemId: entry,
          };
          final hierarchyColorEnabled =
              snapshot.board.validationSettings.hierarchyColorGroupingByGoal;
          final goalColors = hierarchyColorEnabled
              ? resolveGoalColors(
                  items: snapshot.items,
                  overrides: snapshot
                      .board.validationSettings.hierarchyGoalColorOverrides,
                )
              : const <String, int>{};
          final allBoardIds = {for (final board in boards) board.boardId};
          final visibleBoardIds = selectedBoardIds.isEmpty
              ? allBoardIds
              : allBoardIds.intersection(selectedBoardIds);
          if (!visibleBoardIds.contains(currentBoardId) &&
              visibleBoardIds.isNotEmpty) {
            final fallbackBoardId = boards
                .where((board) => visibleBoardIds.contains(board.boardId))
                .map((board) => board.boardId)
                .first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(boardControllerProvider).switchBoard(fallbackBoardId);
            });
          }
          final focusRelatedItemIds = focusedItemId == null
              ? null
              : _focusRelatedItemIds(snapshot.items, focusedItemId);
          final screenWidth = MediaQuery.sizeOf(context).width;
          final compactDensity = cardDensity == BoardCardDensity.compact;
          const compactLikeWidthFactor = 0.8;
          const compactLikeMinWidth = 230.0;
          const compactLikeMaxWidth = 320.0;
          const compactLikeDesktopWidth = 300.0;
          final columnWidth = screenWidth < 900
              ? (screenWidth * compactLikeWidthFactor)
                  .clamp(compactLikeMinWidth, compactLikeMaxWidth)
              : compactLikeDesktopWidth;
          final doingColumn = columns
              .where((column) => column.kind == BoardColumnKind.inProgress)
              .cast<BoardColumn?>()
              .firstWhere((_) => true, orElse: () => null);
          final doingColumnAnchorKey = GlobalKey();
          final visibleItemsByColumn = {
            for (final column in columns)
              column.columnId: _sortedVisibleItems(
                items: snapshot.items,
                columnId: column.columnId,
                filter: visibilityFilter,
                stateFilter: stateFilter,
                focusModeEnabled: focusModeEnabled,
                focusRelatedItemIds: focusRelatedItemIds,
                textQuery: textQuery,
                tagFilter: tagFilter,
                columnsById: columnsById,
                showOverdueOnly: showOverdueOnly,
                showDueSoonOnly: showDueSoonOnly,
                showArchivedOnly: showArchivedOnly,
              ),
          };
          final pendingWithRetry = outboxStatus?.retryScheduledCount ?? 0;
          final syncBannerText = switch ((
            syncUiState.isSyncing,
            pendingCount,
            pendingWithRetry,
            syncUiState.lastError,
            syncUiState.lastReport?.permissionDenied ?? 0,
          )) {
            (true, _, _, _, _) => 'Sync in progress...',
            (false, > 0, > 0, _, _) =>
              'Pending changes: $pendingCount. Auto-retry scheduled for ${outboxStatus?.nextRetryAt == null ? 'soon' : _formatRetryTime(outboxStatus!.nextRetryAt!)}.',
            (false, > 0, _, _, _) => 'Pending changes: $pendingCount.',
            (false, _, _, final String? error, _) when error != null => error,
            (false, _, _, _, > 0) =>
              'Some changes were denied by permissions and were dropped. Review role/access.',
            _ => null,
          };
          final shouldAutoFocusDoingColumn =
              workspaceSurface == BoardWorkspaceSurface.board &&
                  planningView == BoardPlanningView.kanban &&
                  doingColumn != null &&
                  lastAutoFocusedDoingBoardId != currentBoardId;
          if (shouldAutoFocusDoingColumn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final anchorContext = doingColumnAnchorKey.currentContext;
              if (anchorContext != null) {
                Scrollable.ensureVisible(
                  anchorContext,
                  alignment: 0.04,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                );
              }
              ref.read(lastAutoFocusedDoingBoardIdProvider.notifier).state =
                  currentBoardId;
            });
          }

          return Column(
            children: [
              const _WorkspaceSyncLifecycleBridge(),
              if (syncBannerText != null)
                MaterialBanner(
                  content: Text(syncBannerText),
                  leading: syncUiState.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  actions: [
                    if (!syncUiState.isSyncing && pendingCount > 0)
                      TextButton(
                        onPressed: () {
                          ref
                              .read(boardControllerProvider)
                              .syncNow(ignoreRetrySchedule: true);
                        },
                        child: const Text('Retry now'),
                      ),
                  ],
                ),
              if ((remindersAsync.valueOrNull?.isNotEmpty ?? false))
                MaterialBanner(
                  content: Text(
                    '${remindersAsync.valueOrNull!.first.title}: ${remindersAsync.valueOrNull!.first.message}',
                  ),
                  leading: Icon(
                    remindersAsync.valueOrNull!.first.isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.notifications_active_outlined,
                    color: remindersAsync.valueOrNull!.first.isOverdue
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _runGuardedAction(
                        context,
                        () => ref.read(boardControllerProvider).snoozeReminder(
                              reminderId:
                                  remindersAsync.valueOrNull!.first.reminderId,
                            ),
                      ),
                      child: const Text('Snooze'),
                    ),
                    TextButton(
                      onPressed: () => _runGuardedAction(
                        context,
                        () => ref
                            .read(boardControllerProvider)
                            .muteReminders(const Duration(hours: 8)),
                      ),
                      child: const Text('Mute 8h'),
                    ),
                    TextButton(
                      onPressed: () {
                        final preferences =
                            reminderPreferencesAsync.valueOrNull ??
                                const NotificationPreferences();
                        _showReminderCenterSheet(
                          context,
                          ref,
                          reminders: remindersAsync.valueOrNull!,
                          preferences: preferences,
                        );
                      },
                      child: const Text('View all'),
                    ),
                  ],
                ),
              if (activeDraggedItem != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.65),
                  child: SizedBox(
                    height: 62,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final column in columns)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: DragTarget<WorkItem>(
                              onWillAcceptWithDetails: (details) {
                                return details.data.boardId == currentBoardId &&
                                    details.data.columnId != column.columnId;
                              },
                              onAcceptWithDetails: (details) {
                                if (!canModifyItems) {
                                  _showActionFeedback(
                                    context,
                                    'Current role cannot modify items in this board.',
                                  );
                                  return;
                                }
                                _moveItemWithUndo(
                                  context,
                                  ref,
                                  item: details.data,
                                  toColumnId: column.columnId,
                                );
                              },
                              builder: (context, candidateData, rejectedData) {
                                final isDropActive = candidateData.any(
                                  (it) =>
                                      it != null &&
                                      it.boardId == currentBoardId &&
                                      it.columnId != column.columnId,
                                );
                                return Chip(
                                  avatar: Icon(
                                    isDropActive
                                        ? Icons.move_down
                                        : Icons.drag_indicator,
                                    size: 20,
                                  ),
                                  label: Text(
                                    column.name,
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  backgroundColor: isDropActive
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  labelPadding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  side: BorderSide(
                                    color: isDropActive
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    if (!searchExpanded) ...[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showBoardSelectionSheet(
                            context,
                            ref,
                            boards: boards,
                            selectedBoardIds: selectedBoardIds,
                            currentBoardId: currentBoardId,
                          ),
                          icon: const Icon(Icons.view_list_outlined),
                          label:
                              Text(_boardScopeLabel(boards, selectedBoardIds)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Filter items',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _showWorkspaceFiltersSheet(
                            context,
                            ref,
                            visibilityFilter: visibilityFilter,
                            stateFilter: stateFilter,
                            tagFilter: tagFilter,
                            showOverdueOnly: showOverdueOnly,
                            showDueSoonOnly: showDueSoonOnly,
                            showArchivedOnly: showArchivedOnly,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.filter_list, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Filter presets',
                        onPressed: () => _showFilterPresetsSheet(
                          context,
                          ref,
                          presets: filterPresets,
                        ),
                        icon: Badge(
                          isLabelVisible: filterPresets.isNotEmpty,
                          label: Text('${filterPresets.length}'),
                          child: const Icon(Icons.bookmarks_outlined),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Search items',
                        onPressed: () {
                          ref
                              .read(workspaceSearchExpandedProvider.notifier)
                              .state = true;
                        },
                        icon: Badge(
                          isLabelVisible: textQuery.trim().isNotEmpty,
                          child: const Icon(Icons.search),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: TextFormField(
                          initialValue: textQuery,
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search items by title',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            ref.read(boardTextQueryProvider.notifier).state =
                                value;
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Collapse search',
                        onPressed: () {
                          ref
                              .read(workspaceSearchExpandedProvider.notifier)
                              .state = false;
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ],
                ),
              ),
              if (focusModeEnabled && focusedItemId != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  child: Text(
                    'Focus mode: showing selected item context (ancestors + descendants)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              Expanded(
                child: workspaceSurface == BoardWorkspaceSurface.inbox
                    ? _buildInboxView(
                        context: context,
                        ref: ref,
                        allItems: snapshot.items,
                        columns: columns,
                        boards: boards,
                        canModifyItems: canModifyItems,
                        selectedItemIds: selectedItemIds,
                        focusedItemId: focusedItemId,
                        density: cardDensity,
                        settings: snapshot.board.validationSettings,
                      )
                    : planningView == BoardPlanningView.kanban
                        ? ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              SizedBox(
                                width: 36,
                                child: Column(
                                  children: [
                                    IconButton(
                                      tooltip: 'Move first column right',
                                      onPressed: !canManageBoard
                                          ? null
                                          : columns.length > 1
                                              ? () {
                                                  final ordered = [
                                                    for (final c in columns)
                                                      c.columnId
                                                  ];
                                                  final first =
                                                      ordered.removeAt(0);
                                                  ordered.insert(1, first);
                                                  _runGuardedAction(
                                                    context,
                                                    () => ref
                                                        .read(
                                                            boardControllerProvider)
                                                        .reorderColumns(
                                                            ordered),
                                                  );
                                                }
                                              : null,
                                      icon: const Icon(Icons.arrow_forward),
                                    ),
                                  ],
                                ),
                              ),
                              for (final column in columns)
                                KeyedSubtree(
                                  key: doingColumn != null &&
                                          column.columnId ==
                                              doingColumn.columnId
                                      ? doingColumnAnchorKey
                                      : null,
                                  child: SizedBox(
                                    width: columnWidth,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: compactDensity ? 4 : 8,
                                        horizontal: compactDensity ? 2 : 4,
                                      ),
                                      child: Card(
                                        child: Padding(
                                          padding: EdgeInsets.all(
                                              compactDensity ? 8 : 12),
                                          child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Tooltip(
                                                    message: column.name,
                                                    child: Text(
                                                      column.name,
                                                      maxLines: compactDensity
                                                          ? 2
                                                          : 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: compactDensity
                                                          ? Theme.of(context)
                                                              .textTheme
                                                              .titleSmall
                                                          : Theme.of(context)
                                                              .textTheme
                                                              .titleMedium,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Column semantics',
                                                  onPressed: canManageBoard
                                                      ? () =>
                                                          _showColumnSemanticsDialog(
                                                            context,
                                                            ref,
                                                            column: column,
                                                          )
                                                      : null,
                                                  icon: const Icon(Icons.tune,
                                                      size: 18),
                                                ),
                                                IconButton(
                                                  tooltip: 'Rename column',
                                                  onPressed: canManageBoard
                                                      ? () =>
                                                          _showRenameColumnDialog(
                                                            context,
                                                            ref,
                                                            columnId:
                                                                column.columnId,
                                                            currentName:
                                                                column.name,
                                                          )
                                                      : null,
                                                  icon: const Icon(Icons.edit,
                                                      size: 18),
                                                ),
                                                IconButton(
                                                  tooltip: 'Move left',
                                                  onPressed: !canManageBoard
                                                      ? null
                                                      : () {
                                                          final index = columns
                                                              .indexWhere((c) =>
                                                                  c.columnId ==
                                                                  column
                                                                      .columnId);
                                                          if (index <= 0) {
                                                            return;
                                                          }
                                                          final ordered = [
                                                            for (final c
                                                                in columns)
                                                              c.columnId
                                                          ];
                                                          final id = ordered
                                                              .removeAt(index);
                                                          ordered.insert(
                                                              index - 1, id);
                                                          _runGuardedAction(
                                                            context,
                                                            () => ref
                                                                .read(
                                                                    boardControllerProvider)
                                                                .reorderColumns(
                                                                    ordered),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                      Icons.chevron_left),
                                                ),
                                                IconButton(
                                                  tooltip: 'Move right',
                                                  onPressed: !canManageBoard
                                                      ? null
                                                      : () {
                                                          final index = columns
                                                              .indexWhere((c) =>
                                                                  c.columnId ==
                                                                  column
                                                                      .columnId);
                                                          if (index < 0 ||
                                                              index >=
                                                                  columns.length -
                                                                      1) {
                                                            return;
                                                          }
                                                          final ordered = [
                                                            for (final c
                                                                in columns)
                                                              c.columnId
                                                          ];
                                                          final id = ordered
                                                              .removeAt(index);
                                                          ordered.insert(
                                                              index + 1, id);
                                                          _runGuardedAction(
                                                            context,
                                                            () => ref
                                                                .read(
                                                                    boardControllerProvider)
                                                                .reorderColumns(
                                                                    ordered),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                      Icons.chevron_right),
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete column',
                                                  onPressed: canManageBoard
                                                      ? () =>
                                                          _confirmDeleteColumn(
                                                            context,
                                                            ref,
                                                            columnId:
                                                                column.columnId,
                                                            name: column.name,
                                                            canDelete:
                                                                columns.length >
                                                                    1,
                                                          )
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 18),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Builder(
                                              builder: (_) {
                                                final visibleItems =
                                                    visibleItemsByColumn[
                                                            column.columnId] ??
                                                        const <WorkItem>[];

                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 6),
                                                  child: Text(
                                                    '${visibleItems.length} item(s)',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium,
                                                  ),
                                                );
                                              },
                                            ),
                                            Expanded(
                                              child: DragTarget<WorkItem>(
                                                onWillAcceptWithDetails:
                                                    (details) {
                                                  return details
                                                          .data.columnId !=
                                                      column.columnId;
                                                },
                                                onAcceptWithDetails: (details) {
                                                  final movedItem =
                                                      details.data;
                                                  if (movedItem.columnId ==
                                                      column.columnId) {
                                                    return;
                                                  }
                                                  if (!canModifyItems) {
                                                    _showActionFeedback(
                                                      context,
                                                      'Current role cannot modify items in this board.',
                                                    );
                                                    return;
                                                  }
                                                  _moveItemWithUndo(
                                                    context,
                                                    ref,
                                                    item: movedItem,
                                                    toColumnId: column.columnId,
                                                  );
                                                },
                                                builder: (context,
                                                    candidateData,
                                                    rejectedData) {
                                                  final isDropActive =
                                                      candidateData.any(
                                                    (item) =>
                                                        item != null &&
                                                        item.columnId !=
                                                            column.columnId,
                                                  );

                                                  return AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 120),
                                                    decoration: BoxDecoration(
                                                      color: isDropActive
                                                          ? Theme.of(context)
                                                              .colorScheme
                                                              .primaryContainer
                                                              .withValues(
                                                                  alpha: 0.35)
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                        color: isDropActive
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                            : Colors
                                                                .transparent,
                                                      ),
                                                    ),
                                                    child: ListView(
                                                      padding: EdgeInsets.all(
                                                        compactDensity ? 2 : 4,
                                                      ),
                                                      children: [
                                                        for (final item
                                                            in visibleItemsByColumn[
                                                                    column
                                                                        .columnId] ??
                                                                const <WorkItem>[])
                                                          BoardItemTile(
                                                            item: item,
                                                            columns: columns,
                                                            allItems:
                                                                snapshot.items,
                                                            density:
                                                                cardDensity,
                                                            parentPathMode: snapshot
                                                                .board
                                                                .validationSettings
                                                                .hierarchyParentPathMode,
                                                            focused:
                                                                focusedItemId ==
                                                                    item.itemId,
                                                            selected:
                                                                selectedItemIds
                                                                    .contains(item
                                                                        .itemId),
                                                            childCount: snapshot
                                                                .items
                                                                .where((x) =>
                                                                    x.parentId ==
                                                                    item.itemId)
                                                                .length,
                                                            onSelect: () {
                                                              ref
                                                                  .read(focusedItemIdProvider
                                                                      .notifier)
                                                                  .state = item.itemId;
                                                            },
                                                            onAddChildAction:
                                                                () {
                                                              _showQuickAddChildActionDialog(
                                                                context,
                                                                ref,
                                                                parent: item,
                                                                columns:
                                                                    columns,
                                                              );
                                                            },
                                                            onEdit: () {
                                                              _showEditItemSheet(
                                                                context,
                                                                ref,
                                                                item: item,
                                                                allItems:
                                                                    snapshot
                                                                        .items,
                                                                settings: snapshot
                                                                    .board
                                                                    .validationSettings,
                                                              );
                                                            },
                                                            onViewDetails: () {
                                                              _showItemDetailsSheet(
                                                                context,
                                                                ref,
                                                                item: item,
                                                                allItems:
                                                                    snapshot
                                                                        .items,
                                                                settings: snapshot
                                                                    .board
                                                                    .validationSettings,
                                                              );
                                                            },
                                                            onToggleArchive:
                                                                () {
                                                              _toggleArchiveWithUndo(
                                                                context,
                                                                ref,
                                                                item: item,
                                                              );
                                                            },
                                                            onMoveToColumn:
                                                                (toColumnId) =>
                                                                    _moveItemWithUndo(
                                                              context,
                                                              ref,
                                                              item: item,
                                                              toColumnId:
                                                                  toColumnId,
                                                            ),
                                                            onToggleSelected: () =>
                                                                _toggleItemSelection(
                                                              ref,
                                                              item.itemId,
                                                            ),
                                                            onReparent:
                                                                canModifyItems
                                                                    ? () =>
                                                                        _showReparentDialog(
                                                                          context,
                                                                          ref,
                                                                          item:
                                                                              item,
                                                                          allItems:
                                                                              snapshot.items,
                                                                        )
                                                                    : null,
                                                            onJumpToParent:
                                                                item.parentId ==
                                                                        null
                                                                    ? null
                                                                    : () {
                                                                        ref.read(boardVisibilityFilterProvider.notifier).state =
                                                                            BoardVisibilityFilter.allItems;
                                                                        ref.read(focusedItemIdProvider.notifier).state =
                                                                            item.parentId;
                                                                        ref.read(focusModeEnabledProvider.notifier).state =
                                                                            true;
                                                                      },
                                                            onDelete:
                                                                canModifyItems
                                                                    ? () =>
                                                                        _deleteItemWithUndo(
                                                                          context,
                                                                          ref,
                                                                          item:
                                                                              item,
                                                                          allItems:
                                                                              snapshot.items,
                                                                        )
                                                                    : null,
                                                            canModifyItems:
                                                                canModifyItems,
                                                            accentColor:
                                                                !hierarchyColorEnabled
                                                                    ? null
                                                                    : (() {
                                                                        final topGoalId =
                                                                            topLevelGoalIdForItem(
                                                                          item,
                                                                          allItemsById,
                                                                        );
                                                                        final accentColorValue = topGoalId ==
                                                                                null
                                                                            ? null
                                                                            : goalColors[topGoalId];
                                                                        return accentColorValue ==
                                                                                null
                                                                            ? null
                                                                            : Color(accentColorValue);
                                                                      })(),
                                                          ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : _buildAlternativeView(
                            context: context,
                            ref: ref,
                            planningView: planningView,
                            columns: columns,
                            allItems: snapshot.items,
                            filter: visibilityFilter,
                            stateFilter: stateFilter,
                            focusModeEnabled: focusModeEnabled,
                            focusRelatedItemIds: focusRelatedItemIds,
                            textQuery: textQuery,
                            tagFilter: tagFilter,
                            columnsById: columnsById,
                            showOverdueOnly: showOverdueOnly,
                            showDueSoonOnly: showDueSoonOnly,
                            showArchivedOnly: showArchivedOnly,
                            focusedItemId: focusedItemId,
                            canModifyItems: canModifyItems,
                            collapsedHierarchyItemIds:
                                collapsedHierarchyItemIds,
                            selectedItemIds: selectedItemIds,
                            density: cardDensity,
                            settings: snapshot.board.validationSettings,
                          ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _WorkspaceSyncLifecycleBridge extends ConsumerStatefulWidget {
  const _WorkspaceSyncLifecycleBridge();

  @override
  ConsumerState<_WorkspaceSyncLifecycleBridge> createState() =>
      _WorkspaceSyncLifecycleBridgeState();
}

class _WorkspaceSyncLifecycleBridgeState
    extends ConsumerState<_WorkspaceSyncLifecycleBridge>
    with WidgetsBindingObserver {
  bool _syncInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoSync(force: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync(force: true);
    }
  }

  Future<void> _triggerAutoSync({required bool force}) async {
    if (!mounted || !useFirebaseSync || _syncInFlight) return;
    final pendingCount = await ref.read(pendingOutboxCountProvider.future);
    if (pendingCount <= 0) return;

    _syncInFlight = true;
    try {
      await ref.read(boardControllerProvider).syncNow(
            ignoreRetrySchedule: force,
          );
    } catch (_) {
      // Best-effort background sync; UI shows latest sync status.
    } finally {
      _syncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(
      pendingOutboxCountProvider.select((value) => value.valueOrNull),
      (previous, next) {
        if (!useFirebaseSync) return;
        final nextCount = next ?? 0;
        final previousCount = previous ?? 0;
        if (nextCount > 0 && nextCount > previousCount) {
          _triggerAutoSync(force: false);
        }
      },
    );
    return const SizedBox.shrink();
  }
}

class _HierarchyGuidePainter extends CustomPainter {
  const _HierarchyGuidePainter({
    required this.depth,
    required this.color,
  });

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < depth; i++) {
      final x = (i * 10.0) + 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final connectorStartX = ((depth - 1) * 10.0) + 5;
    final connectorEndX = size.width;
    final midY = size.height * 0.5;
    canvas.drawLine(
        Offset(connectorStartX, midY), Offset(connectorEndX, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _HierarchyGuidePainter oldDelegate) {
    return oldDelegate.depth != depth || oldDelegate.color != color;
  }
}
